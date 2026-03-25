//
//  RunHistoryTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 19.11.25.
//

import XCTest
@testable import Qalti

final class RunHistoryTests: XCTestCase {
    private var runHistory: RunHistory!

    override func setUp() {
        super.setUp()
        // Clear state before each test
        runHistory = RunHistory()
        runHistory.clearHistory()
        runHistory.setRunInProgress(false)
    }

    // MARK: - Run State Observer Tests

    func testRunStateObserverNotifiesChange() {
        let expectation = XCTestExpectation(description: "Observer should be notified of run state change")

        let token = runHistory.registerRunStateObserver { isRunning in
            if isRunning {
                expectation.fulfill()
            }
        }

        // Trigger change
        runHistory.setRunInProgress(true)

        wait(for: [expectation], timeout: 1.0)
        runHistory.removeRunStateObserver(id: token)
    }

    func testRunStateObserverRemoval() {
        let expectation = XCTestExpectation(description: "Observer should NOT be notified after removal")
        expectation.isInverted = true // Fail if fulfilled

        // 1. Register
        let token = runHistory.registerRunStateObserver { _ in
            expectation.fulfill()
        }

        // 2. Remove immediately
        runHistory.removeRunStateObserver(id: token)

        // 3. Trigger change
        runHistory.setRunInProgress(true)

        wait(for: [expectation], timeout: 0.5)
    }

    // MARK: - Chat History Observer Tests

    func testHistoryObserverNotifiesAppend() {
        let expectation = XCTestExpectation(description: "History observer notified")

        let token = runHistory.registerObserver {
            expectation.fulfill()
        }

        runHistory.append(.user(.init(content: .string("Test message"))))

        wait(for: [expectation], timeout: 1.0)
        runHistory.removeObserver(id: token)
    }

    // MARK: - Thread Safety Tests

    func testObserverThreadSafety() {
        let expectation = XCTestExpectation(description: "Concurrent operations should not crash")
        expectation.expectedFulfillmentCount = 100 // Expect 100 updates

        let group = DispatchGroup()

        // Thread A: Rapidly registering and removing observers
        group.enter()
        DispatchQueue.global().async {
            for _ in 0..<1000 {
                let token = self.runHistory.registerRunStateObserver { _ in }
                self.runHistory.removeRunStateObserver(id: token)
            }
            group.leave()
        }

        // Thread B: Rapidly triggering updates
        group.enter()
        DispatchQueue.global().async {
            for i in 0..<100 {
                // Toggle state
                self.runHistory.setRunInProgress(i % 2 == 0)
            }
            group.leave()
        }

        // Thread C: Static observer that should survive the chaos
        let stableToken = runHistory.registerRunStateObserver { _ in
            expectation.fulfill()
        }

        // Wait for threads A and B to finish
        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success)

        runHistory.removeRunStateObserver(id: stableToken)
    }
}
