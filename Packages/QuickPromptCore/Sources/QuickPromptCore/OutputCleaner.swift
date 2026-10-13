import Foundation

/// Normalizes the model output before pasting it.
public enum OutputCleaner {
    static let openTag = "<texte>"
    static let closeTag = "</texte>"

    /// Trims surrounding whitespace and removes `<texte>` tags when they wrap the whole output.
    public static func clean(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(openTag), text.hasSuffix(closeTag),
           text.count >= openTag.count + closeTag.count {
            text = String(text.dropFirst(openTag.count).dropLast(closeTag.count))
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
