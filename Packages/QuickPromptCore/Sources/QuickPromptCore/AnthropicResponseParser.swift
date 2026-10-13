import Foundation

/// Decodes Anthropic Messages API responses.
public enum AnthropicResponseParser {
    public struct Result: Equatable, Sendable {
        public let text: String
        public let stopReason: String?
    }

    struct Body: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]?
        let stop_reason: String?
    }

    struct ErrorBody: Decodable {
        struct Detail: Decodable { let type: String? }
        let error: Detail?
    }

    /// Returns the concatenated text blocks, or throws an `LLMError`.
    public static func parse(status: Int, data: Data) throws -> Result {
        guard (200..<300).contains(status) else {
            let type = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.type
            throw LLMError.http(status: status, type: type)
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              let content = body.content else {
            throw LLMError.unexpectedResponse
        }
        switch body.stop_reason {
        case "max_tokens": throw LLMError.truncated
        case "refusal": throw LLMError.refused
        default: break
        }
        let text = content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
        guard !text.isEmpty else { throw LLMError.emptyResponse }
        return Result(text: text, stopReason: body.stop_reason)
    }
}
