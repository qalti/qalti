//
//  TestRunnerRetryTests.swift
//  QaltiUnitTests
//
//  Created by Pavel Akhrameev on 06.03.26.
//

import XCTest
@testable import Qalti

final class TestRunnerRetryTests: XCTestCase {

    private var mockDelayProvider: MockDelayProvider!
    private var mockErrorCapturer: MockErrorCapturer!
    private var mockCredentialsService: MockCredentialsService!
    private var mockIdbManager: MockIdbManager!
    
    override func setUp() {
        super.setUp()
        mockDelayProvider = MockDelayProvider()
        mockErrorCapturer = MockErrorCapturer()
        mockCredentialsService = MockCredentialsService()
        mockIdbManager = MockIdbManager()
        // Set up valid credentials
        mockCredentialsService.openRouterKey = "test-api-key"
    }
    
    override func tearDown() {
        mockDelayProvider = nil
        mockErrorCapturer = nil
        mockCredentialsService = nil
        mockIdbManager = nil
        super.tearDown()
    }
    
    func testExecuteTestWithRetry_retriesOnRateLimitErrorAndSucceeds() async {
        // Strategy allows 3 attempts; executor fails twice with a rate-limit error then succeeds
        let strategy = TestingStrategy(maxAttempts: 3, fixedDelay: 0.001)
        let runHistory = RunHistory()
        let testRunner = await TestRunner(
            executionMode: .cli,
            runHistory: runHistory,
            recordVideo: false,
            credentialsService: mockCredentialsService,
            idbManager: mockIdbManager,
            errorCapturer: mockErrorCapturer,
            retryStrategy: strategy,
            delayProvider: mockDelayProvider
        )

        var executorCallCount = 0
        let dummySummary = TestRunner.RunSummary(
            name: nil, file: nil, testFileURL: nil, testRunURL: nil, videoURL: nil
        )
        let result = await testRunner.executeTestWithRetry(testURL: URL(fileURLWithPath: "/tmp/dummy.test")) {
            executorCallCount += 1
            if executorCallCount < 3 {
                return .failure(dummySummary, error: "Rate limit exceeded")
            }
            return .success(dummySummary)
        }

        // All 3 attempts were made
        XCTAssertEqual(executorCallCount, 3)
        // Delay between attempt 1→2 and 2→3, but not after the successful 3rd attempt
        XCTAssertEqual(mockDelayProvider.delayCallCount, 2)
        if case .success = result { } else {
            XCTFail("Expected .success on third attempt")
        }
    }
    
    func testRetryStrategyProgressionWithExponentialBackoff() {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 4,
            baseDelay: 1.0,
            maxDelay: 20.0,
            jitterFactor: 0.0
        )
        
        // Test that delays follow exponential pattern
        let delays = (1...4).compactMap { strategy.nextDelay(attempt: $0) }
        let expectedDelays = [1.0, 2.0, 4.0, 8.0]
        
        for (actual, expected) in zip(delays, expectedDelays) {
            XCTAssertEqual(actual, expected, accuracy: 0.01)
        }
    }
    
    func testRetryWithDifferentErrorTypes() {
        let strategy = ExponentialBackoffStrategy(maxAttempts: 3)
        
        // Rate limit errors should be retried
        let rateLimitError = NSError(domain: "Test", code: 429, userInfo: [NSLocalizedDescriptionKey: "Rate limit exceeded"])
        XCTAssertTrue(strategy.shouldRetry(attempt: 1, error: rateLimitError))
        
        // Network errors should be retried
        let networkError = NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network timeout"])
        XCTAssertTrue(strategy.shouldRetry(attempt: 1, error: networkError))
        
        // Auth errors should not be retried (handled by default implementation)
        let authError = NSError(domain: "Test", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication failed"])
        XCTAssertFalse(strategy.shouldRetry(attempt: 1, error: authError))
    }
    
    func testDelayProviderIntegration() async {
        let mockProvider = MockDelayProvider()
        
        // Test multiple delays
        try? await mockProvider.delay(1.0)
        try? await mockProvider.delay(2.0)
        try? await mockProvider.delay(4.0)
        
        // Verify the progression was captured
        XCTAssertEqual(mockProvider.delayCallCount, 3)
        XCTAssertTrue(mockProvider.verifyDelayProgression([1.0, 2.0, 4.0]))
        XCTAssertEqual(mockProvider.totalDelayTime, 7.0)
    }
    
    func testRetryStrategy_MaxAttemptsExceeded() {
        let strategy = TestingStrategy(maxAttempts: 2, fixedDelay: 0.1)
        
        XCTAssertNotNil(strategy.nextDelay(attempt: 1))
        XCTAssertNotNil(strategy.nextDelay(attempt: 2))
        XCTAssertNil(strategy.nextDelay(attempt: 3)) // Exceeds max
        
        let rateLimitError = NSError(domain: "Test", code: 429, userInfo: [NSLocalizedDescriptionKey: "Rate limited"])
        XCTAssertTrue(strategy.shouldRetry(attempt: 1, error: rateLimitError))
        // attempt == maxAttempts: no retry remaining
        XCTAssertFalse(strategy.shouldRetry(attempt: 2, error: rateLimitError))
        XCTAssertFalse(strategy.shouldRetry(attempt: 3, error: rateLimitError)) // Exceeds max
    }
    
    func testRetryStrategyFactory_EnvironmentSelection() {
        let production = RetryStrategyFactory.create(for: .production) as! ExponentialBackoffStrategy
        let development = RetryStrategyFactory.create(for: .development) as! LinearBackoffStrategy
        let testing = RetryStrategyFactory.create(for: .testing) as! TestingStrategy
        
        // Verify different strategies have different characteristics
        XCTAssertEqual(production.maxAttempts, 3)
        XCTAssertEqual(development.maxAttempts, 3)
        XCTAssertEqual(testing.maxAttempts, 2)
        
        // Production should have longer delays than testing
        XCTAssertNotNil(production.nextDelay(attempt: 1))
        XCTAssertNotNil(development.nextDelay(attempt: 1))
        XCTAssertEqual(testing.nextDelay(attempt: 1), 0.001) // Very fast for tests
    }
    
    func testMockDelayProvider_FastExecution() async {
        let mockProvider = MockDelayProvider()
        
        let startTime = Date()
        
        // Simulate retry progression
        try? await mockProvider.delay(1.0)
        try? await mockProvider.delay(2.0)
        try? await mockProvider.delay(4.0)
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should complete almost instantly with mock
        XCTAssertLessThan(elapsed, 0.1, "Mock delays should be near-instantaneous")
        
        // But should track all the requested delays
        XCTAssertEqual(mockProvider.totalDelayTime, 7.0)
        XCTAssertEqual(mockProvider.delayCallCount, 3)
    }
    
    func testNoRetryStrategy_runsOnceWithoutCrashing() async {
        let runHistory = RunHistory()
        let noRetryStrategy = NoRetryStrategy()
        let testRunner = await TestRunner(
            executionMode: .cli,
            runHistory: runHistory,
            recordVideo: false,
            credentialsService: mockCredentialsService,
            idbManager: mockIdbManager,
            errorCapturer: mockErrorCapturer,
            retryStrategy: noRetryStrategy,
            delayProvider: mockDelayProvider
        )

        // Directly test executeTestWithRetry to ensure retry logic is exercised
        let dummySummary = TestRunner.RunSummary(name: nil, file: nil, testFileURL: nil, testRunURL: nil, videoURL: nil)
        let result = await testRunner.executeTestWithRetry(testURL: URL(fileURLWithPath: "/tmp/dummy.test")) {
            return .failure(dummySummary, error: "Some error")
        }

        switch result {
        case .failure(_, let error):
            XCTAssertFalse(error.isEmpty)
            // No delays should be requested when there are no retries
            XCTAssertEqual(mockDelayProvider.delayCallCount, 0)
        case .success, .cancelled:
            XCTFail("Expected failure due to missing runtime")
        }
    }

    func testNoRetryStrategy_executesOnceWithoutRetryOrDelay() async {
        let runHistory = RunHistory()
        let testRunner = await TestRunner(
            executionMode: .cli,
            runHistory: runHistory,
            recordVideo: false,
            credentialsService: mockCredentialsService,
            idbManager: mockIdbManager,
            errorCapturer: mockErrorCapturer,
            retryStrategy: NoRetryStrategy(),
            delayProvider: mockDelayProvider
        )

        var executorCallCount = 0
        let dummySummary = TestRunner.RunSummary(
            name: nil, file: nil, testFileURL: nil, testRunURL: nil, videoURL: nil
        )
        let result = await testRunner.executeTestWithRetry(testURL: URL(fileURLWithPath: "/tmp/dummy.test")) {
            executorCallCount += 1
            return .failure(dummySummary, error: "Rate limit exceeded")
        }

        // Executor must be called exactly once — no retries with NoRetryStrategy
        XCTAssertEqual(executorCallCount, 1)
        XCTAssertEqual(mockDelayProvider.delayCallCount, 0)
        if case .failure = result { } else {
            XCTFail("Expected .failure result")
        }
    }

    func testExecuteTestWithRetry_returnsLastFailureSummaryOnExhaustion() async {
        // Arrange: create a dummy summary with non-nil URLs to simulate a real failure
        let expectedTestRunURL = URL(fileURLWithPath: "/tmp/fake_test_run.json")
        let expectedVideoURL = URL(fileURLWithPath: "/tmp/fake_video.mp4")
        let dummySummary = TestRunner.RunSummary(
            name: "TestName",
            file: "TestFile.swift",
            testFileURL: URL(fileURLWithPath: "/tmp/testfile"),
            testRunURL: expectedTestRunURL,
            videoURL: expectedVideoURL
        )
        let runHistory = RunHistory()
        let testRunner = await TestRunner(
            executionMode: .cli,
            runHistory: runHistory,
            recordVideo: false,
            credentialsService: mockCredentialsService,
            idbManager: mockIdbManager,
            errorCapturer: mockErrorCapturer,
            retryStrategy: TestingStrategy(maxAttempts: 2, fixedDelay: 0.01),
            delayProvider: mockDelayProvider
        )
        var callCount = 0
        // Always fail, return our dummy summary with a retryable error string
        let result = await testRunner.executeTestWithRetry(testURL: URL(fileURLWithPath: "/tmp/testfile")) {
            callCount += 1
            return .failure(dummySummary, error: "Rate limit exceeded")
        }
        // Should have retried twice (maxAttempts)
        XCTAssertEqual(callCount, 2)
        // Should return the last failure summary, not a new one with nil URLs
        if case .failure(let summary, let error) = result {
            XCTAssertEqual(summary.testRunURL, expectedTestRunURL, "Should return last failure summary with correct testRunURL")
            XCTAssertEqual(summary.videoURL, expectedVideoURL, "Should return last failure summary with correct videoURL")
            XCTAssertEqual(error, "Rate limit exceeded")
        } else {
            XCTFail("Expected .failure result")
        }
    }

    // MARK: - Helper Methods
    
    private func createTempTestFile(content: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_\(UUID().uuidString).test")
        
        do {
            try content.write(to: testFile, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to create temp test file: \(error)")
        }
        
        return testFile
    }
}
