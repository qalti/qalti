//
//  DelayProvider.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 06.03.26.
//

import Foundation
import Logging

/// Protocol for providing delays in a testable way
protocol DelayProvider {
    /// Provides an asynchronous delay
    /// - Parameter interval: Time to delay in seconds
    func delay(_ interval: TimeInterval) async throws
}

/// Production implementation using system sleep
struct SystemDelayProvider: DelayProvider, Loggable {
    func delay(_ interval: TimeInterval) async throws {
        logger.debug("Delaying for \(interval) seconds")
        // Clamp to a valid range before converting to UInt64: negative, NaN, or infinite
        // values would trap or produce undefined behaviour in UInt64(...).
        let safeInterval = interval.isFinite ? max(0, interval) : 0
        let nanoseconds = UInt64(safeInterval * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

/// Mock implementation for testing that tracks calls but doesn't actually delay
class MockDelayProvider: DelayProvider, Loggable {
    private(set) var delayCallCount = 0
    private(set) var lastDelayInterval: TimeInterval?
    private(set) var allDelayIntervals: [TimeInterval] = []
    private(set) var totalDelayTime: TimeInterval = 0
    
    /// If true, will actually perform delays (useful for integration tests)
    var shouldActuallyDelay: Bool = false
    
    /// Custom delay override for specific test scenarios
    var delayOverride: TimeInterval?
    
    func delay(_ interval: TimeInterval) async throws {
        delayCallCount += 1
        lastDelayInterval = interval
        allDelayIntervals.append(interval)
        totalDelayTime += interval
        
        logger.debug("Mock delay called: \(interval)s (call #\(delayCallCount))")
        
        if shouldActuallyDelay {
            let actualDelay = delayOverride ?? interval
            // Same guard as SystemDelayProvider: clamp before UInt64 conversion.
            let safeDelay = actualDelay.isFinite ? max(0, actualDelay) : 0
            let nanoseconds = UInt64(safeDelay * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
        // Otherwise return immediately for fast tests
    }
    
    /// Reset tracking state for new test runs
    func reset() {
        delayCallCount = 0
        lastDelayInterval = nil
        allDelayIntervals.removeAll()
        totalDelayTime = 0
        delayOverride = nil
        logger.debug("Mock delay provider reset")
    }
    
    /// Check if delay was called with expected interval (within tolerance)
    func wasDelayCalledWith(_ expectedInterval: TimeInterval, tolerance: TimeInterval = 0.1) -> Bool {
        return allDelayIntervals.contains { abs($0 - expectedInterval) <= tolerance }
    }
    
    /// Verify delay progression matches expected pattern
    func verifyDelayProgression(_ expectedIntervals: [TimeInterval], tolerance: TimeInterval = 0.1) -> Bool {
        guard allDelayIntervals.count == expectedIntervals.count else { return false }
        
        for (actual, expected) in zip(allDelayIntervals, expectedIntervals) {
            if abs(actual - expected) > tolerance {
                return false
            }
        }
        return true
    }
}

/// Factory for creating delay providers based on environment
struct DelayProviderFactory {
    static func create() -> DelayProvider {
        let env = ProcessInfo.processInfo.environment
        
        if env["XCTestConfigurationFilePath"] != nil {
            // Running in tests - use mock provider
            return MockDelayProvider()
        } else {
            // Production or development - use real delays
            return SystemDelayProvider()
        }
    }
    
    /// Create provider for specific testing scenarios
    static func createForTesting(shouldActuallyDelay: Bool = false) -> MockDelayProvider {
        let provider = MockDelayProvider()
        provider.shouldActuallyDelay = shouldActuallyDelay
        return provider
    }
}