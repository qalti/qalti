//
//  MockErrorCapturer.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import Foundation
import XCTest
@testable import Qalti

class MockErrorCapturer: ErrorCapturing {
    var capturedError: Error?
    var captureCount = 0
    var expectation: XCTestExpectation?

    func capture(error: Error) {
        capturedError = error
        captureCount += 1
        expectation?.fulfill()
    }
}
