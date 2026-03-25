//
//  AllureConverterTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import XCTest
@testable import Qalti

final class AllureConverterTests: XCTestCase {

    var converter: AllureConverter!

    override func setUp() {
        super.setUp()
        let fixedStart = Date(timeIntervalSince1970: 1000)
        let fixedEnd = Date(timeIntervalSince1970: 1060)

        let mockDateProvider = MockDateProvider()

        converter = AllureConverter(
            outputDirectory: URL(fileURLWithPath: "/dev/null"),
            testName: "TestLogic",
            testStartTime: fixedStart,
            testEndTime: fixedEnd,
            testSuccess: true,
            dateProvider: mockDateProvider
        )
    }

    override func tearDown() {
        converter = nil
        super.tearDown()
    }

    func testStatus_IsCorrectlyMappedFromTestResult_IgnoringStepFailures() {
        // SCENARIO: A step failed, but the LLM self-healed and reported a final status.
        // The final TestResult from the LLM is the ONLY thing that should matter.

        let failedStep = makeStep(status: .failed)
        let failureReason = "Test failed explicitly"

        // Case 1: LLM says "pass"
        let passingResult = makeTestResult(status: .pass)
        let status1 = converter.determineAllureStatus(runSucceeded: true, runFailureReason: nil, testResult: passingResult, steps: [failedStep])
        XCTAssertEqual(status1, .passed, "Final status should be 'passed' because TestResult is 'pass', regardless of intermediate step failures.")

        // Case 1b: LLM says "failed" with failure reason (unexpected)
        let status1b = converter.determineAllureStatus(runSucceeded: true, runFailureReason: failureReason, testResult: passingResult, steps: [failedStep])
        XCTAssertEqual(status1b, .passed, "Final status should be 'passed' because TestResult is 'pass', regardless of intermediate step failures.")

        // Case 2: LLM says "failed"
        let failingResult = makeTestResult(status: .failed)
        let status2 = converter.determineAllureStatus(runSucceeded: true, runFailureReason: failureReason, testResult: failingResult, steps: [failedStep])
        XCTAssertEqual(status2, .failed, "Final status should be 'failed' because TestResult is 'failed'.")

        // Case 2b: LLM says "failed" without failure reason (unexpected)
        let status2b = converter.determineAllureStatus(runSucceeded: true, runFailureReason: nil, testResult: failingResult, steps: [failedStep])
        XCTAssertEqual(status2b, .failed, "Final status should be 'failed' because TestResult is 'failed'.")

        // Case 3: LLM says "pass with comments"
        let commentsResult = makeTestResult(status: .passWithComments)
        let status3 = converter.determineAllureStatus(runSucceeded: true, runFailureReason: nil, testResult: commentsResult, steps: [failedStep])
        XCTAssertEqual(status3, .broken, "Final status should be 'broken' because TestResult is 'pass with comments'.")

        // Case 3b: LLM says "pass with comments" with failure reason (unexpected)
        let status3b = converter.determineAllureStatus(runSucceeded: true, runFailureReason: failureReason, testResult: commentsResult, steps: [failedStep])
        XCTAssertEqual(status3b, .broken, "Final status should be 'broken' because TestResult is 'pass with comments'.")
    }

    func testStatus_WhenNoTestResultExists_ButRunSucceeded_ReturnsPassed() {
        // SCENARIO: A legacy run or a bug where the LLM didn't produce a final JSON.
        // If the process finished successfully, we should treat it as a pass.
        let status = converter.determineAllureStatus(
            runSucceeded: true,
            runFailureReason: nil,
            testResult: nil,
            steps: [makeStep(status: .passed)] // All steps were technically fine
        )
        XCTAssertEqual(status, .passed)
    }

    func testStatus_WhenRecoverableErrorOccurs_AndLLMSaysPass_ReturnsPassed() {
        // SCENARIO: The LLM forgot a comment, the step failed, but it recovered and the final result is "pass".
        // EXPECTED: The overall test is "passed".

        // 1. Create a "failed" step that matches our recoverable pattern.
        let recoverableErrorDetails = AllureTestResult.AllureStatusDetails(
            message: "Failed: Tool call was NOT executed because you did not provide a comment...",
            trace: nil
        )
        let recoverableStep = makeStep(status: .failed, details: recoverableErrorDetails)

        // 2. The LLM's final opinion is "pass".
        let passingResult = makeTestResult(status: .pass)

        // Act
        let status = converter.determineAllureStatus(
            runSucceeded: true,
            runFailureReason: nil,
            testResult: passingResult,
            steps: [recoverableStep]
        )

        // Assert
        XCTAssertEqual(status, .passed, "A self-healed 'missing comment' error should not mark the test as broken if it ultimately passed.")
    }

    // MARK: - Priority 1: Infrastructure Failures

    func testStatus_WhenRunCrashed_ReturnsBroken() {
        // Scenario: The agent crashed, no TestResult was produced.
        let status = converter.determineAllureStatus(
            runSucceeded: false,
            runFailureReason: "Agent crashed",
            testResult: nil,
            steps: [] // No steps might have been recorded
        )

        XCTAssertEqual(status, .broken)
    }

    // MARK: - Priority 2: LLM Semantic Results (When steps are OK)

    func testStatus_WhenAllStepsPass_AndResultIsPass_ReturnsPassed() {
        let result = makeTestResult(status: .pass)
        let passedStep = makeStep(status: .passed)

        let status = converter.determineAllureStatus(
            runSucceeded: true,
            runFailureReason: nil,
            testResult: result,
            steps: [passedStep]
        )

        XCTAssertEqual(status, .passed)
    }

    func testStatus_WhenAllStepsPass_AndResultIsFailed_ReturnsFailed() {
        // Scenario: All tools worked, but the LLM detected a logical error.
        let result = makeTestResult(status: .failed)
        let passedStep = makeStep(status: .passed)

        let status = converter.determineAllureStatus(
            runSucceeded: true,
            runFailureReason: nil,
            testResult: result,
            steps: [passedStep]
        )

        XCTAssertEqual(status, .failed, "LLM's logical failure should be respected if steps are clean.")
    }

    func testStatus_WhenAllStepsPass_AndResultIsPassWithComments_ReturnsBroken() {
        let result = makeTestResult(status: .passWithComments)
        let passedStep = makeStep(status: .passed)

        let status = converter.determineAllureStatus(
            runSucceeded: true,
            runFailureReason: nil,
            testResult: result,
            steps: [passedStep]
        )

        XCTAssertEqual(status, .broken)
    }

    // MARK: - Helpers

    private func makeTestResult(status: TestResultStatus) -> TestResult {
        return TestResult(
            testResult: status,
            comments: "Dummy comments",
            testObjectiveAchieved: status != .failed,
            stepsFollowedExactly: status == .pass,
            adaptationsMade: [],
            finalStateDescription: "Finished"
        )
    }

    private func makeStep(status: AllureStatus, details: AllureTestResult.AllureStatusDetails? = nil) -> AllureTestResult.AllureStep {
        return AllureTestResult.AllureStep(
            name: "dummy step",
            status: status,
            statusDetails: details,
            start: 0,
            stop: 0,
            attachments: nil,
            parameters: nil
        )
    }
}
