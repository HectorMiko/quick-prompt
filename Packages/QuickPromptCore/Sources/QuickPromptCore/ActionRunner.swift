import Foundation
import os

public enum ActionRunnerError: Error, Equatable, Sendable {
    case emptyInput
    case inputTooLong(count: Int, limit: Int)

    public var userMessage: String {
        switch self {
        case .emptyInput: "No text selected"
        case .inputTooLong(let count, let limit): "Text too long (\(count) > \(limit) characters)"
        }
    }
}

/// Runs a `TextAction` on some text. Only one run at a time: a new run cancels the previous one.
public actor ActionRunner {
    public static let maxInputLength = 20_000

    private var current: Task<String, Error>?
    private let logger = Logger(subsystem: CoreLog.subsystem, category: "runner")

    public init() {}

    /// The provider is passed per run so a backend change applies to the next run.
    public func run(_ action: TextAction, input: String, provider: any LLMProvider) async throws -> String {
        current?.cancel()

        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ActionRunnerError.emptyInput
        }
        guard input.count <= Self.maxInputLength else {
            throw ActionRunnerError.inputTooLong(count: input.count, limit: Self.maxInputLength)
        }

        let values = ["text": input]
        for name in TemplateRenderer.unknownPlaceholders(in: action.userTemplate, values: values) {
            logger.warning(
                "Unknown placeholder {{\(name, privacy: .public)}} in action \(action.id, privacy: .public)"
            )
        }
        let request = LLMRequest(
            system: action.systemPrompt,
            user: TemplateRenderer.render(action.userTemplate, values: values),
            model: action.model,
            effort: action.effort,
            temperature: action.temperature,
            maxTokens: action.maxTokens,
            timeout: action.timeout
        )

        let task = Task {
            let output = try await provider.complete(request)
            try Task.checkCancellation()
            let cleaned = OutputCleaner.clean(output)
            guard !cleaned.isEmpty else { throw LLMError.emptyResponse }
            return cleaned
        }
        current = task

        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch is CancellationError {
            throw LLMError.cancelled
        }
    }

    public func cancel() {
        current?.cancel()
        current = nil
    }
}
