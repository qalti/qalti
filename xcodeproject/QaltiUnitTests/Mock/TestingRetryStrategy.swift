//
//  TestingRetryStrategy.swift
//  QaltiUnitTests
//
//  Created by Pavel Akhrameev on 06.03.26.
//

import Foundation
@testable import Qalti

/// Test-target only: a near-zero-delay strategy. Kept out of the app target so
/// production binaries cannot accidentally select it.
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
