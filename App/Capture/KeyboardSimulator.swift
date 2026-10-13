import Carbon.HIToolbox
import CoreGraphics

/// Posts synthetic key events. Requires the Accessibility permission.
enum KeyboardSimulator {
    /// Marker set on our own events so the double Cmd+C listener ignores them.
    static let eventMarker: Int64 = 0x5155_4943_4B50 // "QUICKP"

    static let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    static func copy() { pressWithCommand(CGKeyCode(kVK_ANSI_C)) }
    static func paste() { pressWithCommand(CGKeyCode(kVK_ANSI_V)) }

    private static func pressWithCommand(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    static var modifiersPressed: Bool {
        !CGEventSource.flagsState(.hidSystemState).intersection(modifierMask).isEmpty
    }

    /// Waits until no modifier key is physically held. Returns `false` on timeout.
    static func waitForModifiersRelease(timeout: Duration = .seconds(2)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while modifiersPressed {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}
