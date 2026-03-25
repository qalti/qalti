import XCTest
import OpenAI
@testable import Qalti

final class TestRunTests: XCTestCase {

    var loader: TestFileLoader!
    var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let mockErrorCapturer = MockErrorCapturer()
        loader = TestFileLoader(errorCapturer: mockErrorCapturer)

        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectoryURL)
        loader = nil
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    private func createTemporaryFile(named fileName: String, content: String) throws -> URL {
        let fileURL = temporaryDirectoryURL.appendingPathComponent(fileName)
        try content.data(using: .utf8)?.write(to: fileURL)
        return fileURL
    }

    // MARK: - Sample Data

    private var v2RunJSON: String {
        """
        {
            "version": 2,
            "originalVersion": null,
            "runSucceeded": true,
            "runFailureReason": null,
            "timestamp": "2025-11-13T10:00:00Z",
            "test": "v2 action 1\\nv2 action 2",
            "testResult": { "test_result": "pass", "comments": "V2 Pass", "test_objective_achieved": true, "steps_followed_exactly": true, "adaptations_made": [], "final_state_description": "" },
            "runHistory": [
                {
                    "message": { "role": "assistant", "content": "Thinking..." },
                    "timestamp": "2025-11-13T10:00:01.123Z"
                },
                {
                    "message": { "role": "tool", "content": "Result", "tool_call_id": "call_1" },
                    "timestamp": "2025-11-13T10:00:03.456Z"
                }
            ]
        }
        """
    }

    private var v1RunJSON: String {
        """
        {
            "version": 1,
            "runSucceeded": false,
            "runFailureReason": "User cancelled",
            "timestamp": "2025-11-13T11:00:00Z",
            "test": "v1 action",
            "testResult": null,
            "runHistory": [
                { "role": "assistant", "content": "Thinking...", "timestamp": "2025-11-13T11:00:01Z"}
            ]
        }
        """
    }

    private var v0RunJSON: String {
        """
        {
            "success": true,
            "errorMessage": null,
            "timestamp": "2025-11-13T12:00:00Z",
            "testActions": [
                { "action": "v0 action 1", "parsedAction": "v0 action 1" },
                { "action": "v0 action 2", "parsedAction": "v0 action 2" }
            ],
            "runHistory": [
                { "role": "assistant", "content": "Finalizing... ```json{\\"test_result\\":\\"failed\\", \\"comments\\":\\"V0 fail\\", \\"test_objective_achieved\\":false, \\"steps_followed_exactly\\":true, \\"adaptations_made\\":[], \\"final_state_description\\":\\"Wrong state\\"}```" }
            ]
        }
        """
    }

    private var v0CorruptHistoryJSON: String {
        """
        {
            "success": true,
            "errorMessage": null,
            "timestamp": "2025-11-13T13:00:00Z",
            "testActions": [{ "action": "v0 corrupt", "parsedAction": "v0 corrupt" }],
            "runHistory": [
                { "role": "assistant", "content": "This message is OK." },
                { "role": "user", "content": [{"type": "image_url", "image_url": {"detail": "auto"}}] },
                { "role": "tool", "content": "This message is also OK.", "tool_call_id": "call_2" }
            ]
        }
        """
    }

    // MARK: - Decoding and Migration Tests

    func testLoad_V2Run_SucceedsAndIsCorrect() throws {
        // Arrange
        let fileURL = try createTemporaryFile(named: "test_run_v2.json", content: v2RunJSON)

        // Act
        let result = try loader.load(from: fileURL)
        let testRun = try XCTUnwrap(result.testRun)

        // Assert
        XCTAssertEqual(testRun.version, 2)
        XCTAssertNil(testRun.originalVersion)
        XCTAssertTrue(testRun.runSucceeded)
        XCTAssertEqual(testRun.testResult?.testResult, .pass)
        XCTAssertEqual(testRun.test, "v2 action 1\nv2 action 2")
        XCTAssertEqual(testRun.runHistory.count, 2)

        let duration = testRun.runHistory[1].timestamp.timeIntervalSince(testRun.runHistory[0].timestamp)
        XCTAssertEqual(duration, 2.333, accuracy: 0.001)

        // Test protocol conformance
        XCTAssertTrue(testRun.isTestPassed)
        XCTAssertEqual(testRun.displayStatusMessage, "Loaded test run (Result: PASS)")
    }

    func testLoad_V1Run_SucceedsAndMigratesToV2() throws {
        // Arrange
        let fileURL = try createTemporaryFile(named: "test_run_v1.json", content: v1RunJSON)

        // Act
        let result = try loader.load(from: fileURL)
        let testRun = try XCTUnwrap(result.testRun)

        // Assert Migration
        XCTAssertEqual(testRun.version, 2, "Test run should be migrated to V2")
        XCTAssertEqual(testRun.originalVersion, 1, "Original version should be tracked as 1")
        XCTAssertFalse(testRun.runSucceeded)
        XCTAssertEqual(testRun.runFailureReason, "User cancelled")
        XCTAssertEqual(testRun.test, "v1 action")

        // Assert History Conversion (all have the same placeholder timestamp)
        XCTAssertEqual(testRun.runHistory.count, 1)
        let allTimestamps = Set(testRun.runHistory.map { $0.timestamp })
        XCTAssertEqual(allTimestamps.count, 1)
    }

    func testLoad_V0Run_SucceedsAndMigratesToV2() throws {
        // Arrange
        let fileURL = try createTemporaryFile(named: "test_run_v0.json", content: v0RunJSON)

        // Act
        let result = try loader.load(from: fileURL)
        let testRun = try XCTUnwrap(result.testRun)

        // Assert Migration
        XCTAssertEqual(testRun.version, 2, "Test run should be migrated to V2")
        XCTAssertEqual(testRun.originalVersion, 0, "Original version should be tracked as 0")
        XCTAssertTrue(testRun.runSucceeded) // from `success`
        XCTAssertNil(testRun.runFailureReason) // from `errorMessage`

        // Assert `testActions` array was converted to `test` string
        let expectedTestString = "v0 action 1\nv0 action 2"
        XCTAssertEqual(testRun.test, expectedTestString)

        // Assert TestResult parsing from history
        XCTAssertNotNil(testRun.testResult)
        XCTAssertEqual(testRun.testResult?.testResult, .failed)
    }

    func testLoad_CorruptHistory_ThrowsError() throws {
        // Arrange
        let fileURL = try createTemporaryFile(named: "test_run_v0_corrupt.json", content: v0CorruptHistoryJSON)

        // Act & Assert
        XCTAssertThrowsError(try loader.load(from: fileURL)) { error in
            // Ensure we got a loader error wrapping a decoding error
            guard let loaderError = error as? TestFileLoader.LoaderError,
                  case .invalidJSONFormat(let url, let underlyingError) = loaderError else {
                XCTFail("Expected LoaderError.invalidJSONFormat but got \(error)")
                return
            }

            XCTAssertEqual(url, fileURL)

            let isNativeDecodingError = underlyingError is DecodingError
            let isOpenAIDecodingError = String(describing: type(of: underlyingError)).contains("DecodingError")

            XCTAssert(isNativeDecodingError || isOpenAIDecodingError, "Expected a decoding error, but got: \(type(of: underlyingError))")
        }
    }

    func testLoad_InvalidJSON_ThrowsDetailedError() throws {
        // Arrange
        let data = "{\"version\": 1, \"runSucceeded\": true".data(using: .utf8)!
        let fileURL = temporaryDirectoryURL.appendingPathComponent("invalid.json")
        try data.write(to: fileURL)

        // Act & Assert
        XCTAssertThrowsError(try loader.load(from: fileURL)) { error in
            guard let loaderError = error as? TestFileLoader.LoaderError,
                  case .invalidJSONFormat(let url, let underlyingError) = loaderError else {
                XCTFail("Expected LoaderError.invalidJSONFormat but got \(error)")
                return
            }

            XCTAssertEqual(url, fileURL)
            XCTAssert(underlyingError is DecodingError)
            // Check for a part of the detailed error message
            XCTAssert(loaderError.localizedDescription.contains("data is corrupted"))
        }
    }
}
