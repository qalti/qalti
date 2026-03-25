//
//  AllureAttachmentTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 03.12.25.
//

import XCTest
import OpenAI
@testable import Qalti

final class AllureAttachmentTests: XCTestCase {

    var converter: AllureConverter!
    var tempDir: URL!
    var mockDateProvider: MockDateProvider!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 3
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")

        let calendar = Calendar(identifier: .gregorian)
        guard let predictableStartDate = calendar.date(from: components) else {
            XCTFail("Failed to create a predictable start date for the test.")
            return
        }
        mockDateProvider = MockDateProvider(date: predictableStartDate)

        let startTime = mockDateProvider.now()
        converter = AllureConverter(
            outputDirectory: tempDir,
            testName: "AttachmentTest",
            testStartTime: startTime,
            testEndTime: startTime.addingTimeInterval(60),
            testSuccess: true,
            dateProvider: mockDateProvider
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        converter = nil
        tempDir = nil
        mockDateProvider = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testScreenshotIsAttachedToCorrectStepWithName() throws {
        // ARRANGE
        let t0 = Date(timeIntervalSince1970: 100)
        let t1 = Date(timeIntervalSince1970: 102)
        let t2 = Date(timeIntervalSince1970: 104)
        let t3 = Date(timeIntervalSince1970: 106)
        let t4 = Date(timeIntervalSince1970: 108)
        let t5 = Date(timeIntervalSince1970: 110)

        let history: [CodableChatMessage] = [
            makeAssistantMessage(toolCallId: "call_1", name: "tap", timestamp: t0, comment: "**Tip:** Tap button 1"),
            makeToolMessage(toolCallId: "call_1", timestamp: t1),
            makeUserMessageWithScreenshot(timestamp: t2),
            makeAssistantMessage(toolCallId: "call_2", name: "input", timestamp: t3, comment: "**Tip:** Input text"),
            makeToolMessage(toolCallId: "call_2", timestamp: t4),
            makeUserMessageWithScreenshot(timestamp: t5),
        ]

        let filePrefix = "dummy_prefix_for_parsing"

        // ACT
        let steps = try converter.parseStepsFromChatHistory(history, filePrefix: filePrefix)

        // ASSERT
        XCTAssertEqual(steps.count, 2)

        let step1 = steps[0]
        XCTAssertEqual(step1.name, "1. [tap] Tap button 1")
        XCTAssertEqual(step1.attachments?.count, 1)
        XCTAssertEqual(step1.attachments?.first?.name, "Screenshot after Step 1")

        let step2 = steps[1]
        XCTAssertEqual(step2.name, "2. [input] Input text")
        XCTAssertEqual(step2.attachments?.count, 1)
        XCTAssertEqual(step2.attachments?.first?.name, "Screenshot after Step 2")
    }

    func testUniqueScreenshotFilenamesAcrossRuns() throws {
        // ARRANGE
        let t0 = Date(timeIntervalSince1970: 500)
        let t1 = t0.addingTimeInterval(1)
        let t2 = t1.addingTimeInterval(1)

        let history: [CodableChatMessage] = [
            makeAssistantMessage(toolCallId: "call_1", name: "tap", timestamp: t0, comment: "Tap something"),
            makeToolMessage(toolCallId: "call_1", timestamp: t1),
            makeUserMessageWithScreenshot(timestamp: t2),
        ]
        let runData = TestRunData(
            runSucceeded: true, runFailureReason: nil, testResult: nil,
            timestamp: "2025-12-20T12:00:00Z", test: "dummyTest", runHistory: history
        )

        // ACT
        try converter.convertAndSave(from: runData)
        mockDateProvider.advance(by: 10) // 10 seconds later
        try converter.convertAndSave(from: runData)

        // ASSERT
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertEqual(files.count, 4, "There should be two JSON reports and two screenshot files.")

        let jsonFiles = files.filter { $0.hasSuffix("-result.json") }.sorted()
        let screenshotFiles = files.filter { $0.hasSuffix(".jpeg") }.sorted()

        let expectedPrefix1 = "20251203_120000_000"
        let expectedPrefix2 = "20251203_120010_000"

        XCTAssertEqual(jsonFiles[0], "\(expectedPrefix1)-result.json")
        XCTAssertEqual(jsonFiles[1], "\(expectedPrefix2)-result.json")

        XCTAssertTrue(screenshotFiles[0].hasPrefix(expectedPrefix1 + "_"))
        XCTAssertTrue(screenshotFiles[1].hasPrefix(expectedPrefix2 + "_"))
    }

    // MARK: - Helpers

    private let dummyBase64Image = "data:image/jpeg;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAIAAABMXPacAAABVklEQVR4nOzTMQ3CUABFUUK+AYxghQQ5GMAMAhDQsVPNdK2IP5w0vUfBS27eeL/225n9tq+eMOWuB1xdAbACYAXACoAVACsAVgCsAFgBsAJgBcAKgBUAKwBWAKwAWAGwAmAFwAqAFQArAFYArABYAbACYAXACoAVACsAVgCsAFgBsAJgBcAKgBUAKwBWAKwAWAGwAmAFwAqAFQArAFYArABYAbACYAXACoAVACsAVgCsAFgBsAJgBcAKgBUAKwA2Hp+n3jBlWf96wpQegBUAKwBWAKwAWAGwAmAFwAqAFQArAFYArABYAbACYAXACoAVACsAVgCsAFgBsAJgBcAKgBUAKwBWAKwAWAGwAmAFwAqAFQArAFYArABYAbACYAXACoAVACsAVgCsAFgBsAJgBcAKgBUAKwBWAKwAWAGwAmAFwAqAFQArAFYArABYAbACYEcAAAD//6kKB6M5Dv4cAAAAAElFTkSuQmCC"

    private func makeAssistantMessage(toolCallId: String, name: String, timestamp: Date, comment: String) -> CodableChatMessage {
        let tool = ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam(
            id: toolCallId,
            function: .init(arguments: "{}", name: name)
        )
        let param = ChatQuery.ChatCompletionMessageParam.AssistantMessageParam(
            content: .textContent(comment),
            toolCalls: [tool]
        )
        return .init(message: .assistant(param), timestamp: timestamp, parsedComments: nil)
    }

    private func makeToolMessage(toolCallId: String, timestamp: Date) -> CodableChatMessage {
        let param = ChatQuery.ChatCompletionMessageParam.ToolMessageParam(
            content: .textContent("{\"success\":true}"),
            toolCallId: toolCallId
        )
        return .init(message: .tool(param), timestamp: timestamp, parsedComments: nil)
    }

    private func makeUserMessageWithScreenshot(timestamp: Date) -> CodableChatMessage {
        let imagePart = ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.ContentPart.image(
            .init(imageUrl: .init(url: dummyBase64Image, detail: .auto))
        )
        let textPart = ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.ContentPart.text(.init(text: "Screenshot"))

        let param = ChatQuery.ChatCompletionMessageParam.UserMessageParam(content: .contentParts([textPart, imagePart]))
        return .init(message: .user(param), timestamp: timestamp, parsedComments: nil)
    }
}
