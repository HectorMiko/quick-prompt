import Foundation
import os

public struct AnthropicAPIProvider: LLMProvider {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"

    private let apiKey: String
    private let session: URLSession
    private let logger = Logger(subsystem: CoreLog.subsystem, category: "api")

    public init(apiKey: String) {
        self.apiKey = apiKey
        // The per-request timeout is enforced by `withTimeout`.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: configuration)
    }

    struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct OutputConfig: Encodable {
            let effort: Effort
        }
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        let temperature: Double?
        let output_config: OutputConfig?

        init(_ request: LLMRequest) {
            model = request.model
            max_tokens = request.maxTokens
            system = request.system
            messages = [.init(role: "user", content: request.user)]
            temperature = request.temperature
            output_config = request.effort.map(OutputConfig.init)
        }
    }

    static func makeURLRequest(_ request: LLMRequest, apiKey: String) throws -> URLRequest {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONEncoder().encode(RequestBody(request))
        return urlRequest
    }

    public func complete(_ request: LLMRequest) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        let urlRequest = try Self.makeURLRequest(request, apiKey: apiKey)

        logger.info("""
            POST /v1/messages model=\(request.model, privacy: .public) \
            effort=\(request.effort?.rawValue ?? "none", privacy: .public) \
            max_tokens=\(request.maxTokens) timeout=\(Int(request.timeout))s input length=\(request.user.count)
            """)
        let start = Date()
        let session = session
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await withTimeout(request.timeout) {
                try await session.data(for: urlRequest)
            }
        } catch let error as LLMError {
            logger.error("API failure: \(String(describing: error), privacy: .public)")
            throw error
        } catch is CancellationError {
            throw LLMError.cancelled
        } catch let error as URLError {
            logger.error("Network error code=\(error.code.rawValue)")
            switch error.code {
            case .cancelled: throw LLMError.cancelled
            case .timedOut: throw LLMError.timeout
            default: throw LLMError.network(code: error.code.rawValue)
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        guard let http = response as? HTTPURLResponse else { throw LLMError.unexpectedResponse }
        logger.info("Status=\(http.statusCode) in \(elapsed, format: .fixed(precision: 2))s, body length=\(data.count)")

        do {
            let result = try AnthropicResponseParser.parse(status: http.statusCode, data: data)
            logger.info("stop_reason=\(result.stopReason ?? "nil", privacy: .public) output length=\(result.text.count)")
            return result.text
        } catch {
            logger.error("API failure: \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}
