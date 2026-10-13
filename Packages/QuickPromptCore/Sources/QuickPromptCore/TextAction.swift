import Foundation

/// A prompt resolved into everything needed for one model call.
public struct TextAction: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var systemPrompt: String
    public var userTemplate: String
    public var backend: Backend
    public var model: String
    /// `nil` when the model does not support effort.
    public var effort: Effort?
    /// `nil` when the model rejects `temperature`.
    public var temperature: Double?
    public var maxTokens: Int
    public var timeout: TimeInterval

    public init(
        id: String,
        name: String,
        systemPrompt: String,
        userTemplate: String = TextAction.userTemplate,
        backend: Backend = .default,
        model: String,
        effort: Effort?,
        temperature: Double?,
        maxTokens: Int,
        timeout: TimeInterval
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.userTemplate = userTemplate
        self.backend = backend
        self.model = model
        self.effort = effort
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeout = timeout
    }
}

extension TextAction {
    /// The selected text is always wrapped in tags so the model treats it as data.
    public static let userTemplate = "<texte>\n{{text}}\n</texte>"

    /// Resolves a prompt: empty fields take the model defaults.
    public init(prompt: PromptItem) {
        let model = ClaudeModel.find(prompt.model ?? ClaudeModel.default.id)
        self.init(
            id: prompt.id,
            name: prompt.name,
            systemPrompt: prompt.prompt,
            backend: prompt.backend ?? .default,
            model: model.id,
            effort: model.supportsEffort ? (prompt.effort ?? ClaudeModel.defaultEffort) : nil,
            temperature: model.supportsTemperature ? 0 : nil,
            maxTokens: prompt.maxTokens.flatMap { $0 > 0 ? $0 : nil } ?? model.defaultMaxTokens,
            timeout: prompt.timeoutSeconds.flatMap { $0 > 0 ? $0 : nil } ?? model.defaultTimeout
        )
    }

    public static let grammar = TextAction(
        prompt: PromptItem(id: "grammar", name: "Correct", prompt: DefaultPrompts.correct)
    )
}
