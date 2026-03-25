import XCTest
import OpenAI
@testable import Qalti

final class CLIModeTests: XCTestCase {

    func testLoadJsonReportDoesNotPopulateRunHistory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("sample_report.json")

        // Build a minimal report with one chat message to ensure the JSON parser runs.
        let message = ChatQuery.ChatCompletionMessageParam.user(
            .init(content: .string("hello"), name: nil)
        )
        let codableMessage = CodableChatMessage(message: message, timestamp: Date(), parsedComments: nil)
        let report = TestReportData(
            runSucceeded: true,
            runFailureReason: nil,
            testResult: nil,
            timestamp: Date().ISO8601Format(),
            test: "1. tap()",
            runHistory: [codableMessage]
        )

        let encoder = JSONEncoder.withPreciseDateEncoding()
        let data = try encoder.encode(report)
        try data.write(to: fileURL)

        let runHistory = RunHistory()
        XCTAssertEqual(runHistory.count, 0)

        let fileLoader = TestFileLoader(errorCapturer: MockErrorCapturer())
        let loadedTest = try CLICommand.loadTestFile(fileURL, fileLoader: fileLoader)

        XCTAssertEqual(loadedTest, report.test)
        XCTAssertEqual(runHistory.count, 0, "CLI loader must not hydrate run history for new runs")
        XCTAssertFalse(runHistory.hasDisplayableContent())
    }
}
