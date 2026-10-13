import Foundation

/// How a prompt reaches Claude: the Anthropic API (API key) or Claude Code (Claude subscription).
public enum Backend: String, Codable, CaseIterable, Sendable {
    case api
    case claudeCode

    /// Used when a prompt does not choose a backend.
    public static let `default` = Backend.api
}

/// Effort level (`output_config.effort` / `claude --effort`).
public enum Effort: String, Codable, CaseIterable, Sendable {
    case low, medium, high, xhigh, max
}

/// A Claude model the app knows how to call.
public struct ClaudeModel: Hashable, Sendable {
    public let id: String
    public let displayName: String
    /// Input / output price per million tokens.
    public let price: String
    /// Haiku 4.5 rejects `effort`.
    public let supportsEffort: Bool
    /// Models that always think reject `temperature`.
    public let supportsTemperature: Bool
    public let defaultTimeout: TimeInterval
    public let defaultMaxTokens: Int

    public static let haiku45 = ClaudeModel(
        id: "claude-haiku-4-5", displayName: "Haiku 4.5", price: "$1 / $5",
        supportsEffort: false, supportsTemperature: true, defaultTimeout: 30, defaultMaxTokens: 4096
    )
    public static let sonnet55 = thinking(id: "claude-sonnet-5-5", displayName: "Sonnet 5.5", price: "$2 / $10")
    public static let opus55 = thinking(id: "claude-opus-5-5", displayName: "Opus 5.5", price: "$4 / $20")
    public static let fable51 = thinking(id: "claude-fable-5-1", displayName: "Fable 5.1", price: "$10 / $50")

    public static let all: [ClaudeModel] = [haiku45, sonnet55, opus55, fable51]
    public static let `default` = haiku45
    public static let defaultEffort = Effort.low

    /// Known model for `id`. Unknown ids (edited by hand) are treated like current thinking models.
    public static func find(_ id: String) -> ClaudeModel {
        if let model = all.first(where: { $0.id == id }) { return model }
        if id.hasPrefix(haiku45.id) {
            return ClaudeModel(
                id: id, displayName: haiku45.displayName, price: haiku45.price,
                supportsEffort: false, supportsTemperature: true,
                defaultTimeout: haiku45.defaultTimeout, defaultMaxTokens: haiku45.defaultMaxTokens
            )
        }
        return thinking(id: id, displayName: id, price: "")
    }

    private static func thinking(id: String, displayName: String, price: String) -> ClaudeModel {
        ClaudeModel(
            id: id, displayName: displayName, price: price,
            supportsEffort: true, supportsTemperature: false, defaultTimeout: 120, defaultMaxTokens: 16_000
        )
    }
}
