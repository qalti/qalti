//
//  CodableExtensionsTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 14.11.25.
//

import XCTest
@testable import Qalti

final class CodableExtensionsTests: XCTestCase {

    struct DateContainer: Decodable {
        let date: Date
    }

    var decoder: JSONDecoder!
    var encoder: JSONEncoder!

    override func setUp() {
        super.setUp()
        decoder = JSONDecoder.withPreciseDateDecoding()
        encoder = JSONEncoder.withPreciseDateEncoding()
    }

    // MARK: - Date Decoding Tests

    func testDateDecoding_HandlesHighPrecisionString() throws {
        // Arrange
        let json = #"{"date": "2025-11-13T10:00:01.123Z"}"#.data(using: .utf8)!
        let expectedDate = Date(timeIntervalSince1970: 1763028001.123)

        // Act
        let result = try decoder.decode(DateContainer.self, from: json)

        // Assert
        XCTAssertEqual(result.date.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 0.0001)
    }

    func testDateDecoding_HandlesLowPrecisionString() throws {
        // Arrange
        let json = #"{"date": "2025-11-13T10:00:01Z"}"#.data(using: .utf8)!
        let expectedDate = Date(timeIntervalSince1970: 1763028001.0)

        // Act
        let result = try decoder.decode(DateContainer.self, from: json)

        // Assert
        XCTAssertEqual(result.date.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 0.0001)
    }

    func testDateDecoding_HandlesNumericTimestamp() throws {
        // Arrange
        let json = #"{"date": 1762986001.123}"#.data(using: .utf8)!
        let expectedDate = Date(timeIntervalSince1970: 1762986001.123)

        // Act
        let result = try decoder.decode(DateContainer.self, from: json)

        // Assert
        XCTAssertEqual(result.date.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 0.0001)
    }

    func testDateDecoding_ThrowsErrorForInvalidFormat() {
        // Arrange
        let json = #"{"date": "invalid-date-format"}"#.data(using: .utf8)!

        // Act & Assert
        XCTAssertThrowsError(try decoder.decode(DateContainer.self, from: json)) { error in
            guard let decodingError = error as? DecodingError else {
                XCTFail("Expected a DecodingError")
                return
            }
            if case .dataCorrupted(let context) = decodingError {
                XCTAssert(context.debugDescription.contains("Invalid date format"))
            } else {
                XCTFail("Expected a dataCorrupted error, but got \(decodingError)")
            }
        }
    }

    // MARK: - Date Encoding Test

    func testDateEncoding_WritesHighPrecisionString() throws {
        // Arrange
        let date = Date(timeIntervalSince1970: 1763028001.123)
        let container = ["date": date]

        // Act
        let data = try encoder.encode(container)
        let jsonString = String(data: data, encoding: .utf8)!

        let expectedSubstring = "\"date\":\"2025-11-13T10:00:01.123Z\""
        let jsonStringWithoutSpaces = jsonString.filter { !$0.isWhitespace }

        // Assert
        XCTAssertTrue(
            jsonStringWithoutSpaces.contains(expectedSubstring),
            "The encoded JSON should contain the high-precision date string, ignoring whitespace."
        )
    }
}
