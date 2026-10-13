import AppKit
import ScreenCaptureKit

struct RunningAppItem: Identifiable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage
    var windows: [WindowItem]

    var id: pid_t { pid }
}

struct WindowItem: Identifiable {
    let id: String
    let title: String
    let bounds: CGRect
    let element: AXUIElement
    var thumbnail: NSImage?
}

struct WindowThumbnailRequest {
    let id: String
    let pid: pid_t
    let title: String
    let bounds: CGRect
}

enum SwitcherPhase {
    case apps
    case windows
}

final class SwitcherStore: ObservableObject {
    private static let recentAppsDefaultsKey = "recentlyActivatedApplicationBundleIdentifiers"

    @Published private(set) var apps: [RunningAppItem] = []
    @Published private(set) var phase: SwitcherPhase = .apps
    @Published private(set) var isVisible = false
    @Published var selectedAppIndex = 0
    @Published var selectedWindowIndex = 0
    private var capturePreviews = false
    private var captureGeneration = UUID()
    private var recentBundleIdentifiers = UserDefaults.standard.stringArray(forKey: recentAppsDefaultsKey) ?? []

    var onVisibilityChanged: ((Bool) -> Void)?

    var selectedApp: RunningAppItem? {
        guard apps.indices.contains(selectedAppIndex) else { return nil }
        return apps[selectedAppIndex]
    }

    var selectedWindow: WindowItem? {
        guard let selectedApp, selectedApp.windows.indices.contains(selectedWindowIndex) else { return nil }
        return selectedApp.windows[selectedWindowIndex]
    }

    func show(capturePreviews: Bool) {
        refresh()
        guard !apps.isEmpty else {
            isVisible = false
            onVisibilityChanged?(false)
            return
        }

        phase = .apps
        selectedWindowIndex = 0
        selectedAppIndex = indexForFirstSelection()
        self.capturePreviews = capturePreviews
        captureGeneration = UUID()
        isVisible = true
        onVisibilityChanged?(true)
        if capturePreviews {
            refreshWindowThumbnails(for: apps.compactMap { app in
                app.windows.first.map { window in
                    WindowThumbnailRequest(
                        id: window.id,
                        pid: app.pid,
                        title: window.title,
                        bounds: window.bounds
                    )
                }
            })
        }
    }

    func hide() {
        guard isVisible else { return }
        captureGeneration = UUID()
        isVisible = false
        onVisibilityChanged?(false)
        apps = []
    }

    func cancel() {
        hide()
    }

    func refresh() {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           frontmostApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            noteApplicationActivation(bundleIdentifier: frontmostApp.bundleIdentifier)
        }
        apps = WindowDiscovery.snapshot(recentBundleIdentifiers: recentBundleIdentifiers)
    }

    func noteApplicationActivation(bundleIdentifier: String?) {
        guard let bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier else { return }

        recentBundleIdentifiers.removeAll { $0 == bundleIdentifier }
        recentBundleIdentifiers.insert(bundleIdentifier, at: 0)
        UserDefaults.standard.set(recentBundleIdentifiers, forKey: Self.recentAppsDefaultsKey)
    }

    func cycleApp(forward: Bool = true) {
        guard !apps.isEmpty else { return }
        selectedAppIndex = (selectedAppIndex + (forward ? 1 : -1) + apps.count) % apps.count
        selectedWindowIndex = 0
    }

    func selectApp(at index: Int) {
        guard apps.indices.contains(index) else { return }
        selectedAppIndex = index
        selectedWindowIndex = 0
    }

    func enterWindows() {
        guard let selectedApp else { return }

        guard selectedApp.windows.count > 1 else {
            activateSelection()
            return
        }

        phase = .windows
        selectedWindowIndex = 0
        if capturePreviews {
            refreshWindowThumbnails(for: selectedApp.windows.map { window in
                WindowThumbnailRequest(
                    id: window.id,
                    pid: selectedApp.pid,
                    title: window.title,
                    bounds: window.bounds
                )
            })
        }
    }

    func cycleWindow(forward: Bool = true) {
        guard let selectedApp, !selectedApp.windows.isEmpty else { return }
        selectedWindowIndex = (selectedWindowIndex + (forward ? 1 : -1) + selectedApp.windows.count) % selectedApp.windows.count
    }

    func moveWindow(rowDelta: Int, columnDelta: Int) {
        guard let selectedApp, !selectedApp.windows.isEmpty else { return }

        // Windows are presented in a single horizontal strip, so navigation
        // must traverse the entire array instead of stopping at a grid column.
        let delta = columnDelta != 0 ? columnDelta : rowDelta
        guard delta != 0 else { return }
        selectedWindowIndex = min(
            max(selectedWindowIndex + delta, 0),
            selectedApp.windows.count - 1
        )
    }

    func activateSelection() {
        guard let selectedApp else {
            hide()
            return
        }

        if let selectedWindow {
            WindowActivator.activate(window: selectedWindow, for: selectedApp)
        } else if let app = NSRunningApplication(processIdentifier: selectedApp.pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        hide()
    }

    private func indexForFirstSelection() -> Int {
        guard apps.count > 1 else { return 0 }
        return 1
    }

    private func refreshWindowThumbnails(for requests: [WindowThumbnailRequest]) {
        let generation = captureGeneration
        WindowDiscovery.loadWindowThumbnails(for: requests) { [weak self] thumbnails in
            guard let self,
                  self.isVisible,
                  self.captureGeneration == generation,
                  !thumbnails.isEmpty
            else { return }

            var updatedApps = self.apps
            for appIndex in updatedApps.indices {
                for windowIndex in updatedApps[appIndex].windows.indices {
                    let id = updatedApps[appIndex].windows[windowIndex].id
                    if let thumbnail = thumbnails[id] {
                        updatedApps[appIndex].windows[windowIndex].thumbnail = thumbnail
                    }
                }
            }
            self.apps = updatedApps
        }
    }

}

enum WindowDiscovery {
    private struct AccessibilityWindowInfo {
        let title: String
        let bounds: CGRect?
        let element: AXUIElement
    }

    static func snapshot(recentBundleIdentifiers: [String]) -> [RunningAppItem] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let recentPositions = Dictionary(
            recentBundleIdentifiers.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.processIdentifier != currentPID &&
                app.activationPolicy == .regular &&
                app.localizedName != nil
            }
            .sorted { lhs, rhs in
                if lhs.processIdentifier == frontmostPID { return true }
                if rhs.processIdentifier == frontmostPID { return false }
                let lhsPosition = lhs.bundleIdentifier.flatMap { recentPositions[$0] } ?? Int.max
                let rhsPosition = rhs.bundleIdentifier.flatMap { recentPositions[$0] } ?? Int.max
                if lhsPosition != rhsPosition { return lhsPosition < rhsPosition }
                return (lhs.localizedName ?? "") < (rhs.localizedName ?? "")
            }

        return runningApps.map { app in
            let axWindows = accessibilityWindows(for: app.processIdentifier)
            let windows = axWindows.enumerated().compactMap { index, axWindow -> WindowItem? in
                let bounds = axWindow.bounds ?? CGRect(x: 0, y: 0, width: 800, height: 600)
                guard axWindow.bounds == nil || (bounds.width > 80 && bounds.height > 40) else { return nil }
                let title = axWindow.title.isEmpty ? "Untitled window" : axWindow.title
                return WindowItem(
                    id: "\(app.processIdentifier):\(index):\(title)",
                    title: title,
                    bounds: bounds,
                    element: axWindow.element,
                    thumbnail: nil
                )
            }

            return RunningAppItem(
                pid: app.processIdentifier,
                name: app.localizedName ?? "Application",
                bundleIdentifier: app.bundleIdentifier,
                icon: app.icon ?? NSImage(size: NSSize(width: 64, height: 64)),
                windows: windows
            )
        }
    }

    private static func accessibilityWindows(for pid: pid_t) -> [AccessibilityWindowInfo] {
        let axApp = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return [] }

        return windows.map { window in
            var titleValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)

            var documentValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &documentValue)

            var positionValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
            var sizeValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)

            let windowTitle = (titleValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let documentTitle = documentDisplayName(from: documentValue as? String)

            return AccessibilityWindowInfo(
                title: windowTitle.isEmpty ? documentTitle : windowTitle,
                bounds: bounds(position: positionValue, size: sizeValue),
                element: window
            )
        }
    }

    private static func documentDisplayName(from value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        if let url = URL(string: value), url.isFileURL {
            return url.lastPathComponent
        }
        return (value as NSString).lastPathComponent
    }

    private static func bounds(position: CFTypeRef?, size: CFTypeRef?) -> CGRect? {
        guard let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }

        let positionValue = position as! AXValue
        let sizeValue = size as! AXValue
        var point = CGPoint.zero
        var windowSize = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &windowSize)
        else { return nil }
        return CGRect(origin: point, size: windowSize)
    }

    static func loadWindowThumbnails(
        for requests: [WindowThumbnailRequest],
        completion: @escaping ([String: NSImage]) -> Void
    ) {
        guard #available(macOS 14.0, *), !requests.isEmpty else {
            completion([:])
            return
        }

        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, _ in
            guard let content else {
                DispatchQueue.main.async { completion([:]) }
                return
            }

            var availableWindows = content.windows
            var matches: [(WindowThumbnailRequest, SCWindow)] = []

            for request in requests {
                let candidates = availableWindows.enumerated().filter { _, window in
                    window.owningApplication?.processID == request.pid
                }
                guard let best = candidates.min(by: { lhs, rhs in
                    captureMatchScore(request: request, window: lhs.element) <
                        captureMatchScore(request: request, window: rhs.element)
                }) else { continue }

                matches.append((request, best.element))
                availableWindows.remove(at: best.offset)
            }

            let group = DispatchGroup()
            let lock = NSLock()
            var images: [String: NSImage] = [:]

            for (request, window) in matches {
                let configuration = SCStreamConfiguration()
                let width = 480
                let aspectRatio = max(0.2, window.frame.height / max(window.frame.width, 1))
                configuration.width = width
                configuration.height = max(120, Int(CGFloat(width) * aspectRatio))
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true

                let filter = SCContentFilter(desktopIndependentWindow: window)
                group.enter()
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
                    if let image {
                        let thumbnail = NSImage(cgImage: image, size: window.frame.size)
                        lock.lock()
                        images[request.id] = thumbnail
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                completion(images)
            }
        }
    }

    @available(macOS 14.0, *)
    private static func captureMatchScore(request: WindowThumbnailRequest, window: SCWindow) -> CGFloat {
        let titlePenalty: CGFloat
        if request.title == "Untitled window" || window.title == nil {
            titlePenalty = 0
        } else {
            titlePenalty = window.title == request.title ? 0 : 10_000
        }

        return titlePenalty +
            abs(request.bounds.midX - window.frame.midX) +
            abs(request.bounds.midY - window.frame.midY) +
            abs(request.bounds.width - window.frame.width) +
            abs(request.bounds.height - window.frame.height)
    }

}

enum WindowActivator {
    static func activate(window: WindowItem, for app: RunningAppItem) {
        guard let runningApp = NSRunningApplication(processIdentifier: app.pid) else { return }
        runningApp.activate(options: [.activateIgnoringOtherApps])

        let axApp = AXUIElementCreateApplication(app.pid)
        _ = AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, window.element)
        _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }
}
