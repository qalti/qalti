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
        // Clamp to a valid range before converting to UInt64: negative, NaN, infinite, or too large
        // values would trap or produce undefined behaviour in UInt64(...).
        let maxSeconds = Double(UInt64.max) / 1_000_000_000
        let safeInterval = interval.isFinite ? max(0, min(interval, maxSeconds)) : 0
        let nanoseconds = UInt64(safeInterval * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
