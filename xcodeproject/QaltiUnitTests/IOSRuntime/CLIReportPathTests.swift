//
//  CLIReportPathTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 05.12.25.
//

import XCTest
@testable import Qalti

final class CLIReportPathTests: XCTestCase {

    var mockDateProvider: MockDateProvider!
    let fixedDate: Date = Date(timeIntervalSince1970: 1735689600) // Jan 1, 2025, 00:00:00 GMT
    var expectedTimestamp: String = ""

    override func setUp() {
        super.setUp()
        mockDateProvider = MockDateProvider(date: fixedDate)

        // Pre-calculate the expected timestamp string
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy_MM_dd_HHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // IMPORTANT for deterministic tests
        expectedTimestamp = formatter.string(from: fixedDate)
    }

    // MARK: - Tests for buildTestRunURL

    func testBuildURL_withReportDir_usesDirAndDefaultFilename() {
        // SCENARIO: User provides --report-dir /tmp/output
        let config = makeConfig(testRunDir: URL(fileURLWithPath: "/tmp/output/"))

        let url = CLICommand.buildTestRunURL(config: config, dateProvider: mockDateProvider)

        XCTAssertEqual(url?.path, "/tmp/output/my-test_\(expectedTimestamp).json")
    }

    func testBuildURL_withReportPathAsFile_usesExactPath() {
        // SCENARIO: User provides --report-path /tmp/reports/specific-name.json
        let config = makeConfig(testRunPath: URL(fileURLWithPath: "/tmp/reports/specific-name.json"))

        let url = CLICommand.buildTestRunURL(config: config, dateProvider: mockDateProvider)

        XCTAssertEqual(url?.path, "/tmp/reports/specific-name.json")
    }

    func testBuildURL_withReportPathAsDirectory_usesDirAndDefaultFilename() {
        // SCENARIO: User provides --report-path /tmp/my-reports/ (note trailing slash)
        let config = makeConfig(testRunPath: URL(fileURLWithPath: "/tmp/my-reports/"))

        let url = CLICommand.buildTestRunURL(config: config, dateProvider: mockDateProvider)

        XCTAssertEqual(url?.path, "/tmp/my-reports/my-test_\(expectedTimestamp).json")
    }

    func testBuildURL_withDefaultPath_createsReportsSubfolder() {
        // SCENARIO: User provides no path options
        let config = makeConfig() // No paths provided

        let url = CLICommand.buildTestRunURL(config: config, dateProvider: mockDateProvider)

        // Expects it to be relative to the test file: /path/to/tests/reports/my-test_...
        XCTAssertEqual(url?.path, "/path/to/tests/reports/my-test_\(expectedTimestamp).json")
    }

    // MARK: - Test for defaultReportFilename helper

    func testDefaultReportFilename_isCorrectlyFormatted() {
        let config = makeConfig()
        let filename = CLICommand.defaultReportFilename(for: config, dateProvider: mockDateProvider)

        XCTAssertEqual(filename, "my-test_\(expectedTimestamp).json")
    }

    // MARK: - Helper

    private func makeConfig(testRunPath: URL? = nil, testRunDir: URL? = nil) -> CLIConfiguration {
        return CLIConfiguration(
            testFile: URL(fileURLWithPath: "/path/to/tests/my-test.test"),
            token: "dummy",
            model: .gpt41,
            promptsDir: nil,
            testRunPath: testRunPath,
            testRunDir: testRunDir,
            allureDir: nil,
            workingDirectory: nil,
            device: .init(),
            controlPort: 0,
            screenshotPort: 0,
            appPath: nil,
            maxIterations: 1,
            stderrLogLevel: .debug,
            logPrefix: nil,
            recordVideo: false,
            deleteSuccessfulVideos: false
        )
    }
}
