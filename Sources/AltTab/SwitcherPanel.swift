import AppKit
import Carbon.HIToolbox
import SwiftUI

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SwitcherPanelController: NSWindowController {
    private static let panelSize = NSSize(width: 740, height: 330)

    private let store: SwitcherStore
    private var localKeyMonitor: Any?

    init(store: SwitcherStore) {
        self.store = store

        let panel = SwitcherPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .aqua)
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        let hostingView = NSHostingView(rootView: SwitcherView(store: store))
        hostingView.frame = NSRect(origin: .zero, size: Self.panelSize)
        hostingView.autoresizingMask = [.width, .height]

        if #available(macOS 26.0, *) {
            // NSGlassEffectView must own content through contentView. AppKit uses
            // that relationship to keep foreground content legible on glass.
            let glassView = NSGlassEffectView()
            glassView.style = .regular
            glassView.cornerRadius = 32
            glassView.tintColor = NSColor.white.withAlphaComponent(0.06)
            glassView.contentView = hostingView
            panel.contentView = glassView
        } else {
            let materialView = NSVisualEffectView()
            materialView.material = .underWindowBackground
            materialView.blendingMode = .behindWindow
            materialView.state = .active
            materialView.wantsLayer = true
            materialView.layer?.cornerRadius = 32
            materialView.layer?.masksToBounds = true
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            materialView.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: materialView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor)
            ])
            panel.contentView = materialView
        }

        super.init(window: panel)
        panel.delegate = self

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.store.isVisible else { return event }
            return self.handleLocalKey(event)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    func show() {
        guard let window else { return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func handleLocalKey(_ event: NSEvent) -> NSEvent? {
        let keyCode = Int(event.keyCode)

        switch keyCode {
        case kVK_Escape:
            store.cancel()
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
            if store.phase == .apps {
                store.enterWindows()
            } else {
                store.activateSelection()
            }
            return nil
        case kVK_ANSI_W:
            store.enterWindows()
            return nil
        case kVK_LeftArrow:
            if store.phase == .apps {
                store.cycleApp(forward: false)
            } else {
                store.moveWindow(rowDelta: 0, columnDelta: -1)
            }
            return nil
        case kVK_RightArrow:
            if store.phase == .apps {
                store.cycleApp()
            } else {
                store.moveWindow(rowDelta: 0, columnDelta: 1)
            }
            return nil
        case kVK_UpArrow:
            if store.phase == .apps {
                store.enterWindows()
            } else {
                store.moveWindow(rowDelta: -1, columnDelta: 0)
            }
            return nil
        case kVK_DownArrow:
            if store.phase == .apps {
                store.enterWindows()
            } else {
                store.moveWindow(rowDelta: 1, columnDelta: 0)
            }
            return nil
        default:
            return event
        }
    }
}

extension SwitcherPanelController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        store.cancel()
        return false
    }
}

struct SwitcherView: View {
    @ObservedObject var store: SwitcherStore

    var body: some View {
        ZStack {
            ReferenceBackdrop()
                .blur(radius: 12)
                .scaleEffect(1.04)

            VStack(spacing: 0) {
                Group {
                    if store.phase == .apps {
                        appShelf
                    } else {
                        windowShelf
                    }
                }
                .frame(height: 286, alignment: .top)

                footer
                    .frame(height: 44)
            }
        }
        .frame(width: 740, height: 330)
        .clipShape(LiquidPanelShape())
        .overlay {
            LiquidPanelShape()
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.88),
                            .white.opacity(0.22),
                            Color.cyan.opacity(0.24),
                            .white.opacity(0.62)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.4
                )

            LiquidPanelShape()
                .stroke(Color.white.opacity(0.26), lineWidth: 1)
                .padding(2)
        }
        .environment(\.colorScheme, .light)
    }

    private var appShelf: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    appTiles
                }
                .scrollIndicators(.hidden)
                .onChange(of: store.selectedAppIndex) { _ in
                    scrollToSelectedApp(using: proxy)
                }
                .onChange(of: store.apps.map(\.id)) { _ in
                    scrollToSelectedApp(using: proxy, animated: false)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 61)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var appTiles: some View {
        LazyHStack(alignment: .center, spacing: 8) {
            ForEach(Array(store.apps.enumerated()), id: \.element.id) { index, app in
                ReferenceAppTile(
                    app: app,
                    isSelected: index == store.selectedAppIndex,
                    action: {
                        store.selectApp(at: index)
                        store.enterWindows()
                    }
                )
                .id(app.id)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minWidth: 720, alignment: .center)
    }

    private var windowShelf: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if let app = store.selectedApp {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    Text(app.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Windows")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Select a window to bring it forward")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 30)
            .padding(.top, 16)

            if let app = store.selectedApp, !app.windows.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        windowTiles(app)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .onChange(of: store.selectedWindowIndex) { _ in
                        scrollToSelectedWindow(in: app, using: proxy)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("No visible windows found")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func windowTiles(_ app: RunningAppItem) -> some View {
        LazyHStack(alignment: .center, spacing: 12) {
            ForEach(Array(app.windows.enumerated()), id: \.element.id) { index, window in
                ReferenceWindowTile(
                    window: window,
                    isSelected: index == store.selectedWindowIndex,
                    action: {
                        store.selectedWindowIndex = index
                        store.activateSelection()
                    }
                )
                .id(window.id)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func scrollToSelectedApp(using proxy: ScrollViewProxy, animated: Bool = true) {
        guard store.apps.indices.contains(store.selectedAppIndex) else { return }
        let id = store.apps[store.selectedAppIndex].id
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            } else {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func scrollToSelectedWindow(in app: RunningAppItem, using proxy: ScrollViewProxy) {
        guard app.windows.indices.contains(store.selectedWindowIndex) else { return }
        let id = app.windows[store.selectedWindowIndex].id
        withAnimation(.easeOut(duration: 0.16)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(store.phase == .apps ? "Switch between open applications (Alt + Tab)" : "Return / Space  Open window")
            Spacer(minLength: 20)
            HStack(spacing: 6) {
                Image(systemName: "square.on.square")
                Text("\(store.apps.count) Applications Open")
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(Color.black.opacity(0.56))
        .shadow(color: .white.opacity(0.52), radius: 1, y: 1)
        .padding(.horizontal, 26)
        .padding(.vertical, 8)
    }
}

/// A nearly rectangular, subtly asymmetric outline. The small bezier offsets
/// keep the panel from reading as a rigid card while preserving clean layout.
private struct LiquidPanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(34.0, min(rect.width, rect.height) * 0.16)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY + 1))
        path.addCurve(
            to: CGPoint(x: rect.maxX - r * 1.1, y: rect.minY + 2),
            control1: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY - 1.5),
            control2: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + 4)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - 1, y: rect.minY + r),
            control1: CGPoint(x: rect.maxX - r * 0.36, y: rect.minY + 2),
            control2: CGPoint(x: rect.maxX - 1, y: rect.minY + r * 0.42)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - 2, y: rect.maxY - r * 0.92),
            control1: CGPoint(x: rect.maxX + 1, y: rect.minY + rect.height * 0.34),
            control2: CGPoint(x: rect.maxX - 4, y: rect.minY + rect.height * 0.73)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY - 1),
            control1: CGPoint(x: rect.maxX - 2, y: rect.maxY - r * 0.36),
            control2: CGPoint(x: rect.maxX - r * 0.42, y: rect.maxY - 1)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + r * 0.94, y: rect.maxY - 2),
            control1: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.maxY + 1),
            control2: CGPoint(x: rect.minX + rect.width * 0.31, y: rect.maxY - 5)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + 1, y: rect.maxY - r),
            control1: CGPoint(x: rect.minX + r * 0.34, y: rect.maxY - 2),
            control2: CGPoint(x: rect.minX + 1, y: rect.maxY - r * 0.43)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + 2, y: rect.minY + r * 0.95),
            control1: CGPoint(x: rect.minX - 1, y: rect.minY + rect.height * 0.68),
            control2: CGPoint(x: rect.minX + 4, y: rect.minY + rect.height * 0.31)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY + 1),
            control1: CGPoint(x: rect.minX + 2, y: rect.minY + r * 0.36),
            control2: CGPoint(x: rect.minX + r * 0.42, y: rect.minY + 1)
        )
        path.closeSubpath()
        return path
    }
}

private struct ReferenceBackdrop: View {
    var body: some View {
        ZStack {
            if #available(macOS 15.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0.0, 0.0], [0.48, 0.0], [1.0, 0.0],
                        [0.0, 0.48], [0.50, 0.52], [1.0, 0.46],
                        [0.0, 1.0], [0.52, 1.0], [1.0, 1.0]
                    ],
                    colors: [
                        Color(red: 0.98, green: 0.70, blue: 0.65),
                        Color(red: 0.97, green: 0.68, blue: 0.76),
                        Color(red: 0.59, green: 0.66, blue: 0.96),
                        Color(red: 0.63, green: 0.80, blue: 0.70),
                        Color(red: 0.93, green: 0.73, blue: 0.77),
                        Color(red: 0.72, green: 0.78, blue: 0.94),
                        Color(red: 0.59, green: 0.76, blue: 0.45),
                        Color(red: 0.77, green: 0.88, blue: 0.69),
                        Color(red: 0.73, green: 0.69, blue: 0.84)
                    ]
                )
                .opacity(0.64)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.73, blue: 0.72),
                        Color(red: 0.72, green: 0.78, blue: 0.95),
                        Color(red: 0.70, green: 0.84, blue: 0.62)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.58)
            }

            LinearGradient(
                colors: [.white.opacity(0.34), .white.opacity(0.08), .clear],
                startPoint: .top,
                endPoint: .bottom
            )

            Ellipse()
                .stroke(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.10),
                            Color.cyan.opacity(0.15),
                            Color.purple.opacity(0.12),
                            .white.opacity(0.20),
                            Color.green.opacity(0.11),
                            .white.opacity(0.10)
                        ],
                        center: .center
                    ),
                    lineWidth: 2
                )
                .frame(width: 620, height: 430)
                .blur(radius: 1.2)
                .offset(x: 470, y: 135)

            Ellipse()
                .stroke(Color.white.opacity(0.14), lineWidth: 1.2)
                .frame(width: 610, height: 470)
                .blur(radius: 0.8)
                .offset(x: -460, y: 155)
        }
        .allowsHitTesting(false)
    }
}

private struct ReferenceAppTile: View {
    let app: RunningAppItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                WindowPreview(
                    window: app.windows.first,
                    isSelected: isSelected
                )

                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.20), radius: 6, y: 3)

                Text(app.name)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .frame(width: isSelected ? 124 : 114, height: 170)
            .padding(.horizontal, 7)
            .padding(.vertical, 9)
            .modifier(ReferenceTileSurface(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

private struct WindowPreview: View {
    let window: WindowItem?
    let isSelected: Bool
    var size = CGSize(width: 112, height: 76)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.34 : 0.25))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.46), lineWidth: 1)
                }

            if let thumbnail = window?.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: size.width > 160 ? .fill : .fit)
                    .frame(width: size.width - 8, height: size.height - 8)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                WindowWireframe(window: window, isSelected: isSelected, size: size)
                    .padding(5)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: .black.opacity(0.20), radius: 6, y: 3)
    }
}

private struct WindowWireframe: View {
    let window: WindowItem?
    let isSelected: Bool
    let size: CGSize

    private var scale: CGFloat {
        min(max(size.width / 112, 0.9), 2.2)
    }

    private var title: String {
        window?.title ?? "No open windows"
    }

    private var accent: Color {
        isSelected ? Color.blue.opacity(0.70) : Color.black.opacity(0.42)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                Circle().fill(Color.red.opacity(0.72))
                    .frame(width: 4 * scale, height: 4 * scale)
                Circle().fill(Color.yellow.opacity(0.76))
                    .frame(width: 4 * scale, height: 4 * scale)
                Circle().fill(Color.green.opacity(0.72))
                    .frame(width: 4 * scale, height: 4 * scale)

                Text(title)
                    .font(.system(size: 7.5 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.64))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 2)

                Spacer(minLength: 0)
            }
            .frame(height: 15 * scale)
            .padding(.horizontal, 6 * scale)

            Rectangle()
                .fill(Color.white.opacity(0.48))
                .frame(height: 1)

            if window == nil {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                    Text("No window")
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.42))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(accent.opacity(0.20))
                        .frame(width: 20)
                        .overlay(alignment: .top) {
                            VStack(spacing: 3) {
                                ForEach(0..<4, id: \.self) { _ in
                                    Capsule()
                                        .fill(accent.opacity(0.55))
                                        .frame(width: 11 * scale, height: 2 * scale)
                                }
                            }
                            .padding(.top, 6 * scale)
                        }

                    VStack(alignment: .leading, spacing: 5) {
                        Capsule()
                            .fill(accent.opacity(0.68))
                            .frame(width: 44 * scale, height: 4 * scale)
                        Capsule()
                            .fill(Color.black.opacity(0.20))
                            .frame(width: 57 * scale, height: 3 * scale)
                        Capsule()
                            .fill(Color.black.opacity(0.15))
                            .frame(width: 48 * scale, height: 3 * scale)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 7 * scale)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7 * scale)
                .padding(.bottom, 6 * scale)
            }
        }
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.50), Color.white.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.66), lineWidth: 0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ReferenceWindowTile: View {
    let window: WindowItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                WindowPreview(
                    window: window,
                    isSelected: isSelected,
                    size: CGSize(width: 222, height: 140)
                )
                Text(window.title)
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium, design: .rounded))
                    .lineLimit(1)
                    .frame(width: 222)
            }
            .frame(width: isSelected ? 246 : 238, height: 184)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .modifier(ReferenceTileSurface(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

private struct ReferenceTileSurface: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(red: 0.35, green: 0.72, blue: 1.0).opacity(0.13))
                        LinearGradient(
                            colors: [.white.opacity(0.30), .clear, .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
                .overlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.blue.opacity(0.86), lineWidth: 1.35)
                        RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                            .stroke(Color.white.opacity(0.66), lineWidth: 0.8)
                            .padding(1.5)
                    }
                }
                .shadow(color: Color.blue.opacity(0.19), radius: 14, y: 5)
        } else {
            content
        }
    }
}
