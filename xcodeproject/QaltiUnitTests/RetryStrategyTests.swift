//
//  RetryStrategyTests.swift
//  QaltiUnitTests
//
//  Created by Pavel Akhrameev on 06.03.26.
//

import XCTest
@testable import Qalti

final class RetryStrategyTests: XCTestCase {

    func testExponentialBackoffDelayCalculation() {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 3,
            baseDelay: 1.0,
            maxDelay: 10.0,
            jitterFactor: 0.0 // No jitter for predictable tests
        )
        
        // Test delay progression: 1s, 2s, 4s
        XCTAssertEqual(strategy.nextDelay(attempt: 1)!, 1.0, accuracy: 0.01)
        XCTAssertEqual(strategy.nextDelay(attempt: 2)!, 2.0, accuracy: 0.01)
        XCTAssertEqual(strategy.nextDelay(attempt: 3)!, 4.0, accuracy: 0.01)
        XCTAssertNil(strategy.nextDelay(attempt: 4)) // Exceeds max attempts
    }
    
    func testExponentialBackoffMaxDelayCapps() {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 10,
            baseDelay: 2.0,
            maxDelay: 5.0,
            jitterFactor: 0.0
        )
        
        // After reaching max delay, should stay capped
        XCTAssertEqual(strategy.nextDelay(attempt: 1)!, 2.0, accuracy: 0.01)
        XCTAssertEqual(strategy.nextDelay(attempt: 2)!, 4.0, accuracy: 0.01)
        XCTAssertEqual(strategy.nextDelay(attempt: 3)!, 5.0, accuracy: 0.01) // Capped
        XCTAssertEqual(strategy.nextDelay(attempt: 4)!, 5.0, accuracy: 0.01) // Still capped
    }
    
    func testExponentialBackoffWithJitter() {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 3,
            baseDelay: 10.0,
            maxDelay: 100.0,
            jitterFactor: 0.1
        )
        
        // With 10% jitter, delay should be within ±10% of expected value
        let delay1 = strategy.nextDelay(attempt: 1)!
        XCTAssertTrue(delay1 >= 9.0 && delay1 <= 11.0, "Delay1 \(delay1) should be 10 ± 10%")
        
        let delay2 = strategy.nextDelay(attempt: 2)!
        XCTAssertTrue(delay2 >= 18.0 && delay2 <= 22.0, "Delay2 \(delay2) should be 20 ± 10%")
    }
    
    func testLinearBackoffDelayCalculation() {
        let strategy = LinearBackoffStrategy(
            maxAttempts: 4,
            delayIncrement: 5.0,
            maxDelay: 20.0
        )
        
        // Test linear progression: 5s, 10s, 15s, 20s
        XCTAssertEqual(strategy.nextDelay(attempt: 1), 5.0)
        XCTAssertEqual(strategy.nextDelay(attempt: 2), 10.0)
        XCTAssertEqual(strategy.nextDelay(attempt: 3), 15.0)
        XCTAssertEqual(strategy.nextDelay(attempt: 4), 20.0) // Reaches max
        XCTAssertNil(strategy.nextDelay(attempt: 5)) // Exceeds max attempts
    }
    
    func testLinearBackoffMaxDelayCap() {
        let strategy = LinearBackoffStrategy(
            maxAttempts: 5,
            delayIncrement: 15.0,
            maxDelay: 25.0
        )
        
        XCTAssertEqual(strategy.nextDelay(attempt: 1), 15.0)
        XCTAssertEqual(strategy.nextDelay(attempt: 2), 25.0) // Capped at max
        XCTAssertEqual(strategy.nextDelay(attempt: 3), 25.0) // Still capped
    }
    
    func testTestingStrategyMinimalDelays() {
        let strategy = TestingStrategy(maxAttempts: 2, fixedDelay: 0.01)
        
        XCTAssertEqual(strategy.nextDelay(attempt: 1), 0.01)
        XCTAssertEqual(strategy.nextDelay(attempt: 2), 0.01)
        XCTAssertNil(strategy.nextDelay(attempt: 3))
    }
    
    func testNoRetryStrategy() {
        let strategy = NoRetryStrategy()
        
        XCTAssertEqual(strategy.maxAttempts, 0)
        XCTAssertNil(strategy.nextDelay(attempt: 1))
        XCTAssertFalse(strategy.shouldRetry(attempt: 1, error: TestError.rateLimitError))
    }
    
    func testShouldRetryForRateLimitErrors() {
        let strategy = ExponentialBackoffStrategy(maxAttempts: 3)
        
        XCTAssertTrue(strategy.shouldRetry(attempt: 1, error: TestError.rateLimitError))
        XCTAssertTrue(strategy.shouldRetry(attempt: 2, error: TestError.rateLimitError))
        XCTAssertTrue(strategy.shouldRetry(attempt: 3, error: TestError.rateLimitError))
        XCTAssertFalse(strategy.shouldRetry(attempt: 4, error: TestError.rateLimitError)) // Exceeds max
    }
    
    func testShouldRetryForNetworkErrors() {
        let strategy = LinearBackoffStrategy(maxAttempts: 2)
        
        XCTAssertTrue(strategy.shouldRetry(attempt: 1, error: TestError.networkTimeout))
        XCTAssertTrue(strategy.shouldRetry(attempt: 1, error: TestError.connectionLost))
    }
    
    func testShouldNotRetryForNonRetryableErrors() {
        let strategy = ExponentialBackoffStrategy(maxAttempts: 3)
        
        XCTAssertFalse(strategy.shouldRetry(attempt: 1, error: TestError.authenticationError))
        XCTAssertFalse(strategy.shouldRetry(attempt: 1, error: TestError.genericError))
    }
    
    func testRetryStrategyFactoryEnvironments() {
        let production = RetryStrategyFactory.create(for: .production)
        let development = RetryStrategyFactory.create(for: .development)
        let testing = RetryStrategyFactory.create(for: .testing)
        
        XCTAssertTrue(production is ExponentialBackoffStrategy)
        XCTAssertTrue(development is LinearBackoffStrategy)
        XCTAssertTrue(testing is TestingStrategy)
        
        // Test custom strategy
        let custom = NoRetryStrategy()
        let customStrategy = RetryStrategyFactory.create(for: .custom(custom))
        XCTAssertTrue(customStrategy is NoRetryStrategy)
    }
    
    func testRetryStrategyDescriptions() {
        let exponential = ExponentialBackoffStrategy()
        let linear = LinearBackoffStrategy()
        let testing = TestingStrategy()
        let noRetry = NoRetryStrategy()
        
        XCTAssertFalse(exponential.description.isEmpty)
        XCTAssertFalse(linear.description.isEmpty)
        XCTAssertFalse(testing.description.isEmpty)
        XCTAssertFalse(noRetry.description.isEmpty)
    }
}

// MARK: - Test Helper Errors

private enum TestError: Error, LocalizedError {
    case rateLimitError
    case networkTimeout
    case connectionLost
    case authenticationError
    case genericError
    
    var errorDescription: String? {
        switch self {
        case .rateLimitError:
            return "Rate limit exceeded (429)"
        case .networkTimeout:
            return "Network timeout occurred"
        case .connectionLost:
            return "Network connection lost"
        case .authenticationError:
            return "Authentication failed"
        case .genericError:
            return "Generic error"
        }
    }
}
