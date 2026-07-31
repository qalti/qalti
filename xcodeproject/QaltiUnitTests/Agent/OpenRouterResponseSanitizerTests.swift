//
//  OpenRouterResponseSanitizerTests.swift
//  Qalti
//

import XCTest
import OpenAI
@testable import Qalti

/// Cover for the byte-level repair applied to OpenRouter streaming responses.
///
/// Context: two response shapes from Gemini-family models threw `DecodingError` inside the vendored
/// OpenAI client and killed the entire stream, so the agent never saw a usable reply. The fix
/// rewrites those shapes before the decoder runs. Because it edits raw bytes on the critical path
/// of every model response, the important property is not just "it patches the bad cases" but
/// "it changes nothing else" — most of these tests assert byte-identical pass-through.
final class OpenRouterResponseSanitizerTests: XCTestCase {

    // MARK: - Helpers

    private func line(_ string: String) -> Data {
        Data(string.utf8)
    }

    /// Parses a sanitized `data:` line back into JSON so assertions can be made on structure
    /// rather than on key ordering, which `JSONSerialization` does not preserve.
    private func json(
        from data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let text = try XCTUnwrap(String(data: data, encoding: .utf8), file: file, line: line)
        let payload = text.hasPrefix("data: ") ? String(text.dropFirst("data: ".count)) : text
        let object = try JSONSerialization.jsonObject(with: Data(payload.utf8))
        return try XCTUnwrap(object as? [String: Any], file: file, line: line)
    }

    // MARK: - Unknown service_tier

    func test_sanitize_stripsServiceTierOutsideTheKnownEnum() throws {
        let input = line(#"data: {"id":"x","service_tier":"provisioned"}"#)

        let result = OpenRouterResponseSanitizer.sanitize(line: input)

        let object = try json(from: result)
        XCTAssertNil(object["service_tier"], "unknown tier must be removed, not passed to the decoder")
        XCTAssertEqual(object["id"] as? String, "x", "unrelated fields must survive")
    }

    func test_sanitize_keepsServiceTierTheEnumKnows() throws {
        let known = try XCTUnwrap(ServiceTier.allCases.first).rawValue
        let input = line(#"data: {"id":"x","service_tier":"\#(known)"}"#)

        let result = OpenRouterResponseSanitizer.sanitize(line: input)

        XCTAssertEqual(result, input, "a decodable tier must pass through byte-identical")
    }

    // MARK: - Incomplete reasoning_details

    func test_sanitize_backfillsMissingReasoningTextField() throws {
        let input = line(#"data: {"choices":[{"delta":{"reasoning_details":[{"type":"reasoning.text"}]}}]}"#)

        let result = OpenRouterResponseSanitizer.sanitize(line: input)

        let object = try json(from: result)
        let choices = try XCTUnwrap(object["choices"] as? [[String: Any]])
        let delta = try XCTUnwrap(choices[0]["delta"] as? [String: Any])
        let details = try XCTUnwrap(delta["reasoning_details"] as? [[String: Any]])
        XCTAssertEqual(details[0]["text"] as? String, "")
    }

    func test_sanitize_backfillsPerTypeRequiredKey() throws {
        let cases = [
            ("reasoning.encrypted", "data"),
            ("reasoning.summary", "summary")
        ]

        for (type, requiredKey) in cases {
            let input = line(#"data: {"choices":[{"delta":{"reasoning_details":[{"type":"\#(type)"}]}}]}"#)

            let result = OpenRouterResponseSanitizer.sanitize(line: input)

            let object = try json(from: result)
            let choices = try XCTUnwrap(object["choices"] as? [[String: Any]])
            let delta = try XCTUnwrap(choices[0]["delta"] as? [String: Any])
            let details = try XCTUnwrap(delta["reasoning_details"] as? [[String: Any]])
            XCTAssertEqual(details[0][requiredKey] as? String, "", "\(type) should gain \(requiredKey)")
        }
    }

    func test_sanitize_doesNotOverwriteAReasoningFieldThatIsPresent() throws {
        let input = line(#"data: {"choices":[{"delta":{"reasoning_details":[{"type":"reasoning.text","text":"thinking"}]}}]}"#)

        let result = OpenRouterResponseSanitizer.sanitize(line: input)

        XCTAssertEqual(result, input, "a complete entry must not be rewritten at all")
    }

    func test_sanitize_ignoresReasoningTypeItDoesNotKnow() throws {
        let input = line(#"data: {"choices":[{"delta":{"reasoning_details":[{"type":"reasoning.future"}]}}]}"#)

        let result = OpenRouterResponseSanitizer.sanitize(line: input)

        XCTAssertEqual(result, input, "unknown types must pass through rather than gain invented keys")
    }

    // MARK: - Pass-through fidelity

    /// The sanitizer runs on every line of every response, so anything it doesn't recognise must
    /// come out exactly as it went in — including whitespace and key order it would otherwise lose
    /// by round-tripping through JSONSerialization.
    func test_sanitize_passesUnrelatedLinesThroughByteIdentical() {
        let inputs = [
            #"data: {"choices":[{"delta":{"content":"hello"}}],"id":"chatcmpl-1"}"#,
            "data: [DONE]",
            "",
            ": openrouter processing",
            "event: message",
            #"{"not":"an sse line"}"#,
            #"data: {"malformed": "#,
            "data: not json at all"
        ]

        for input in inputs {
            let data = line(input)
            XCTAssertEqual(OpenRouterResponseSanitizer.sanitize(line: data), data, "mutated: \(input)")
        }
    }

    func test_sanitize_preservesTrailingCarriageReturnWhenPatching() throws {
        let input = line("data: {\"service_tier\":\"provisioned\"}\r")

        let result = OpenRouterResponseSanitizer.sanitize(line: input)

        XCTAssertEqual(result.last, 0x0D, "CRLF framing must survive a patch")
        XCTAssertNil(try json(from: result.dropLast())["service_tier"])
    }

    // MARK: - Chunk reassembly

    func test_streamBuffer_emitsOnlyCompleteLines() {
        let buffer = OpenRouterResponseSanitizer.StreamBuffer()

        XCTAssertEqual(buffer.consume(line("data: {\"a\":1}\n")), line("data: {\"a\":1}\n"))
    }

    /// A single `didReceive data:` call is not guaranteed to land on a line boundary, which is the
    /// whole reason the buffer exists: sanitizing half a JSON object would corrupt it.
    func test_streamBuffer_reassemblesALineSplitAcrossChunks() throws {
        let buffer = OpenRouterResponseSanitizer.StreamBuffer()

        let first = buffer.consume(line("data: {\"service_ti"))
        XCTAssertTrue(first.isEmpty, "a partial line must not be emitted")

        let second = buffer.consume(line("er\":\"provisioned\"}\n"))
        XCTAssertNil(try json(from: second.dropLast())["service_tier"], "patch applies once reassembled")
    }

    func test_streamBuffer_emitsEveryLineWhenOneChunkHoldsSeveral() {
        let buffer = OpenRouterResponseSanitizer.StreamBuffer()

        let result = buffer.consume(line("data: {\"a\":1}\ndata: {\"b\":2}\ndata: [DONE]\n"))

        XCTAssertEqual(result, line("data: {\"a\":1}\ndata: {\"b\":2}\ndata: [DONE]\n"))
    }

    func test_streamBuffer_preservesBlankLinesThatFrameSSEEvents() {
        let buffer = OpenRouterResponseSanitizer.StreamBuffer()

        let result = buffer.consume(line("data: {\"a\":1}\n\n"))

        XCTAssertEqual(result, line("data: {\"a\":1}\n\n"), "event framing must not be swallowed")
    }

    /// Documents deliberate behaviour rather than a defect: a line with no terminating newline is
    /// held back, and `ServerSentEventsStreamParser` does exactly the same with its own
    /// `incompleteLine`, so nothing that would otherwise have been delivered is lost.
    func test_streamBuffer_withholdsAnUnterminatedTrailingLine() {
        let buffer = OpenRouterResponseSanitizer.StreamBuffer()

        XCTAssertTrue(buffer.consume(line("data: {\"a\":1}")).isEmpty)
    }

    // MARK: - Middleware wiring

    /// The sanitizer only protects anything if the middleware the OpenAI client actually calls
    /// routes through it. Every other test here exercises the sanitizer directly, so without this
    /// one a middleware that quietly returned its input unchanged would still show a green suite
    /// while Gemini responses crashed exactly as before.
    func test_errorDecodingMiddleware_sanitizesStreamedChunks() throws {
        let middleware = IOSAgent.ErrorDecodingMiddleware()
        let chunk = line("data: {\"id\":\"x\",\"service_tier\":\"provisioned\"}\n")

        let result = middleware.interceptStreamingData(request: nil, chunk)

        XCTAssertNil(
            try json(from: result.dropLast())["service_tier"],
            "middleware must route through the sanitizer, not pass raw bytes to the decoder"
        )
    }

    /// The middleware must also do the buffering, not just the patching — an SSE line split across
    /// two `didReceive data:` callbacks has to be reassembled before it can be inspected.
    func test_errorDecodingMiddleware_buffersAcrossChunks() throws {
        let middleware = IOSAgent.ErrorDecodingMiddleware()

        XCTAssertTrue(middleware.interceptStreamingData(request: nil, line("data: {\"service_ti")).isEmpty)

        let completed = middleware.interceptStreamingData(request: nil, line("er\":\"provisioned\"}\n"))
        XCTAssertNil(try json(from: completed.dropLast())["service_tier"])
    }

    func test_errorDecodingMiddleware_leavesOrdinaryChunksUntouched() {
        let middleware = IOSAgent.ErrorDecodingMiddleware()
        let chunk = line("data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}\n")

        XCTAssertEqual(middleware.interceptStreamingData(request: nil, chunk), chunk)
    }

    func test_streamBuffer_keepsChunkBoundariesIndependentOfLineBoundaries() {
        let buffer = OpenRouterResponseSanitizer.StreamBuffer()
        let whole = "data: {\"a\":1}\ndata: {\"b\":2}\n"

        var reassembled = Data()
        for byte in Array(whole.utf8) {
            reassembled.append(buffer.consume(Data([byte])))
        }

        XCTAssertEqual(reassembled, line(whole), "byte-at-a-time delivery must produce the same bytes")
    }
}
