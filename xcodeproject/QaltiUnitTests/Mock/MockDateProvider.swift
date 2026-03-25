//
//  MockDateProvider.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import Foundation
@testable import Qalti

final class MockDateProvider: DateProvider {

    private var currentDate: Date
    private let lock = NSLock()

    /// Optional: If set > 0, every call to now() moves time forward automatically.
    /// Useful for preserving order in logs without manual advancement.
    var autoAdvanceStep: TimeInterval = 0

    init(date: Date = Date(timeIntervalSince1970: 1609459200)) { // 2021-01-01 00:00:00 UTC
        self.currentDate = date
    }

    // MARK: - DateProvider Protocol

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }

        let returnedDate = currentDate

        if autoAdvanceStep > 0 {
            currentDate.addTimeInterval(autoAdvanceStep)
        }

        return returnedDate
    }

    // MARK: - Test Controls

    /// Manually moves the clock forward by X seconds
    func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        currentDate.addTimeInterval(seconds)
    }

    /// Reset or jump to a specific date
    func set(date: Date) {
        lock.lock()
        defer { lock.unlock() }
        currentDate = date
    }
}
