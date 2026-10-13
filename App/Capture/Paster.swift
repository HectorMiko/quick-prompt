import AppKit

/// Writes the result to the pasteboard, and pastes it with Cmd+V for the quick action.
/// The original pasteboard is not restored: the result stays in the clipboard history.
@MainActor
enum Paster {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Log.output.info("Copied result, length=\(text.count)")
    }

    static func paste(_ text: String) async {
        copy(text)

        if !(await KeyboardSimulator.waitForModifiersRelease()) {
            Log.output.warning("Modifiers still pressed after 2s, pasting anyway")
        }
        KeyboardSimulator.paste()
        Log.output.info("Pasted result, length=\(text.count)")
    }
}
