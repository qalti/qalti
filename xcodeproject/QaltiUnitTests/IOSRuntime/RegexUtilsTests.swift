//
//  RegexUtilsTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import XCTest
@testable import Qalti

final class RegexUtilsTests: XCTestCase {

    // MARK: - Tests for matchRegex (Single Match)

    func testMatchRegex_FindsTunnelIP() {
        let devictlOutput = "    • tunnelIPAddress: fd10:bf50:3ba2::1"
        let pattern = "tunnelIPAddress:\\s*([a-fA-F0-9:.]+)"

        let result = RegexUtils.matchRegex(pattern: pattern, in: devictlOutput)

        XCTAssertEqual(result, "fd10:bf50:3ba2::1")
    }

    func testMatchRegex_ReturnsNilWhenNoMatch() {
        let text = "No matching content here."
        let pattern = "Value: (\\d+)"

        XCTAssertNil(RegexUtils.matchRegex(pattern: pattern, in: text))
    }

    func testMatchRegex_ReturnsNilForInvalidPattern() {
        let text = "Some text."
        // An invalid pattern with an unclosed parenthesis
        let invalidPattern = "Value: (\\d+"

        XCTAssertNil(RegexUtils.matchRegex(pattern: invalidPattern, in: text))
    }

    func testMatchRegex_HandlesPatternWithoutCaptureGroup() {
        // The function is designed to extract capture groups. If none exist, it should return nil.
        let text = "Value: 123"
        let pattern = "Value: \\d+" // No parentheses

        XCTAssertNil(RegexUtils.matchRegex(pattern: pattern, in: text))
    }

    // MARK: - Tests for matchesForRegex (Multiple Matches)

    func testMatchesForRegex_FindsAllNumbers() {
        let text = "Item 1, Item 2, Item 99"
        let pattern = "Item (\\d+)"

        let results = RegexUtils.matchesForRegex(pattern: pattern, in: text)

        XCTAssertEqual(results, ["1", "2", "99"])
    }

    func testMatchesForRegex_ReturnsEmptyArrayForNoMatches() {
        let text = "No numbers here."
        let pattern = "Item (\\d+)"

        let results = RegexUtils.matchesForRegex(pattern: pattern, in: text)

        XCTAssertTrue(results.isEmpty)
    }

    func testMatchesForRegex_ReturnsEmptyArrayForInvalidPattern() {
        let text = "Item 1, Item 2"
        let invalidPattern = "Item (\\d+"

        let results = RegexUtils.matchesForRegex(pattern: invalidPattern, in: text)

        XCTAssertTrue(results.isEmpty)
    }

    func testMatchesForRegex_SkipsMatchesWithoutCaptureGroups() {
        // If a match is found but it has no capture group, it should be ignored.
        // let text = "Match A, NoGroup, Match B"
        // This pattern can match "Match A" and "Match B", but only "NoGroup" has no group.
        // A better test pattern is needed for this specific behavior.
        // Let's test a pattern where one part has a group and another doesn't.
        let complexPattern = "Value: (\\d+)|NoGroup"
        let complexText = "Value: 123, NoGroup, Value: 456"

        let results = RegexUtils.matchesForRegex(pattern: complexPattern, in: complexText)

        // It finds three matches, but only two have content in capture group 1.
        XCTAssertEqual(results, ["123", "456"])
    }
}
