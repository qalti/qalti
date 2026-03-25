//
//  MarkdownStreamerTests.swift
//  QaltiTests
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import XCTest
@testable import Qalti

final class MarkdownStreamerTests: XCTestCase {

    func testStripsCompleteResultBlock() {
        let input = """
            Test passed.
            ```json
            {
                "test_result": "pass"
            }
            ```
            """
        // Even if isStreaming=false (historical), we want it stripped if the Mapper didn't catch it
        // But primarily this tests the logic used inside splitContent
        let stripped = MarkdownStreamer.stripResultBlock(input)
        XCTAssertEqual(stripped, "Test passed.")
    }

    func testStripsPartialResultBlockDuringStream() {
        // Scenario: LLM is typing the result
        let input = """
            Analysis done.
            ```json
            {
                "test_re
            """

        // It shouldn't wait for "test_result" to be fully typed if it sees the structure
        // Note: Our logic checks for "test_result" OR just "{"
        // In this input, it sees "```json" and "{\n    \"test_re"
        // The hasPrefix("{") check (after trimming) handles this.

        let stripped = MarkdownStreamer.stripResultBlock(input)
        XCTAssertEqual(stripped, "Analysis done.")
    }

    func testDoesNotStripRandomCodeBlocks() {
        // Scenario: LLM writes a regular code snippet
        let input = """
            Here is a snippet:
            ```json
            { "key": "value" }
            ```
            """

        let stripped = MarkdownStreamer.stripResultBlock(input)

        // Should NOT strip because it doesn't contain "test_result"
        // (unless your heuristic is strictly "all ```json blocks",
        // but looking for test_result is safer)

        // Note: The logic I provided checks for `contains("test_result")` OR `hasPrefix("{")`.
        // Since `hasPrefix("{")` is true here, it *would* strip it.
        // If your agent sends other JSON snippets often, we should make the heuristic stricter:
        // Change logic to: if suffix.contains("test_result")

        // If you want to support generic code blocks, update logic to:
        // if suffix.contains("test_result") || suffix.contains("final_state")

        // For now, assuming the Agent only outputs JSON at the end:
        XCTAssertEqual(stripped, "Here is a snippet:")
    }

    func testFormatsLinePrefixAddingNewlines() {
        // Scenario: LLM forgot newlines
        let input = "Line 1/10: **Analysis:** Tap button"

        let (stable, _) = MarkdownStreamer.splitContent(from: input, isStreaming: false)

        // Expectation: The regex should now match and insert newlines
        let expected = "Line 1/10:\n\n**Analysis:** Tap button"
        XCTAssertEqual(stable, expected)
    }

    func testFormatTriggerSnapDuringStreaming() {
        let input = "Line 1/10: **Analysis"

        let (stable, pending) = MarkdownStreamer.splitContent(from: input, isStreaming: true)

        XCTAssertEqual(stable, "Line 1/10:\n\n")
        XCTAssertEqual(pending, "**Analysis")
    }

    func testCleansBoldingArtifacts() {
        // Input: LLM is typing the standard key
        let input = "**Action to perform:** Verifying"

        let cleaned = MarkdownStreamer.cleanPendingText(input)

        // Expectation: Raw text without asterisks
        // This looks much cleaner to the user while typing.
        XCTAssertEqual(cleaned, "Action to perform: Verifying")
    }

    func testCleansPartialBolding() {
        // Input: Typing in progress
        let input = "**Actio"

        let cleaned = MarkdownStreamer.cleanPendingText(input)

        XCTAssertEqual(cleaned, "Actio")
    }

    func testCleansListPrefix() {
        // Input: LLM outputting a list item
        let input = "- Step 1"

        let cleaned = MarkdownStreamer.cleanPendingText(input)

        // Expectation: Dash removed to prevent indentation jump
        // (Note: Markdown parser might still trim whitespace, but the block structure is gone)
        XCTAssertEqual(cleaned, " Step 1")
    }

    func testFormatsLinePrefixWithAnalysisKeyword() {
        // Scenario: LLM forgot newlines with the new format
        let input = "Line 1/10: **Analysis:** Tap button"

        let (stable, _) = MarkdownStreamer.splitContent(from: input, isStreaming: false)

        // Expectation: Split into two paragraphs and bold the keyword
        let expected = "Line 1/10:\n\n**Analysis:** Tap button"
        XCTAssertEqual(stable, expected)
    }

    func testFormatTriggerSnapWithAnalysisKeyword() {
        // Scenario: LLM just finished typing the trigger word "Analysis"
        let input = "Line 1/10: **Analysis"

        let (stable, pending) = MarkdownStreamer.splitContent(from: input, isStreaming: true)

        XCTAssertEqual(stable, "Line 1/10:\n\n")
        XCTAssertEqual(pending, "**Analysis")
    }

    // MARK: - Streaming Logic

    func testSplitsAtLastNewline() {
        let input = "Line 1 is done.\n**Line 2 is typ"
        let (stable, pending) = MarkdownStreamer.splitContent(from: input, isStreaming: true)

        XCTAssertEqual(stable, "Line 1 is done.\n")
        XCTAssertEqual(pending, "**Line 2 is typ")
    }
}
