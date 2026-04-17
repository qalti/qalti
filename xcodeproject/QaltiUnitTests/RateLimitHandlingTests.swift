//
//  RateLimitHandlingTests.swift
//  QaltiUnitTests
//
//  Created by Pavel Akhrameev on 06.03.26.
//

import XCTest
@testable import Qalti

@MainActor
final class RateLimitHandlingTests: XCTestCase {

    func testIsRateLimitErrorWith429Code() {
        let errorMessage = "HTTP 429: Too many requests"
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithRateLimitText() {
        let errorMessage = "Rate limit exceeded. Please try again later."
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithTooManyRequestsText() {
        let errorMessage = "Too many requests sent in a short period"
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithQuotaExceededText() {
        let errorMessage = "Quota exceeded for this API key"
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithLimitExceededText() {
        let errorMessage = "Key limit exceeded (monthly limit). Manage it using https://openrouter.ai/settings/keys"
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithThrottledText() {
        let errorMessage = "Request was throttled due to high load"
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithNonRateLimitMessage() {
        let errorMessage = "Authentication failed - invalid API key"
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertFalse(isRateLimit)
    }

    func testIsRateLimitErrorCaseInsensitive() {
        let errorMessage = "RATE LIMIT EXCEEDED"
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithPartialMatch() {
        let errorMessage = "Service temporarily unavailable due to rate limiting"
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithEmptyString() {
        let errorMessage = ""
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertFalse(isRateLimit)
    }

    func testIsRateLimitErrorWithNetworkError() {
        let errorMessage = "The Internet connection appears to be offline."
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertFalse(isRateLimit)
    }

    func testIsRateLimitErrorWithServerError() {
        let errorMessage = "Internal server error (500)"
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertFalse(isRateLimit)
    }

    // MARK: - Error Message Scenarios Based on Real OpenRouter Responses

    func testRealOpenRouterRateLimitMessage() {
        // Based on actual OpenRouter rate limit response
        let errorMessage = "statusError(response: <NSHTTPURLResponse: 0x600002bb7760> { URL: https://openrouter.ai:443/api/v1/chat/completions } { Status Code: 429"
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit, "Should detect 429 status code in actual error messages")
    }

    func testRealOpenRouterQuotaExceededMessage() {
        // Based on actual OpenRouter quota response
        let errorMessage = "{\"error\":{\"message\":\"Key limit exceeded (monthly limit). Manage it using https://openrouter.ai/settings/keys\",\"code\":403}}"
        let testRunner = createTestRunner()

        let isRateLimit = testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit, "Should detect quota exceeded messages")
    }

    // MARK: - Test Helper Methods

    @MainActor
    private func createTestRunner() -> TestRunner {
        let mockDelayProvider = MockDelayProvider()
        let testingStrategy = TestingStrategy()
        let mockErrorCapturer = MockErrorCapturer()
        let mockCredentialsService = MockCredentialsService()

        // Create TestRunner with minimal dependencies for testing
        let testRunner = TestRunner(
            executionMode: .cli,
            runHistory: RunHistory(),
            recordVideo: false,
            credentialsService: mockCredentialsService,
            idbManager: MockIdbManager(),
            errorCapturer: MockErrorCapturer(),
            fileManager: MockFileManager(),
            cliRecorderFactory: nil,
            retryStrategy: testingStrategy,
            delayProvider: mockDelayProvider
        )

        return testRunner
    }
}

// MARK: - Test Helpers Extension for TestRunner

extension TestRunner {
    /// Exposed isRateLimitError method for testing purposes
    func isRateLimitErrorForTesting(_ errorMessage: String) -> Bool {
        return self.isRateLimitError(errorMessage)
    }
}
