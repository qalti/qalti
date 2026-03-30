//
//  RetryStrategy.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 06.03.26.
//

import Foundation
import Logging

/// Protocol defining retry strategies for handling rate limits and temporary failures
protocol RetryStrategy {
    /// Calculates the delay before the next retry attempt
    /// - Parameter attempt: The attempt number (1-based)
    /// - Returns: Delay in seconds, or nil if no more retries should be attempted
    func nextDelay(attempt: Int) -> TimeInterval?
    
    /// Determines if a retry should be attempted for the given error
    /// - Parameters:
    ///   - attempt: The attempt number (1-based)
    ///   - error: The error that occurred
    /// - Returns: True if retry should be attempted
    func shouldRetry(attempt: Int, error: Error) -> Bool
    
    /// Maximum number of retry attempts
    var maxAttempts: Int { get }
    
    /// Human-readable description of the strategy
    var description: String { get }
}

/// Default implementation for common retry logic.
///
/// - Only allows retry if `attempt < maxAttempts` (i.e., maxAttempts is the total number of tries, not retries).
/// - Explicitly checks NSError codes 429/503 for HTTP-style rate limit/service unavailable errors.
/// - Also checks error descriptions for rate-limit/quota/throttle indicators.
/// - Handles temporary network issues by matching common keywords.
///
/// This ensures callers cannot schedule a retry after the final allowed attempt, and that both error codes and strings are considered.
extension RetryStrategy {
    func shouldRetry(attempt: Int, error: Error) -> Bool {
        // attempt < maxAttempts: after the last allowed attempt there is nothing left to retry.
        guard attempt < maxAttempts else { return false }

        // Check NSError codes directly so callers that supply HTTP-style codes
        // (e.g. NSError(domain:…, code: 429)) are handled without relying on the
        // localizedDescription containing the numeric string.
        if let nsError = error as? NSError,
           nsError.code == 429 || nsError.code == 503 {
            return true
        }

        // Check description for rate-limit / quota / throttle signals.
        // Keeps parity with the indicators used in TestRunner.isRateLimitError.
        let errorString = error.localizedDescription.lowercased()
        let rateLimitIndicators = [
            "429", "503",
            "rate limit", "too many requests",
            "quota exceeded", "limit exceeded", "throttled"
        ]
        if rateLimitIndicators.contains(where: { errorString.contains($0) }) {
            return true
        }

        // Check for temporary network issues
        let networkErrors = ["timeout", "connection", "network", "temporary"]
        return networkErrors.contains { errorString.contains($0) }
    }
}

/// Exponential backoff strategy with jitter
struct ExponentialBackoffStrategy: RetryStrategy {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let jitterFactor: Double
    
    init(maxAttempts: Int = 3, 
         baseDelay: TimeInterval = 1.0, 
         maxDelay: TimeInterval = 120.0, 
         jitterFactor: Double = 0.1) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterFactor = jitterFactor
    }
    
    func nextDelay(attempt: Int) -> TimeInterval? {
        guard attempt <= maxAttempts else { return nil }
        
        // Exponential backoff: baseDelay * 2^(attempt-1)
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
        let cappedDelay = min(exponentialDelay, maxDelay)
        
        // Add jitter: ±10% random variation
        let jitter = Double.random(in: -jitterFactor...jitterFactor)
        let finalDelay = cappedDelay * (1.0 + jitter)
        
        return max(0.1, finalDelay) // Minimum 0.1 second delay
    }
    
    var description: String {
        return "Exponential backoff (max: \(maxAttempts), base: \(baseDelay)s, cap: \(maxDelay)s)"
    }
}

/// Linear backoff strategy for more predictable delays
struct LinearBackoffStrategy: RetryStrategy {
    let maxAttempts: Int
    let delayIncrement: TimeInterval
    let maxDelay: TimeInterval
    
    init(maxAttempts: Int = 5, 
         delayIncrement: TimeInterval = 10.0, 
         maxDelay: TimeInterval = 60.0) {
        self.maxAttempts = maxAttempts
        self.delayIncrement = delayIncrement
        self.maxDelay = maxDelay
    }
    
    func nextDelay(attempt: Int) -> TimeInterval? {
        guard attempt <= maxAttempts else { return nil }
        
        let linearDelay = delayIncrement * Double(attempt)
        return min(linearDelay, maxDelay)
    }
    
    var description: String {
        return "Linear backoff (max: \(maxAttempts), increment: \(delayIncrement)s, cap: \(maxDelay)s)"
    }
}

/// Fast strategy for testing with minimal delays
struct TestingStrategy: RetryStrategy {
    let maxAttempts: Int
    let fixedDelay: TimeInterval
    
    init(maxAttempts: Int = 3, fixedDelay: TimeInterval = 0.01) {
        self.maxAttempts = maxAttempts
        self.fixedDelay = fixedDelay
    }
    
    func nextDelay(attempt: Int) -> TimeInterval? {
        guard attempt <= maxAttempts else { return nil }
        return fixedDelay
    }
    
    var description: String {
        return "Testing strategy (max: \(maxAttempts), fixed: \(fixedDelay)s)"
    }
}

/// No-retry strategy: run the test exactly once and never retry
struct NoRetryStrategy: RetryStrategy {
    let maxAttempts: Int = 1
    
    func nextDelay(attempt: Int) -> TimeInterval? {
        return nil
    }
    
    func shouldRetry(attempt: Int, error: Error) -> Bool {
        return false
    }
    
    var description: String {
        return "No retry strategy"
    }
}

/// Factory for creating retry strategies based on environment and use case
struct RetryStrategyFactory {
    enum Environment {
        case production
        case development  
        case testing
        case custom(RetryStrategy)
    }
    
    static func create(for environment: Environment) -> RetryStrategy {
        switch environment {
        case .production:
            return ExponentialBackoffStrategy(
                maxAttempts: 3,
                baseDelay: 2.0,
                maxDelay: 60.0,
                jitterFactor: 0.1
            )
        case .development:
            return LinearBackoffStrategy(
                maxAttempts: 3,
                delayIncrement: 5.0,
                maxDelay: 30.0
            )
        case .testing:
            return TestingStrategy(maxAttempts: 2, fixedDelay: 0.001)
        case .custom(let strategy):
            return strategy
        }
    }
    
    /// Create strategy based on process environment
    static func createFromEnvironment() -> RetryStrategy {
        let env = ProcessInfo.processInfo.environment
        
        if env["XCTestConfigurationFilePath"] != nil {
            return create(for: .testing)
        } else if env["QALTI_DEVELOPMENT"] != nil {
            return create(for: .development)
        } else {
            return create(for: .production)
        }
    }
}
