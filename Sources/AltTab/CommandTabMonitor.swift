import AppKit
import Carbon.HIToolbox

final class CommandTabMonitor {
    private weak var store: SwitcherStore?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let stateLock = NSLock()
    private var overlayIsActive = false
    var onShowRequested: (() -> Void)?

    init(store: SwitcherStore) {
        self.store = store
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: commandTabEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        Thread { [weak self] in
            guard let self, let source = self.runLoopSource, let tap = self.eventTap else { return }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }.start()
        return true
    }

    func setOverlayActive(_ active: Bool) {
        stateLock.lock()
        overlayIsActive = active
        stateLock.unlock()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        if keyCode == kVK_Tab && event.flags.contains(.maskCommand) {
            if !isOverlayActiveNow() {
                DispatchQueue.main.async { [weak self] in self?.onShowRequested?() }
            } else {
                let forward = !event.flags.contains(.maskShift)
                DispatchQueue.main.async { [weak self] in self?.store?.cycleApp(forward: forward) }
            }
            return nil
        }

        guard isOverlayActiveNow() else {
            return Unmanaged.passUnretained(event)
        }

        switch keyCode {
        case kVK_Escape:
            DispatchQueue.main.async { [weak self] in self?.store?.cancel() }
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
            DispatchQueue.main.async { [weak self] in
                guard let store = self?.store else { return }
                if store.phase == .apps {
                    store.enterWindows()
                } else {
                    store.activateSelection()
                }
            }
            return nil
        case kVK_LeftArrow:
            DispatchQueue.main.async { [weak self] in self?.moveLeft() }
            return nil
        case kVK_RightArrow:
            DispatchQueue.main.async { [weak self] in self?.moveRight() }
            return nil
        case kVK_UpArrow:
            DispatchQueue.main.async { [weak self] in self?.moveUp() }
            return nil
        case kVK_DownArrow:
            DispatchQueue.main.async { [weak self] in self?.moveDown() }
            return nil
        case kVK_ANSI_W:
            DispatchQueue.main.async { [weak self] in self?.store?.enterWindows() }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func moveLeft() {
        guard let store else { return }
        if store.phase == .apps {
            store.cycleApp(forward: false)
        } else {
            store.moveWindow(rowDelta: 0, columnDelta: -1)
        }
    }

    private func moveRight() {
        guard let store else { return }
        if store.phase == .apps {
            store.cycleApp()
        } else {
            store.moveWindow(rowDelta: 0, columnDelta: 1)
        }
    }

    private func moveUp() {
        guard let store else { return }
        if store.phase == .apps {
            store.enterWindows()
        } else {
            store.moveWindow(rowDelta: -1, columnDelta: 0)
        }
    }

    private func moveDown() {
        guard let store else { return }
        if store.phase == .apps {
            store.enterWindows()
        } else {
            store.moveWindow(rowDelta: 1, columnDelta: 0)
        }
    }

    private func isOverlayActiveNow() -> Bool {
        stateLock.lock()
        let active = overlayIsActive
        stateLock.unlock()
        return active
    }
}

private let commandTabEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<CommandTabMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}
