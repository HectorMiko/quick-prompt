import Foundation
import Observation
import QuickPromptCore

extension Backend {
    var label: String {
        switch self {
        case .api: "API key"
        case .claudeCode: "Claude subscription"
        }
    }
}

/// Both connections, usable at the same time by different prompts.
/// The API key lives in the keychain, the Claude Code path in UserDefaults. Changes apply to the next run.
@MainActor @Observable
final class BackendSettings {
    enum TestState: Equatable {
        case idle, running
        case success(String)
        case failure(String)
    }

    private enum Keys {
        static let cliPath = "cliPath"
    }

    var cliPath: String {
        didSet { UserDefaults.standard.set(cliPath, forKey: Keys.cliPath) }
    }

    /// Last 4 characters of the stored key, or `nil` when there is no key.
    private(set) var apiKeySuffix: String?
    private(set) var testStates: [Backend: TestState] = [:]

    var hasAPIKey: Bool { apiKeySuffix != nil }

    var cliFound: Bool {
        FileManager.default.isExecutableFile(atPath: expandedCLIPath)
    }

    private var expandedCLIPath: String {
        (cliPath as NSString).expandingTildeInPath
    }

    init() {
        cliPath = UserDefaults.standard.string(forKey: Keys.cliPath) ?? ClaudeCLIProvider.defaultPath
        apiKeySuffix = KeychainStore.readAPIKey().map { String($0.suffix(4)) }
    }

    // MARK: - API key

    /// Returns an error message, or `nil` on success.
    func setAPIKey(_ key: String) -> String? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "The key is empty." }
        do {
            try KeychainStore.saveAPIKey(key)
            apiKeySuffix = String(key.suffix(4))
            testStates[.api] = nil
            Log.system.info("API key saved in the keychain")
            return nil
        } catch {
            Log.system.error("Saving API key failed: \(String(describing: error), privacy: .public)")
            return "Could not save the key in the keychain."
        }
    }

    func removeAPIKey() {
        do {
            try KeychainStore.deleteAPIKey()
            apiKeySuffix = nil
            testStates[.api] = nil
            Log.system.info("API key removed from the keychain")
        } catch {
            Log.system.error("Removing API key failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Providers

    /// Message explaining why `backend` cannot run, or `nil` when it is ready.
    func readinessError(for backend: Backend) -> String? {
        switch backend {
        case .api: hasAPIKey ? nil : LLMError.missingAPIKey.userMessage
        case .claudeCode: cliFound ? nil : LLMError.cliNotFound(path: cliPath).userMessage
        }
    }

    func makeProvider(for backend: Backend) -> any LLMProvider {
        switch backend {
        case .api: AnthropicAPIProvider(apiKey: KeychainStore.readAPIKey() ?? "")
        case .claudeCode: ClaudeCLIProvider(executablePath: expandedCLIPath)
        }
    }

    func testState(for backend: Backend) -> TestState {
        testStates[backend] ?? .idle
    }

    /// Small real call with Haiku 4.5 to check the key, the network or Claude Code.
    func testConnection(_ backend: Backend) {
        guard testState(for: backend) != .running else { return }
        testStates[backend] = .running
        let provider = makeProvider(for: backend)
        let model = ClaudeModel.haiku45
        let request = LLMRequest(
            system: "Reply with the single word OK.",
            user: "ping",
            model: model.id,
            effort: nil,
            temperature: 0,
            maxTokens: 16,
            timeout: model.defaultTimeout
        )
        Task {
            let start = ContinuousClock.now
            do {
                _ = try await provider.complete(request)
                let elapsed = (ContinuousClock.now - start).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
                testStates[backend] = .success("Connected with \(model.displayName) in \(elapsed)")
            } catch let error as LLMError {
                testStates[backend] = .failure(error.userMessage)
            } catch {
                testStates[backend] = .failure("Unexpected error")
            }
        }
    }
}
