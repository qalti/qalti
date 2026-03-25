//
//  AllureTimingTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import XCTest
import OpenAI
@testable import Qalti

final class AllureTimingTests: XCTestCase {

    var converter: AllureConverter!

    override func setUp() {
        super.setUp()

        let mockDateProvider = MockDateProvider()

        // Dummy converter; we only need it to run the parsing logic
        converter = AllureConverter(
            outputDirectory: URL(fileURLWithPath: "/dev/null"),
            testName: "TimingTest",
            testStartTime: Date(),
            testEndTime: Date(),
            testSuccess: true,
            dateProvider: mockDateProvider
        )
    }

    override func tearDown() {
        converter = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testSingleStepDuration() throws {
        // Scenario: Assistant calls 1 tool. Tool responds 5 seconds later.
        // Expected: Step duration is exactly 5 seconds.

        let startT = Date(timeIntervalSince1970: 1000)
        let endT   = Date(timeIntervalSince1970: 1005)

        let assistantMsg = makeAssistantMessage(toolCallId: "call_1", name: "tap", timestamp: startT)
        let toolMsg      = makeToolMessage(toolCallId: "call_1", timestamp: endT)

        let history = [assistantMsg, toolMsg]
        let filePrefix = "dummy-prefix"

        // Act
        let steps = try converter.parseStepsFromChatHistory(history, filePrefix: filePrefix)

        // Assert
        XCTAssertEqual(steps.count, 1)
        let step = steps[0]

        XCTAssertEqual(step.start, 1000 * 1000) // Allure uses milliseconds
        XCTAssertEqual(step.stop,  1005 * 1000)
        XCTAssertEqual(step.stop - step.start, 5000)
    }

    func testSequentialStepsChaining() throws {
        // Scenario: Assistant calls 2 tools in ONE message (Parallel/Sequential).
        // Assistant (T=100) -> [Tool A, Tool B]
        // Tool A Response (T=102)
        // Tool B Response (T=107)

        // Expected:
        // Step A: 100 -> 102 (2s)
        // Step B: 102 -> 107 (5s) <-- Critical: Step B must start when A ends, not when Assistant spoke.

        let t0 = Date(timeIntervalSince1970: 100)
        let t1 = Date(timeIntervalSince1970: 102)
        let t2 = Date(timeIntervalSince1970: 107)

        let assistantMsg = makeAssistantMultiToolMessage(
            toolCalls: [("call_A", "tap"), ("call_B", "input")],
            timestamp: t0
        )
        let toolAMsg = makeToolMessage(toolCallId: "call_A", timestamp: t1)
        let toolBMsg = makeToolMessage(toolCallId: "call_B", timestamp: t2)

        let history = [assistantMsg, toolAMsg, toolBMsg]
        let filePrefix = "dummy-prefix"

        // Act
        let steps = try converter.parseStepsFromChatHistory(history, filePrefix: filePrefix)

        // Assert
        XCTAssertEqual(steps.count, 2)

        let stepA = steps[0]
        let stepB = steps[1]

        // Verify Step A
        XCTAssertEqual(stepA.name, "1. [tap]")
        XCTAssertEqual(stepA.start, 100 * 1000)
        XCTAssertEqual(stepA.stop,  102 * 1000)

        // Verify Step B chains correctly
        XCTAssertEqual(stepB.name, "2. [input]")
        XCTAssertEqual(stepB.start, 102 * 1000, "Step B should start exactly when Step A ended")
        XCTAssertEqual(stepB.stop,  107 * 1000)
    }

    func testMissingToolResponseFallback() throws {
        // Scenario: Assistant calls tool, but app crashes/stops before tool response is recorded.
        // Expected: Step exists but has a minimal default duration (0.1s).

        let startT = Date(timeIntervalSince1970: 2000)
        let assistantMsg = makeAssistantMessage(toolCallId: "call_dead", name: "tap", timestamp: startT)

        // No tool response in history
        let history = [assistantMsg]
        let filePrefix = "dummy-prefix"

        // Act
        let steps = try converter.parseStepsFromChatHistory(history, filePrefix: filePrefix)

        // Assert
        XCTAssertEqual(steps.count, 1)
        let step = steps[0]

        XCTAssertEqual(step.start, 2000 * 1000)
        // Fallback adds 0.1s
        XCTAssertEqual(step.stop,  2000 * 1000 + 100)
    }

    // MARK: - Helpers for Constructing Messages

    private func makeAssistantMessage(toolCallId: String, name: String, timestamp: Date) -> CodableChatMessage {
        return makeAssistantMultiToolMessage(toolCalls: [(toolCallId, name)], timestamp: timestamp)
    }

    private func makeAssistantMultiToolMessage(toolCalls: [(id: String, name: String)], timestamp: Date) -> CodableChatMessage {
        let tools: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam] = toolCalls.map {
            .init(
                id: $0.id,
                function: .init(arguments: "{}", name: $0.name)
            )
        }

        let assistantParam = ChatQuery.ChatCompletionMessageParam.AssistantMessageParam(
            content: .textContent("Doing stuff"),
            toolCalls: tools
        )

        return CodableChatMessage(
            message: .assistant(assistantParam),
            timestamp: timestamp,
            parsedComments: nil
        )
    }

    private func makeToolMessage(toolCallId: String, timestamp: Date) -> CodableChatMessage {
        let toolParam = ChatQuery.ChatCompletionMessageParam.ToolMessageParam(
            content: .textContent("{\"success\":true}"),
            toolCallId: toolCallId
        )

        return CodableChatMessage(
            message: .tool(toolParam),
            timestamp: timestamp,
            parsedComments: nil
        )
    }
}
