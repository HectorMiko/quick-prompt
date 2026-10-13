import Foundation

public struct LLMRequest: Sendable, Equatable {
    public var system: String
    public var user: String
    public var model: String
    public var effort: Effort?
    public var temperature: Double?
    public var maxTokens: Int
    public var timeout: TimeInterval

    public init(
        system: String,
        user: String,
        model: String,
        effort: Effort?,
        temperature: Double?,
        maxTokens: Int,
        timeout: TimeInterval
    ) {
        self.system = system
        self.user = user
        self.model = model
        self.effort = effort
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeout = timeout
    }
}

/// A Claude backend: the Anthropic API or the Claude Code CLI.
public protocol LLMProvider: Sendable {
    func complete(_ request: LLMRequest) async throws -> String
}

public enum LLMError: Error, Equatable, Sendable {
    case missingAPIKey
    case http(status: Int, type: String?)
    case network(code: Int)
    case timeout
    case unexpectedResponse
    case emptyResponse
    case truncated
    case refused
    case cliNotFound(path: String)
    case cliFailed(exitCode: Int32, message: String?)
    case cancelled

    /// Short message shown to the user. Never contains user text.
    public var userMessage: String {
        switch self {
        case .missingAPIKey: "Missing API key (see Settings)"
        case let .http(status, type): "API error (\(status)\(type.map { " \($0)" } ?? ""))"
        case let .network(code): "Network error (\(code))"
        case .timeout: "Request timed out"
        case .unexpectedResponse: "Unexpected API response"
        case .emptyResponse: "Empty response"
        case .truncated: "Response truncated (max tokens reached)"
        case .refused: "Claude declined this request"
        case let .cliNotFound(path): "Claude Code not found at \(path)"
        case let .cliFailed(exitCode, message):
            "Claude Code error (exit \(exitCode))\(message.map { ": \($0)" } ?? "")"
        case .cancelled: "Cancelled"
        }
    }
}

/// Runs `operation`, throwing `LLMError.timeout` if it takes longer than `seconds`.
/// The operation is cancelled on timeout.
func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw LLMError.timeout
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw LLMError.timeout }
        return result
    }
}
