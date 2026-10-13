import Carbon.HIToolbox
import CoreGraphics
import Foundation
import QuickPromptCore

/// Listens for two Cmd+C within 0.2 s with a listen-only event tap on a dedicated thread.
/// Requires the Input Monitoring permission.
final class DoubleCopyTrigger: @unchecked Sendable {
    private let onDoubleCopy: @MainActor @Sendable () -> Void
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    // Only touched on the event tap thread.
    private var detector = DoubleTapDetector(interval: 0.2)

    init(onDoubleCopy: @escaping @MainActor @Sendable () -> Void) {
        self.onDoubleCopy = onDoubleCopy
    }

    var isRunning: Bool { lock.withLock { tap != nil } }

    /// Creates the event tap. Returns `false` when macOS refuses (Input Monitoring missing).
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.trigger.error("Event tap creation failed (Input Monitoring permission missing?)")
            return false
        }
        lock.withLock { self.tap = tap }

        let thread = Thread { [weak self] in
            guard let self, let tap = self.lock.withLock({ self.tap }) else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let runLoop = CFRunLoopGetCurrent()
            self.lock.withLock { self.runLoop = runLoop }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "quick-prompt.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        Log.trigger.info("Double Cmd+C listener started")
        return true
    }

    func stop() {
        let (tap, runLoop) = lock.withLock {
            defer { self.tap = nil; self.runLoop = nil }
            return (self.tap, self.runLoop)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
        Log.trigger.info("Double Cmd+C listener stopped")
    }

    /// Called on the event tap thread. Must stay fast: macOS disables slow taps.
    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = lock.withLock({ self.tap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            Log.trigger.warning("Event tap disabled by macOS (type=\(type.rawValue)), re-enabled immediately")
        case .keyDown:
            guard isCommandC(event) else { return }
            if detector.registerPress(at: ProcessInfo.processInfo.systemUptime) {
                Log.trigger.info("Double Cmd+C detected")
                let onDoubleCopy = onDoubleCopy
                DispatchQueue.main.async { MainActor.assumeIsolated { onDoubleCopy() } }
            }
        default:
            break
        }
    }

    private func isCommandC(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_C),
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              event.getIntegerValueField(.eventSourceUserData) != KeyboardSimulator.eventMarker else {
            return false
        }
        let flags = event.flags.intersection(KeyboardSimulator.modifierMask)
        return flags == .maskCommand
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let trigger = Unmanaged<DoubleCopyTrigger>.fromOpaque(userInfo).takeUnretainedValue()
        trigger.handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
