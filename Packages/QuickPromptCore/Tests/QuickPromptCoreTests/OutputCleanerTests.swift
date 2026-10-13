import Testing
@testable import QuickPromptCore

struct OutputCleanerTests {
    @Test func trimsWhitespace() {
        #expect(OutputCleaner.clean("  \nBonjour.\n\n") == "Bonjour.")
    }

    @Test func removesWrappingTags() {
        #expect(OutputCleaner.clean("<texte>\nBonjour.\n</texte>") == "Bonjour.")
    }

    @Test func keepsTagsThatDoNotWrapEverything() {
        let text = "Utilise <texte> pour ouvrir et </texte> pour fermer"
        #expect(OutputCleaner.clean(text) == text)
    }

    @Test func keepsInnerLineBreaks() {
        #expect(OutputCleaner.clean("a\n\n- b\n- c") == "a\n\n- b\n- c")
    }
}
