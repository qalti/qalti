//
//  IOSAgentTests.swift
//  QaltiUnitTests
//
//  Created by Copilot on 2026-03-31.
//

import XCTest
@testable import Qalti

final class IOSAgentTests: XCTestCase {
    func testRateLimitInfoHeaderParsing() {
        // Simulate HTTPURLResponse with mixed-case headers and different value types
        let headers: [AnyHashable: Any] = [
            "Retry-After": "42",
            "X-RateLimit-Limit": "100",
            "X-RateLimit-Remaining": "55",
            "X-RateLimit-Reset": String(Int(Date().addingTimeInterval(60).timeIntervalSince1970)),
        ]
        let url = URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: headers as? [String: String])!
        let info = IOSAgent.RateLimitInfo(from: response)
        XCTAssertEqual(info.retryAfter, 42, accuracy: 0.1)
        XCTAssertEqual(info.limit, 100)
        XCTAssertEqual(info.remaining, 55)
        XCTAssertNotNil(info.resetTime)
    }

    func testRateLimitInfoHeaderParsing_MixedCase() {
        // Mixed-case headers
        let headers: [AnyHashable: Any] = [
            "ReTrY-AfTeR": "99",
            "X-RaTeLiMiT-LiMiT": "77",
            "X-RaTeLiMiT-ReMaInInG": "33"
        ]
        let url = URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: headers as? [String: String])!
        let info = IOSAgent.RateLimitInfo(from: response)
        XCTAssertEqual(info.retryAfter, 99, accuracy: 0.1)
        XCTAssertEqual(info.limit, 77)
        XCTAssertEqual(info.remaining, 33)
    }
}
