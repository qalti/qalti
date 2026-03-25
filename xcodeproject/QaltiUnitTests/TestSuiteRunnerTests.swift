//
//  TestSuiteRunnerTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 16.12.25.
//

import XCTest
@testable import Qalti

@MainActor
class TestSuiteRunnerLogicTests: XCTestCase {

    var suiteRunner: TestSuiteRunner!
    var mockFileManager: MockFileManager!
    var mockErrorCapturer: MockErrorCapturer!
    var mockIdbManager: MockIdbManager!

    var dummyRuntime: IOSRuntime!
    var errorCapturer: ErrorCapturerService!
    var dummyCredentials: CredentialsService!

    override func setUp() {
        super.setUp()
        mockFileManager = MockFileManager()
        mockErrorCapturer = MockErrorCapturer()
        mockIdbManager = MockIdbManager()

        errorCapturer = ErrorCapturerService()
        dummyCredentials = CredentialsService(errorCapturer: errorCapturer)

        dummyRuntime = IOSRuntime(
            simulatorID: "dummy-test-simulator-UDID",
            idbManager: mockIdbManager,
            errorCapturer: mockErrorCapturer
        )

        suiteRunner = TestSuiteRunner(
            documentsURL: URL(fileURLWithPath: "/tmp/docs"),
            runStorage: RunStorage(),
            credentialsService: dummyCredentials,
            idbManager: mockIdbManager,
            errorCapturer: errorCapturer,
            fileManager: mockFileManager
        )
        suiteRunner.setRuntime(dummyRuntime)
    }

    func test_startSuiteRun_whenGivenDirectory_findsTestsAndStartsRun() throws {
        // Arrange
        let documentsURL = URL(fileURLWithPath: "/tmp/docs")
        let testsDir = documentsURL.appendingPathComponent("Tests")
        let testFile = testsDir.appendingPathComponent("mytest.test")

        mockFileManager.createdDirectories.insert(testsDir)
        mockFileManager.files[testFile] = Data("test content".utf8)
        mockFileManager.enumeratorResults[testsDir] = [testFile]

        // Act: Run tests on the DIRECTORY
        suiteRunner.runTests(at: [testsDir], model: .gpt41, recordVideo: false, deleteSuccessfulVideo: false)

        // Assert
        let expectedRunRoot = documentsURL.appendingPathComponent("Runs", isDirectory: true)
        XCTAssertTrue(mockFileManager.createdDirectories.contains(expectedRunRoot), "The 'Runs' directory should have been created.")
        XCTAssertTrue(suiteRunner.isRunning, "The suite should be running because RunPlan found the test file via the enumerator.")
    }

    func test_handleCompletion_deletesVideoOnSuccess_whenFlagIsTrue() {
        // Arrange
        let videoURL = URL(fileURLWithPath: "/tmp/test-video.mp4")
        let summary = TestRunner.RunSummary(name: "Test", file: "test.json", testFileURL: nil, testRunURL: nil, videoURL: videoURL)
        let completion = TestRunner.RunCompletion.success(summary)
        suiteRunner.deleteSuccessfulVideoForCurrentSuite = true
        suiteRunner.setIsRunningForTesting(true)

        // Act
        suiteRunner.handleCompletion(completion)

        // Assert
        XCTAssertTrue(mockFileManager.removedItems.contains(videoURL), "Video file should have been deleted.")
    }

    func test_handleCompletion_doesNotDeleteVideoOnSuccess_whenFlagIsFalse() {
        // Arrange
        let videoURL = URL(fileURLWithPath: "/tmp/test-video.mp4")
        let summary = TestRunner.RunSummary(name: "Test", file: "test.json", testFileURL: nil, testRunURL: nil, videoURL: videoURL)
        let completion = TestRunner.RunCompletion.success(summary)
        suiteRunner.deleteSuccessfulVideoForCurrentSuite = false
        suiteRunner.setIsRunningForTesting(true)

        // Act
        suiteRunner.handleCompletion(completion)

        // Assert
        XCTAssertTrue(mockFileManager.removedItems.isEmpty, "Video file should NOT have been deleted.")
    }

    func test_handleCompletion_doesNotDeleteVideoOnFailure() {
        // Arrange
        let videoURL = URL(fileURLWithPath: "/tmp/test-video.mp4")
        let summary = TestRunner.RunSummary(name: "Test", file: "test.json", testFileURL: nil, testRunURL: nil, videoURL: videoURL)
        let completion = TestRunner.RunCompletion.failure(summary, error: "Test Failed")
        suiteRunner.deleteSuccessfulVideoForCurrentSuite = true
        suiteRunner.setIsRunningForTesting(true)

        // Act
        suiteRunner.handleCompletion(completion)

        // Assert
        XCTAssertTrue(mockFileManager.removedItems.isEmpty, "Video file should NOT have been deleted on failure.")
    }
}
