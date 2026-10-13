import Foundation
import Testing
@testable import QuickPromptCore

struct ProviderRequestTests {
    private func request(model: ClaudeModel, effort: Effort? = .low) -> LLMRequest {
        let action = TextAction(prompt: PromptItem(name: "X", prompt: "sys", model: model.id, effort: effort))
        return LLMRequest(
            system: action.systemPrompt, user: "u", model: action.model, effort: action.effort,
            temperature: action.temperature, maxTokens: action.maxTokens, timeout: action.timeout
        )
    }

    private func body(_ request: LLMRequest) throws -> [String: Any] {
        let urlRequest = try AnthropicAPIProvider.makeURLRequest(request, apiKey: "k")
        let data = try #require(urlRequest.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func haikuBodyHasTemperatureAndNoEffort() throws {
        let json = try body(request(model: .haiku45))
        #expect(json["model"] as? String == "claude-haiku-4-5")
        #expect(json["temperature"] as? Double == 0)
        #expect(json["output_config"] == nil)
        #expect(json["max_tokens"] as? Int == 4096)
    }

    @Test func thinkingModelBodyHasEffortAndNoTemperature() throws {
        let json = try body(request(model: .opus55, effort: .medium))
        #expect(json["temperature"] == nil)
        #expect((json["output_config"] as? [String: String]) == ["effort": "medium"])
        #expect(json["thinking"] == nil)
        #expect(json["max_tokens"] as? Int == 16_000)
    }

    @Test func apiHeaders() throws {
        let urlRequest = try AnthropicAPIProvider.makeURLRequest(request(model: .haiku45), apiKey: "secret")
        #expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == "secret")
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test func cliArgumentsIsolateUserSetupAndPassEffort() {
        let arguments = ClaudeCLIProvider.arguments(for: request(model: .sonnet55, effort: .high))
        #expect(arguments == [
            "-p", "--model", "claude-sonnet-5-5", "--system-prompt", "sys",
            "--tools", "", "--strict-mcp-config", "--disable-slash-commands",
            "--no-session-persistence", "--setting-sources", "", "--effort", "high",
        ])
        #expect(!arguments.contains("u"))
    }

    @Test func cliArgumentsOmitEffortForHaiku() {
        #expect(!ClaudeCLIProvider.arguments(for: request(model: .haiku45)).contains("--effort"))
    }

    @Test func missingCLIIsReported() async {
        let provider = ClaudeCLIProvider(executablePath: "/nonexistent/claude")
        await #expect(throws: LLMError.cliNotFound(path: "/nonexistent/claude")) {
            try await provider.complete(request(model: .haiku45))
        }
    }

    @Test func cliRunsThroughStdinAndReportsExitCode() async throws {
        // /bin/cat echoes stdin: proves the text goes through stdin, not arguments.
        let echo = ClaudeCLIProvider(executablePath: "/bin/cat")
        // `cat` rejects the claude flags, so check the stdin path with a plain process run instead.
        let run = CLIRun(executablePath: "/bin/cat", arguments: [], input: "  bonjour\n")
        let result = try await run.start()
        #expect(result.exitCode == 0)
        #expect(result.stdout == "  bonjour\n")
        await #expect(throws: LLMError.self) { try await echo.complete(request(model: .haiku45)) }
    }

    @Test func timeoutStopsSlowOperation() async {
        await #expect(throws: LLMError.timeout) {
            try await withTimeout(0.05) { try await Task.sleep(for: .seconds(5)); return 1 }
        }
    }

    @Test func cliTimeoutTerminatesProcess() async throws {
        let run = CLIRun(executablePath: "/bin/sleep", arguments: ["5"], input: "")
        let start = Date()
        await #expect(throws: LLMError.timeout) {
            try await withTimeout(0.2) {
                try await withTaskCancellationHandler { try await run.start() } onCancel: { run.terminate() }
            }
        }
        #expect(Date().timeIntervalSince(start) < 2)
    }
}
