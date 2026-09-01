//
//  CLICommandTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import XCTest
@testable import Qalti

final class CLICommandTests: XCTestCase {

    // MARK: - Tests

    func testBuildTestRunURL_GeneratesDeterministicFilename() throws {
        // 1. Arrange
        // Fixed date: Jan 1, 2021, 12:00:00 UTC
        let fixedDate = Date(timeIntervalSince1970: 1609502400)
        let mockClock = MockDateProvider(date: fixedDate)

        // Calculate expected string based on the current machine's local time
        // (matching the behavior of CLICommand's internal formatter)
        let expectedFormatter = DateFormatter()
        expectedFormatter.dateFormat = "yyyy_MM_dd_HHmmss"
        expectedFormatter.locale = Locale(identifier: "en_US_POSIX")
        expectedFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let expectedTimestampString = expectedFormatter.string(from: fixedDate)

        let config = makeConfig(
            testFilePath: "/tmp/login.test",
            testRunPath: nil // Force generation
        )

        // 2. Act
        guard let url = CLICommand.buildTestRunURL(config: config, dateProvider: mockClock) else {
            XCTFail("URL should not be nil")
            return
        }

        // 3. Assert
        // Verify directory structure
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "reports")

        // Verify filename structure: login_{TIMESTAMP}.json
        let fileName = url.lastPathComponent
        XCTAssertTrue(fileName.hasPrefix("login_"), "Filename should start with test name")
        XCTAssertTrue(fileName.contains(expectedTimestampString), "Filename should contain deterministic timestamp: \(expectedTimestampString)")
        XCTAssertEqual(url.pathExtension, "json")
    }

    func testBuildTestRunURL_RespectsExplicitPath() throws {
        // 1. Arrange
        let mockClock = MockDateProvider()
        let explicitPath = URL(fileURLWithPath: "/custom/path/my_report.json")

        let config = makeConfig(
            testFilePath: "/tmp/login.test",
            testRunPath: explicitPath
        )

        // 2. Act
        let url = CLICommand.buildTestRunURL(config: config, dateProvider: mockClock)

        // 3. Assert
        XCTAssertEqual(url, explicitPath, "Should return the explicit path exactly as provided")
    }

    func testTimeAdvancementSimulation() {
        // This test validates that our MockDateProvider works as a class (reference type),
        // simulating how CLICommand will perceive time passing during execution.

        // 1. Arrange
        let startTimestamp: TimeInterval = 1000
        let mockClock = MockDateProvider(date: Date(timeIntervalSince1970: startTimestamp))

        // 2. Act
        let executionStart = mockClock.now() // returns 1000

        // Simulate "Run Tests" taking 5 minutes (300 seconds)
        mockClock.advance(by: 300)

        let executionEnd = mockClock.now() // returns 1300

        // 3. Assert
        let duration = executionEnd.timeIntervalSince(executionStart)
        XCTAssertEqual(duration, 300, "Duration should be exactly 300 seconds")

        // Verify actual dates
        XCTAssertEqual(executionStart, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(executionEnd, Date(timeIntervalSince1970: 1300))
    }

    // MARK: - Argument Parsing Tests

    // SCENARIO 1: --udid from command line should ALWAYS WIN
    func test_parseArguments_prioritizesCommandLineUDID_overEnvironmentVariable() throws {
        // Arrange
        let commandLineUDID = "cmd-line-udid-123"
        let mockEnvironment = MockEnvironmentProvider(
            deviceUDID: "env-var-udid-WRONG", // A conflicting environment variable
            allVariables: ["QALTI_TOKEN": "fake_token"]
        )
        let arguments = ["/path/to/test.test", "--udid", commandLineUDID]

        // Act
        let config = try runParseArguments(arguments: arguments, environment: mockEnvironment)

        // Assert
        XCTAssertEqual(config.device.udid, commandLineUDID, "The command-line UDID should take precedence.")
    }

    // SCENARIO 2: Environment variable should be used as a FALLBACK
    func test_parseArguments_usesEnvironmentVariableUDID_asFallback() throws {
        // Arrange
        let environmentUDID = "env-var-udid-456"
        let mockEnvironment = MockEnvironmentProvider(
            deviceUDID: environmentUDID, // The environment variable is set
            allVariables: ["QALTI_TOKEN": "fake_token"]
        )
        // NOTE: No --udid in the arguments list
        let arguments = ["/path/to/test.test", "--device-name", "iPhone"]

        // Act
        let config = try runParseArguments(arguments: arguments, environment: mockEnvironment)

        // Assert
        XCTAssertEqual(config.device.udid, environmentUDID, "The environment variable UDID should be used as a fallback.")
    }

    // SCENARIO 3: No UDID provided anywhere
    func test_parseArguments_udidIsNil_whenNotProvided() throws {
        // Arrange
        let mockEnvironment = MockEnvironmentProvider(
            deviceUDID: nil, // No environment variable
            allVariables: ["QALTI_TOKEN": "fake_token"]
        )
        // NOTE: No --udid in the arguments list
        let arguments = ["/path/to/test.test", "--device-name", "iPhone"]

        // Act
        let config = try runParseArguments(arguments: arguments, environment: mockEnvironment)

        // Assert
        XCTAssertNil(config.device.udid, "The device UDID should be nil if not provided in args or environment.")
    }

    // SCENARIO 4: Test that device type is correctly inferred from environment UDID
    func test_parseArguments_doesNotInferDeviceType_fromEnvironmentUDID() throws {
        // Arrange
        let realDeviceUDID = "00008120-000E25E80CF8C01E"
        let mockEnvironment = MockEnvironmentProvider(
            deviceUDID: realDeviceUDID,
            allVariables: ["QALTI_TOKEN": "fake_token"]
        )
        // NOTE: The user has NOT specified --type, so it defaults to .simulator
        let arguments = ["/path/to/test.test"]

        // Act
        let config = try runParseArguments(arguments: arguments, environment: mockEnvironment)

        // Assert
        XCTAssertEqual(config.device.udid, realDeviceUDID)
        XCTAssertEqual(config.device.type, .simulator, "Device type must not be inferred implicitly.")
    }

    // MARK: - Helpers

    private func makeConfig(testFilePath: String, testRunPath: URL?, testRunDir: URL? = nil) -> CLIConfiguration {
        return CLIConfiguration(
            testFile: URL(fileURLWithPath: testFilePath),
            token: "dummy_token",
            model: .gpt41,
            promptsDir: nil,
            testRunPath: testRunPath,
            testRunDir: testRunDir,
            allureDir: nil,
            workingDirectory: nil,
            device: .init(),
            controlPort: 8081,
            screenshotPort: 8082,
            appPath: nil,
            maxIterations: 1,
            stderrLogLevel: .debug,
            logPrefix: nil,
            recordVideo: false,
            deleteSuccessfulVideos: false,
        )
    }

    // Helper to invoke the parseArguments method for testing.
    private func runParseArguments(arguments: [String], environment: EnvironmentProviding) throws -> CLIConfiguration {
        // We must always provide a token, as the real parser requires it.
        let fullArguments = arguments + ["--token", "fake_token"]

        // Temporarily set CommandLine.arguments to our test data
        let originalArgs = CommandLine.arguments
        CommandLine.arguments = ["/path/to/qalti", "cli"] + fullArguments
        defer { CommandLine.arguments = originalArgs } // Restore after test

        // Assuming you've made parseArguments `internal` for testing
        return try CLICommand.parseArguments(from: fullArguments, environment: environment)
    }
}
