import Foundation
import Testing
@testable import QuickPromptCore

struct AnthropicResponseParserTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func parsesSingleTextBlock() throws {
        let result = try AnthropicResponseParser.parse(status: 200, data: data("""
            {"content":[{"type":"text","text":"Bonjour."}],"stop_reason":"end_turn"}
            """))
        #expect(result == .init(text: "Bonjour.", stopReason: "end_turn"))
    }

    @Test func concatenatesTextBlocksAndSkipsOthers() throws {
        let result = try AnthropicResponseParser.parse(status: 200, data: data("""
            {"content":[{"type":"text","text":"A"},{"type":"thinking","thinking":"x"},{"type":"text","text":"B"}],"stop_reason":"end_turn"}
            """))
        #expect(result.text == "AB")
    }

    @Test func emptyContentIsAnError() {
        #expect(throws: LLMError.emptyResponse) {
            try AnthropicResponseParser.parse(status: 200, data: data(#"{"content":[],"stop_reason":"end_turn"}"#))
        }
    }

    @Test func emptyTextIsAnError() {
        #expect(throws: LLMError.emptyResponse) {
            try AnthropicResponseParser.parse(status: 200, data: data(#"{"content":[{"type":"text","text":""}]}"#))
        }
    }

    @Test func missingContentIsUnexpected() {
        #expect(throws: LLMError.unexpectedResponse) {
            try AnthropicResponseParser.parse(status: 200, data: data(#"{"id":"msg"}"#))
        }
    }

    @Test func invalidJSONIsUnexpected() {
        #expect(throws: LLMError.unexpectedResponse) {
            try AnthropicResponseParser.parse(status: 200, data: data("not json"))
        }
    }

    @Test func maxTokensIsTruncated() {
        #expect(throws: LLMError.truncated) {
            try AnthropicResponseParser.parse(status: 200, data: data("""
                {"content":[{"type":"text","text":"partial"}],"stop_reason":"max_tokens"}
                """))
        }
    }

    @Test func refusalIsAnError() {
        #expect(throws: LLMError.refused) {
            try AnthropicResponseParser.parse(status: 200, data: data(
                #"{"content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"}}"#
            ))
        }
    }

    @Test func thinkingBlocksAreIgnored() throws {
        let result = try AnthropicResponseParser.parse(status: 200, data: data(
            #"{"content":[{"type":"thinking","thinking":"","signature":"x"},{"type":"text","text":"Ok."}],"stop_reason":"end_turn"}"#
        ))
        #expect(result.text == "Ok.")
    }

    @Test func httpErrorCarriesStatusAndType() {
        #expect(throws: LLMError.http(status: 401, type: "authentication_error")) {
            try AnthropicResponseParser.parse(status: 401, data: data("""
                {"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}
                """))
        }
    }

    @Test func httpErrorWithoutBody() {
        #expect(throws: LLMError.http(status: 529, type: nil)) {
            try AnthropicResponseParser.parse(status: 529, data: Data())
        }
    }
}
