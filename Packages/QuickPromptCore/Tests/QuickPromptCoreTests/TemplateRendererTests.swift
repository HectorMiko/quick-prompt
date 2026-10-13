import Testing
@testable import QuickPromptCore

struct TemplateRendererTests {
    @Test func replacesKnownPlaceholder() {
        let output = TemplateRenderer.render("<texte>\n{{text}}\n</texte>", values: ["text": "bonjour"])
        #expect(output == "<texte>\nbonjour\n</texte>")
    }

    @Test func toleratesSpacesInsideBraces() {
        #expect(TemplateRenderer.render("{{ text }}", values: ["text": "a"]) == "a")
    }

    @Test func leavesUnknownPlaceholderUntouched() {
        let output = TemplateRenderer.render("{{date}} {{text}}", values: ["text": "a"])
        #expect(output == "{{date}} a")
        #expect(TemplateRenderer.unknownPlaceholders(in: "{{date}} {{text}}", values: ["text": "a"]) == ["date"])
    }

    @Test func doesNotReinterpretPlaceholdersInsideValues() {
        let output = TemplateRenderer.render("{{text}}", values: ["text": "{{text}} }}{{"])
        #expect(output == "{{text}} }}{{")
    }

    @Test func keepsUnclosedBraces() {
        #expect(TemplateRenderer.render("a {{text", values: ["text": "b"]) == "a {{text")
    }

    @Test func grammarTemplateWrapsText() {
        let output = TemplateRenderer.render(TextAction.grammar.userTemplate, values: ["text": "salut"])
        #expect(output == "<texte>\nsalut\n</texte>")
    }
}
