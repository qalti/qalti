//
//  RateLimitHandlingTests.swift
//  QaltiUnitTests
//
//  Created by Pavel Akhrameev on 06.03.26.
//

import XCTest
@testable import Qalti

final class RateLimitHandlingTests: XCTestCase {

    func testIsRateLimitErrorWith429Code() async {
        let errorMessage = "HTTP 429: Too many requests"
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithRateLimitText() async {
        let errorMessage = "Rate limit exceeded. Please try again later."
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithTooManyRequestsText() async {
        let errorMessage = "Too many requests sent in a short period"
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithQuotaExceededText() async {
        let errorMessage = "Quota exceeded for this API key"
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithLimitExceededText() async {
        let errorMessage = "Key limit exceeded (monthly limit). Manage it using https://openrouter.ai/settings/keys"
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithThrottledText() async {
        let errorMessage = "Request was throttled due to high load"
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithNonRateLimitMessage() async {
        let errorMessage = "Authentication failed - invalid API key"
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertFalse(isRateLimit)
    }

    func testIsRateLimitErrorCaseInsensitive() async {
        let errorMessage = "RATE LIMIT EXCEEDED"
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithPartialMatch() async {
        let errorMessage = "Service temporarily unavailable due to rate limiting"
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit)
    }

    func testIsRateLimitErrorWithEmptyString() async {
        let errorMessage = ""
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertFalse(isRateLimit)
    }

    func testIsRateLimitErrorWithNetworkError() async {
        let errorMessage = "The Internet connection appears to be offline."
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertFalse(isRateLimit)
    }

    func testIsRateLimitErrorWithServerError() async {
        let errorMessage = "Internal server error (500)"
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertFalse(isRateLimit)
    }

    // MARK: - Error Message Scenarios Based on Real OpenRouter Responses

    func testRealOpenRouterRateLimitMessage() async {
        // Based on actual OpenRouter rate limit response
        let errorMessage = "statusError(response: <NSHTTPURLResponse: 0x600002bb7760> { URL: https://openrouter.ai:443/api/v1/chat/completions } { Status Code: 429"
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

        XCTAssertTrue(isRateLimit, "Should detect 429 status code in actual error messages")
    }

    func testRealOpenRouterQuotaExceededMessage() async {
        // Based on actual OpenRouter quota response
        let errorMessage = "{\"error\":{\"message\":\"Key limit exceeded (monthly limit). Manage it using https://openrouter.ai/settings/keys\",\"code\":403}}"
        let testRunner = await createTestRunner()

        let isRateLimit = await testRunner.isRateLimitErrorForTesting(errorMessage)

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
