import AppKit
import ApplicationServices

struct CapturedText {
    enum Method: String {
        case accessibility, copy, clipboard
    }

    let text: String
    let method: Method
}

@MainActor
protocol TextCapture {
    func capture() async -> CapturedText?
}

/// Selected text of the focused element, through the Accessibility API.
struct AccessibilityCapture: TextCapture {
    func capture() async -> CapturedText? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.5)

        var focused: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard focusResult == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            Log.capture.debug("AX: no focused element (\(focusResult.rawValue))")
            return nil
        }
        let element = focused as! AXUIElement

        var selected: CFTypeRef?
        let selectionResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected)
        guard selectionResult == .success, let text = selected as? String, !text.isEmpty else {
            Log.capture.debug("AX: no selected text (\(selectionResult.rawValue))")
            return nil
        }
        return CapturedText(text: text, method: .accessibility)
    }
}

/// Reads the pasteboard once it changes after `changeCount`, or after `timeout`.
@MainActor
enum PasteboardWaiter {
    static func waitForChange(from changeCount: Int, timeout: Duration = .milliseconds(500)) async -> Bool {
        let pasteboard = NSPasteboard.general
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while pasteboard.changeCount == changeCount {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    static var text: String? {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return nil }
        return text
    }
}

/// Simulates Cmd+C and reads the pasteboard. Fails when the pasteboard does not change.
struct CopyCapture: TextCapture {
    func capture() async -> CapturedText? {
        // The palette shortcut modifiers may still be held: wait so they do not mix with our Cmd+C.
        if !(await KeyboardSimulator.waitForModifiersRelease()) {
            Log.capture.warning("Modifiers still pressed after 2s, copying anyway")
        }
        let before = NSPasteboard.general.changeCount
        KeyboardSimulator.copy()
        guard await PasteboardWaiter.waitForChange(from: before) else {
            Log.capture.debug("Copy: pasteboard did not change")
            return nil
        }
        guard let text = PasteboardWaiter.text else { return nil }
        return CapturedText(text: text, method: .copy)
    }
}

/// Accessibility first, then Cmd+C.
struct SelectionCapture: TextCapture {
    func capture() async -> CapturedText? {
        if let captured = await AccessibilityCapture().capture() { return captured }
        return await CopyCapture().capture()
    }
}

/// Double Cmd+C: the user already copied. Waits for the source app to finish writing,
/// then takes the pasteboard content (even if it did not change).
struct ClipboardCapture: TextCapture {
    let changeCountAtTrigger: Int

    func capture() async -> CapturedText? {
        let changed = await PasteboardWaiter.waitForChange(from: changeCountAtTrigger)
        Log.capture.debug("Clipboard: changed=\(changed)")
        guard let text = PasteboardWaiter.text else { return nil }
        return CapturedText(text: text, method: .clipboard)
    }
}
