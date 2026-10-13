import Foundation
import Testing
@testable import QuickPromptCore

private struct MockProvider: LLMProvider {
    var output: String = "Corrigé."
    var delay: Duration = .zero
    var error: LLMError?
    let calls = Calls()

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [LLMRequest] = []
        var requests: [LLMRequest] { lock.withLock { _requests } }
        var users: [String] { requests.map(\.user) }
        func append(_ request: LLMRequest) { lock.withLock { _requests.append(request) } }
    }

    func complete(_ request: LLMRequest) async throws -> String {
        calls.append(request)
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return output
    }
}

struct ActionRunnerTests {
    @Test func rendersTemplateAndCleansOutput() async throws {
        let provider = MockProvider(output: "\n<texte>\nBonjour.\n</texte>\n")
        let result = try await ActionRunner().run(.grammar, input: "bonjour", provider: provider)
        #expect(result == "Bonjour.")
        #expect(provider.calls.users == ["<texte>\nbonjour\n</texte>"])
    }

    @Test func passesModelSettingsToProvider() async throws {
        let provider = MockProvider()
        let action = TextAction(prompt: PromptItem(
            id: "x", name: "X", prompt: "sys", model: "claude-opus-5-5", effort: .high, timeoutSeconds: 45, maxTokens: 9000
        ))
        _ = try await ActionRunner().run(action, input: "a", provider: provider)
        #expect(provider.calls.requests == [LLMRequest(
            system: "sys", user: "<texte>\na\n</texte>", model: "claude-opus-5-5",
            effort: .high, temperature: nil, maxTokens: 9000, timeout: 45
        )])
    }

    @Test func rejectsEmptyInputWithoutCallingProvider() async {
        let provider = MockProvider()
        await #expect(throws: ActionRunnerError.emptyInput) {
            try await ActionRunner().run(.grammar, input: "  \n ", provider: provider)
        }
        #expect(provider.calls.users.isEmpty)
    }

    @Test func rejectsTooLongInput() async {
        let input = String(repeating: "a", count: ActionRunner.maxInputLength + 1)
        await #expect(throws: ActionRunnerError.inputTooLong(count: input.count, limit: ActionRunner.maxInputLength)) {
            try await ActionRunner().run(.grammar, input: input, provider: MockProvider())
        }
    }

    @Test func emptyCleanedOutputIsAnError() async {
        await #expect(throws: LLMError.emptyResponse) {
            try await ActionRunner().run(.grammar, input: "a", provider: MockProvider(output: "<texte>\n</texte>"))
        }
    }

    @Test func propagatesProviderError() async {
        let provider = MockProvider(error: .http(status: 500, type: "api_error"))
        await #expect(throws: LLMError.http(status: 500, type: "api_error")) {
            try await ActionRunner().run(.grammar, input: "a", provider: provider)
        }
    }

    @Test func newRunCancelsPreviousRun() async throws {
        let runner = ActionRunner()
        let provider = MockProvider(output: "ok", delay: .milliseconds(300))
        let first = Task { try await runner.run(.grammar, input: "first", provider: provider) }
        try await Task.sleep(for: .milliseconds(50))
        let second = try await runner.run(.grammar, input: "second", provider: provider)
        #expect(second == "ok")
        await #expect(throws: LLMError.cancelled) { try await first.value }
    }

    @Test func cancelStopsCurrentRun() async throws {
        let runner = ActionRunner()
        let run = Task { try await runner.run(.grammar, input: "a", provider: MockProvider(delay: .seconds(5))) }
        try await Task.sleep(for: .milliseconds(50))
        await runner.cancel()
        await #expect(throws: LLMError.cancelled) { try await run.value }
    }

    @Test func callerCancellationStopsRun() async throws {
        let runner = ActionRunner()
        let run = Task { try await runner.run(.grammar, input: "a", provider: MockProvider(delay: .seconds(5))) }
        try await Task.sleep(for: .milliseconds(50))
        run.cancel()
        await #expect(throws: LLMError.cancelled) { try await run.value }
    }
}
