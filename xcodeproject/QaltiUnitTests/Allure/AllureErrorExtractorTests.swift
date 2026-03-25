//
//  AllureErrorExtractorTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import XCTest
@testable import Qalti

final class AllureErrorExtractorTests: XCTestCase {

    // MARK: - 1. Basic Keys

    func testExtractsSimpleStringError() {
        let dict: [String: Any] = ["error": "Simple failure"]
        XCTAssertEqual(AllureErrorExtractor.extractCleanError(from: dict), "Simple failure")
    }

    func testExtractsMessageKey() {
        let dict: [String: Any] = ["message": "Something went wrong"]
        XCTAssertEqual(AllureErrorExtractor.extractCleanError(from: dict), "Something went wrong")
    }

    func testExtractsFailureReasonKey() {
        let dict: [String: Any] = ["failure_reason": "Timeout"]
        XCTAssertEqual(AllureErrorExtractor.extractCleanError(from: dict), "Timeout")
    }

    func testExtractsElementName() {
        // This is the fallback for specific interaction failures
        let dict: [String: Any] = ["element_name": "Login Button"]
        XCTAssertEqual(AllureErrorExtractor.extractCleanError(from: dict), "Interaction failed for element: 'Login Button'")
    }

    // MARK: - 2. Recursion & JSON Parsing

    func testParsesNestedJsonString() {
        // Python tools often return error as a stringified JSON
        let nestedJson = "{\"message\": \"Inner error\"}"
        let dict: [String: Any] = ["error": nestedJson]

        XCTAssertEqual(AllureErrorExtractor.extractCleanError(from: dict), "Inner error")
    }

    func testParsesDeeplyNestedJson() {
        // error -> stringified json -> stringified json -> message
        let deepJson = "{\"error\": \"{\\\"message\\\": \\\"Deepest error\\\"}\"}"
        let dict: [String: Any] = ["error": deepJson]

        XCTAssertEqual(AllureErrorExtractor.extractCleanError(from: dict), "Deepest error")
    }

    // MARK: - 3. Empty/Ignored Values (The "Messy Log" Logic)

    func testIgnoresEmptyJsonBrackets() {
        // If error is just "{}", it should skip it and look for other keys
        let dict: [String: Any] = [
            "error": "{}",
            "message": "Real error"
        ]
        XCTAssertEqual(AllureErrorExtractor.extractCleanError(from: dict), "Real error")
    }

    func testIgnoresEmptyJsonBracketsWithNewline() {
        // Common artifact in some logs
        let dict: [String: Any] = [
            "error": "{\n}",
            "message": "Real error"
        ]
        XCTAssertEqual(AllureErrorExtractor.extractCleanError(from: dict), "Real error")
    }

    func testHandlesNestedEmptyJsonFallback() {
        // The specific case you encountered:
        // "error": "{\"error\":\"\"}" -> Recurses -> Finds empty/unknown -> Returns to parent -> checks element_name
        let dict: [String: Any] = [
            "error": "{\"error\": \"\"}",
            "element_name": "Photos Icon"
        ]

        XCTAssertEqual(
            AllureErrorExtractor.extractCleanError(from: dict),
            "Interaction failed for element: 'Photos Icon'"
        )
    }

    // MARK: - 4. Precedence & Edge Cases

    func testPrecedenceOrder() {
        // Ensure priorities are respected: error > message > failure_reason > element_name

        let allKeys: [String: Any] = [
            "error": "High Priority",
            "message": "Medium Priority",
            "failure_reason": "Low Priority",
            "element_name": "Fallback"
        ]
        XCTAssertEqual(AllureErrorExtractor.extractCleanError(from: allKeys), "High Priority")

        let noError: [String: Any] = [
            "message": "Medium Priority",
            "failure_reason": "Low Priority"
        ]
        XCTAssertEqual(AllureErrorExtractor.extractCleanError(from: noError), "Medium Priority")
    }

    func testMalformedJsonIsTreatedAsString() {
        // If it starts with { but isn't valid JSON, it should be returned as raw string
        let dict: [String: Any] = ["error": "{ bad json"]
        XCTAssertEqual(AllureErrorExtractor.extractCleanError(from: dict), "{ bad json")
    }

    func testTotalFallback() {
        // Nothing useful found
        let dict: [String: Any] = ["success": false]
        XCTAssertEqual(
            AllureErrorExtractor.extractCleanError(from: dict),
            AllureErrorExtractor.unknownErrorMessage
        )
    }
}
