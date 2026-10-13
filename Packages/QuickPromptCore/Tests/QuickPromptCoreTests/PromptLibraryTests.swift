import Foundation
import Testing
@testable import QuickPromptCore

struct PromptLibraryTests {
    private func library() -> PromptLibrary {
        PromptLibrary(quickActionID: "a", prompts: [
            PromptItem(id: "a", name: "A", prompt: "pa"),
            PromptItem(id: "b", name: "B", prompt: "pb"),
            PromptItem(id: "c", name: "C", prompt: "pc"),
        ])
    }

    @Test func defaultsHaveFourPromptsWithCorrectAsQuickAction() {
        var counter = 0
        let defaults = DefaultPrompts.makeLibrary { counter += 1; return "id\(counter)" }
        #expect(defaults.prompts.map(\.name) == ["Correct", "Improve email", "Translate to English", "Translate to French"])
        #expect(defaults.quickAction?.name == "Correct")
        #expect(defaults.quickAction?.prompt == DefaultPrompts.correct)
        #expect(defaults.prompts.filter(\.isValid).count == 4)
    }

    @Test func deletingQuickActionClearsIt() {
        var lib = library()
        lib.delete(id: "a")
        #expect(lib.quickActionID == nil)
        #expect(lib.quickAction == nil)
        #expect(lib.prompts.map(\.id) == ["b", "c"])
    }

    @Test func deletingOtherPromptKeepsQuickAction() {
        var lib = library()
        lib.delete(id: "b")
        #expect(lib.quickAction?.id == "a")
    }

    @Test func setQuickActionIgnoresUnknownID() {
        var lib = library()
        lib.setQuickAction(id: "zzz")
        #expect(lib.quickActionID == "a")
        lib.setQuickAction(id: "c")
        #expect(lib.quickActionID == "c")
        lib.setQuickAction(id: nil)
        #expect(lib.quickActionID == nil)
    }

    @Test func moveMatchesSwiftUISemantics() {
        var lib = library()
        lib.move(fromOffsets: [0], toOffset: 3)
        #expect(lib.prompts.map(\.id) == ["b", "c", "a"])
        lib.move(fromOffsets: [2], toOffset: 0)
        #expect(lib.prompts.map(\.id) == ["a", "b", "c"])
        lib.move(fromOffsets: [0, 1], toOffset: 3)
        #expect(lib.prompts.map(\.id) == ["c", "a", "b"])
    }

    @Test func updateReplacesPromptByID() {
        var lib = library()
        lib.update(PromptItem(id: "b", name: "B2", prompt: "new"))
        #expect(lib.prompts[1] == PromptItem(id: "b", name: "B2", prompt: "new"))
    }

    @Test func invalidPromptsAreNotRunnable() {
        var lib = library()
        lib.add(PromptItem(id: "d", name: "  ", prompt: "x"))
        lib.add(PromptItem(id: "e", name: "E", prompt: "\n"))
        #expect(lib.runnablePrompts.map(\.id) == ["a", "b", "c"])
    }

    @Test func detectsDuplicateNamesIgnoringCaseAndSpaces() {
        var lib = library()
        lib.add(PromptItem(id: "d", name: " a ", prompt: "x"))
        #expect(lib.hasDuplicateName(lib.prompts[0]))
        #expect(lib.hasDuplicateName(lib.prompts[3]))
        #expect(!lib.hasDuplicateName(lib.prompts[1]))
    }

    @Test func emptySettingsUseHaikuDefaults() {
        let action = TextAction(prompt: PromptItem(id: "x", name: "X", prompt: "sys"))
        #expect(action.systemPrompt == "sys")
        #expect(action.userTemplate == "<texte>\n{{text}}\n</texte>")
        #expect(action.backend == .api)
        #expect(action.model == "claude-haiku-4-5")
        #expect(action.effort == nil)
        #expect(action.temperature == 0)
        #expect(action.maxTokens == 4096)
        #expect(action.timeout == 30)
    }

    @Test func backendIsPerPrompt() {
        let action = TextAction(prompt: PromptItem(name: "X", prompt: "p", backend: .claudeCode))
        #expect(action.backend == .claudeCode)
    }

    @Test func haikuIgnoresEffort() {
        let action = TextAction(prompt: PromptItem(name: "X", prompt: "p", model: "claude-haiku-4-5", effort: .max))
        #expect(action.effort == nil)
    }

    @Test func thinkingModelsDropTemperatureAndDefaultToLowEffort() {
        for model in [ClaudeModel.sonnet55, .opus55, .fable51] {
            let action = TextAction(prompt: PromptItem(name: "X", prompt: "p", model: model.id))
            #expect(action.temperature == nil)
            #expect(action.effort == .low)
            #expect(action.maxTokens == 16_000)
            #expect(action.timeout == 120)
        }
    }

    @Test func explicitSettingsWin() {
        let action = TextAction(prompt: PromptItem(
            name: "X", prompt: "p", model: "claude-sonnet-5-5", effort: .xhigh, timeoutSeconds: 200, maxTokens: 32_000
        ))
        #expect(action.effort == .xhigh)
        #expect(action.timeout == 200)
        #expect(action.maxTokens == 32_000)
    }

    @Test func nonPositiveOverridesFallBackToDefaults() {
        let action = TextAction(prompt: PromptItem(name: "X", prompt: "p", timeoutSeconds: 0, maxTokens: -5))
        #expect(action.timeout == 30)
        #expect(action.maxTokens == 4096)
    }

    @Test func unknownModelsAreTreatedAsThinkingModels() {
        let action = TextAction(prompt: PromptItem(name: "X", prompt: "p", model: "claude-future-9"))
        #expect(action.model == "claude-future-9")
        #expect(action.temperature == nil)
        #expect(action.effort == .low)
        #expect(ClaudeModel.find("claude-haiku-4-5-20251001").supportsEffort == false)
    }
}

struct PromptFileTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("prompts.json")
    }

    @Test func missingFileReturnsNil() throws {
        #expect(try PromptFile.load(from: tempURL()) == nil)
    }

    @Test func roundTrip() throws {
        let url = tempURL()
        let lib = DefaultPrompts.makeLibrary()
        try PromptFile.save(lib, to: url)
        #expect(try PromptFile.load(from: url) == lib)
    }

    @Test func fileUsesDocumentedKeys() throws {
        let url = tempURL()
        try PromptFile.save(PromptLibrary(quickActionID: "a", prompts: [PromptItem(id: "a", name: "A", prompt: "p")]), to: url)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(json["quickActionId"] as? String == "a")
        let prompts = try #require(json["prompts"] as? [[String: String]])
        #expect(prompts == [["id": "a", "name": "A", "prompt": "p"]])
    }

    @Test func quickActionIsOptional() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"prompts":[{"id":"a","name":"A","prompt":"p"}]}"#.utf8).write(to: url)
        #expect(try PromptFile.load(from: url) == PromptLibrary(prompts: [PromptItem(id: "a", name: "A", prompt: "p")]))
    }

    @Test func modelSettingsRoundTripAndStayOptional() throws {
        let url = tempURL()
        let lib = PromptLibrary(prompts: [
            PromptItem(
                id: "a", name: "A", prompt: "p", backend: .claudeCode, model: "claude-opus-5-5",
                effort: .medium, timeoutSeconds: 90, maxTokens: 8000
            ),
            PromptItem(id: "b", name: "B", prompt: "p"),
        ])
        try PromptFile.save(lib, to: url)
        #expect(try PromptFile.load(from: url) == lib)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let prompts = try #require(json["prompts"] as? [[String: Any]])
        #expect(Set(prompts[0].keys) == ["id", "name", "prompt", "backend", "model", "effort", "timeoutSeconds", "maxTokens"])
        #expect(Set(prompts[1].keys) == ["id", "name", "prompt"])
        #expect(prompts[0]["backend"] as? String == "claudeCode")
    }

    @Test func invalidEffortIsDescribed() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"prompts":[{"id":"a","name":"A","prompt":"p","effort":"huge"}]}"#.utf8).write(to: url)
        #expect(throws: PromptFile.LoadError.invalid("Invalid value at prompts.[0].effort")) { try PromptFile.load(from: url) }
    }

    @Test func invalidJSONThrows() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        #expect(throws: PromptFile.LoadError.invalid("Invalid JSON")) { try PromptFile.load(from: url) }
    }

    @Test func missingKeyIsDescribed() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"prompts":[{"id":"a","name":"A"}]}"#.utf8).write(to: url)
        #expect(throws: PromptFile.LoadError.invalid(#"Missing key "prompt" at prompts.[0]"#)) { try PromptFile.load(from: url) }
    }
}
