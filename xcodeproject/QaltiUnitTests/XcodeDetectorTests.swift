//
//  XcodeDetectorTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 19.11.25.
//

import XCTest
@testable import Qalti

@MainActor
final class XcodeDetectorTests: XCTestCase {

    func testDetectorDoesNotHangDuringTests() {
        // Given
        let mockErrorCapturer = MockErrorCapturer()
        let detector = XcodeDetector(errorCapturer: mockErrorCapturer)

        // When
        // We call the method that usually triggers the shell command
        let locations = detector.checkXcodePresence()

        // Then
        // 1. It should NOT hang (execution should reach here instantly)
        // 2. It should NOT find xcode-select path (because we short-circuited it)

        let hasCustomLocation = locations.contains { location in
            if case .custom = location { return true }
            return false
        }

        XCTAssertFalse(hasCustomLocation, "Should NOT detect custom xcode-select path when running Unit Tests. The hotfix should short-circuit this check.")

        // 3. SANITY CHECK:
        // Ensure we still got a valid list (even if it's just [.notFound] or [/Applications/...])
        XCTAssertFalse(locations.isEmpty, "Should return at least .notFound or other locations")
    }
}
