//
//  MockDelayProvider.swift
//  QaltiUnitTests
//
//  Created by Pavel Akhrameev on 06.03.26.
//

import Foundation
@testable import Qalti

class MockDelayProvider: DelayProvider, Loggable {
    private(set) var delayCallCount = 0
    private(set) var lastDelayInterval: TimeInterval?
    private(set) var allDelayIntervals: [TimeInterval] = []
    private(set) var totalDelayTime: TimeInterval = 0

    var shouldActuallyDelay: Bool = false
    var delayOverride: TimeInterval?

    /// If set, `delay(_:)` throws this instead of sleeping — used to exercise
    /// the caller's catch path (e.g. distinguishing CancellationError).
    var errorToThrow: Error?

    func delay(_ interval: TimeInterval) async throws {
        delayCallCount += 1
        lastDelayInterval = interval
        allDelayIntervals.append(interval)
        totalDelayTime += interval

        logger.debug("Mock delay called: \(interval)s (call #\(delayCallCount))")

        if let errorToThrow {
            throw errorToThrow
        }

        if shouldActuallyDelay {
            let actualDelay = delayOverride ?? interval
            let maxSeconds = Double(UInt64.max) / 1_000_000_000
            let safeDelay = actualDelay.isFinite ? max(0, min(actualDelay, maxSeconds)) : 0
            let nanoseconds = UInt64(safeDelay * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    func reset() {
        delayCallCount = 0
        lastDelayInterval = nil
        allDelayIntervals.removeAll()
        totalDelayTime = 0
        delayOverride = nil
        errorToThrow = nil
    }

    func wasDelayCalledWith(_ expectedInterval: TimeInterval, tolerance: TimeInterval = 0.1) -> Bool {
        return allDelayIntervals.contains { abs($0 - expectedInterval) <= tolerance }
    }

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

struct DelayProviderFactory {
    static func createForTesting(shouldActuallyDelay: Bool = false) -> MockDelayProvider {
        let provider = MockDelayProvider()
        provider.shouldActuallyDelay = shouldActuallyDelay
        return provider
    }
}
