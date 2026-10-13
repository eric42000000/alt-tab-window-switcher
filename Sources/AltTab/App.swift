import AppKit
import SwiftUI

@main
struct AltTabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum DefaultsKey {
        static let requestedScreenCapture = "requestedScreenCapturePermission"
        static let showAfterRelaunch = "showSwitcherAfterPermissionRelaunch"
    }

    private let store = SwitcherStore()
    private var panelController: SwitcherPanelController!
    private var eventMonitor: CommandTabMonitor!
    private var statusItem: NSStatusItem!
    private var screenCaptureAuthorizedAtLaunch = false
    private var isRequestingScreenCapture = false
    private var waitingForScreenCaptureSettings = false
    private var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        screenCaptureAuthorizedAtLaunch = CGPreflightScreenCaptureAccess()

        panelController = SwitcherPanelController(store: store)
        eventMonitor = CommandTabMonitor(store: store)
        eventMonitor.onShowRequested = { [weak self] in
            self?.requestShowSwitcher()
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.store.noteApplicationActivation(bundleIdentifier: application?.bundleIdentifier)
        }

        store.onVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            self.eventMonitor.setOverlayActive(visible)
            if visible {
                self.panelController.show()
            } else {
                self.panelController.hide()
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "⌘⇥"
        statusItem.button?.toolTip = "AltTab window switcher"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Enable Keyboard Shortcut…", action: #selector(requestAccessibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Screen Recording Settings…", action: #selector(openScreenRecordingSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit AltTab", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        if isOtherAltTabRunning {
            statusItem.button?.toolTip = "AltTab Window Switcher is paused because another AltTab app is running"
            showShortcutConflictAlert()
        } else {
            requestAccessibility()
            if !AXIsProcessTrusted() || !eventMonitor.start() {
                statusItem.button?.toolTip = "AltTab Window Switcher needs Accessibility access"
                showAccessibilityAlert()
            }
        }

        if UserDefaults.standard.bool(forKey: DefaultsKey.showAfterRelaunch) {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.showAfterRelaunch)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.requestShowSwitcher()
            }
        }

    }

    @objc private func showSwitcher() {
        requestShowSwitcher()
    }

    @objc private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func requestShowSwitcher() {
        guard !store.isVisible, !isRequestingScreenCapture else { return }

        if CGPreflightScreenCaptureAccess() {
            if screenCaptureAuthorizedAtLaunch {
                store.show(capturePreviews: true)
            } else {
                relaunchAndShowSwitcher()
            }
            return
        }

        let defaults = UserDefaults.standard
        if defaults.bool(forKey: DefaultsKey.requestedScreenCapture) {
            showScreenCaptureAccessAlert()
            return
        }

        isRequestingScreenCapture = true
        defaults.set(true, forKey: DefaultsKey.requestedScreenCapture)
        let granted = CGRequestScreenCaptureAccess()
        isRequestingScreenCapture = false

        if granted {
            relaunchAndShowSwitcher()
        } else {
            showScreenCaptureAccessAlert()
        }
    }

    @objc private func openScreenRecordingSettings() {
        waitingForScreenCaptureSettings = true
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showScreenCaptureAccessAlert() {
        let alert = NSAlert()
        alert.messageText = "Window previews need Screen Recording access"
        alert.informativeText = "AltTab only captures a single image for each visible preview while the switcher is open. It does not record in the background or save the images."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Use Wireframes")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openScreenRecordingSettings()
        case .alertSecondButtonReturn:
            store.show(capturePreviews: false)
        default:
            break
        }
    }

    private func relaunchAndShowSwitcher() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.showAfterRelaunch)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 0.8; /usr/bin/open -n \"$1\"",
            "--",
            Bundle.main.bundlePath
        ]
        try? process.run()
        NSApp.terminate(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private var isOtherAltTabRunning: Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.contains { app in
            guard app.processIdentifier != currentPID else { return false }
            return app.bundleIdentifier == "com.lwouis.alt-tab-macos" || app.localizedName == "AltTab"
        }
    }

    private func showShortcutConflictAlert() {
        let alert = NSAlert()
        alert.messageText = "Another AltTab app is already running"
        alert.informativeText = "AltTab Window Switcher will not register ⌘Tab while the installed AltTab app is running. Quit the other app from its menu-bar icon, then relaunch this app."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility access is required"
        alert.informativeText = "Enable AltTab Window Switcher in System Settings → Privacy & Security → Accessibility, then relaunch the app. This permission is what lets it receive ⌘Tab and keyboard navigation globally."
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard waitingForScreenCaptureSettings else { return }
        waitingForScreenCaptureSettings = false

        if CGPreflightScreenCaptureAccess() {
            relaunchAndShowSwitcher()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }
}
