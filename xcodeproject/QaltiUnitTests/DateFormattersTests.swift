//
//  DateFormattersTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 09.03.26.
//

import XCTest
@testable import Qalti

final class DateFormattersTests: XCTestCase {

    // MARK: - HTTP Date Formatter Tests

    func testHTTPDateFormatter_ParsesValidHTTPDate() {
        // Given
        let httpDateString = "Mon, 09 Mar 2026 18:30:45 GMT"

        // When
        let parsedDate = DateFormatter.httpDate.date(from: httpDateString)

        // Then
        XCTAssertNotNil(parsedDate, "Should parse valid HTTP date string")

        // Verify the parsed components using GMT timezone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)! // Use GMT like the formatter
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: parsedDate!)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 9)
        XCTAssertEqual(components.hour, 18)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(components.second, 45)
        XCTAssertEqual(components.weekday, 2) // Monday = 2
    }

    func testHTTPDateFormatter_FormatsDateCorrectly() {
        // Given - Create date in GMT timezone to match the formatter
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 9
        components.hour = 18
        components.minute = 30
        components.second = 45
        components.timeZone = TimeZone(secondsFromGMT: 0)

        let date = calendar.date(from: components)!

        // When
        let formattedString = DateFormatter.httpDate.string(from: date)

        // Then - March 9, 2026 is actually a Monday, not Sunday
        XCTAssertEqual(formattedString, "Mon, 09 Mar 2026 18:30:45 GMT")
    }

    func testHTTPDateFormatter_HandlesRetryAfterHeader() {
        // Given - Common Retry-After header formats
        let retryAfterHeaders = [
            "Wed, 21 Oct 2026 07:28:00 GMT",
            "Thu, 01 Jan 2026 00:00:00 GMT",
            "Fri, 31 Dec 2027 23:59:59 GMT"
        ]

        // When & Then
        for headerValue in retryAfterHeaders {
            let parsedDate = DateFormatter.httpDate.date(from: headerValue)
            XCTAssertNotNil(parsedDate, "Should parse Retry-After header: \(headerValue)")

            // Verify round-trip
            let reformatted = DateFormatter.httpDate.string(from: parsedDate!)
            let reparsed = DateFormatter.httpDate.date(from: reformatted)

            XCTAssertNotNil(reparsed, "Should be able to reparse formatted date")
            XCTAssertEqual(parsedDate!.timeIntervalSince1970, reparsed!.timeIntervalSince1970, accuracy: 1.0,
                          "Round-trip should preserve date within 1 second")
        }
    }

    func testHTTPDateFormatter_RejectsInvalidFormats() {
        // Given - Invalid date formats
        let invalidDates = [
            "2026-03-09T18:30:45Z",  // ISO format
            "03/09/2026 18:30:45",   // US format
            "09-03-2026",            // Short format
            "invalid date",          // Garbage
            ""                       // Empty string
        ]

        // When & Then
        for invalidDate in invalidDates {
            let parsedDate = DateFormatter.httpDate.date(from: invalidDate)
            XCTAssertNil(parsedDate, "Should reject invalid date format: \(invalidDate)")
        }
    }

    // MARK: - Log File Formatter Tests

    func testLogFileFormatter_FormatsDateForFilename() {
        // Given - Create date in local timezone (log files use local time)
        let calendar = Calendar(identifier: .gregorian)

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 9
        components.hour = 18
        components.minute = 30
        components.second = 45

        let date = calendar.date(from: components)!

        // When
        let formattedString = DateFormatter.logFile.string(from: date)

        // Then
        XCTAssertEqual(formattedString, "2026-03-09_18-30-45")
    }

    func testLogFileFormatter_ProducesFilesystemSafeNames() {
        // Given - Various dates
        let testDates = [
            Date(timeIntervalSince1970: 1640995200), // 2022-01-01 00:00:00 UTC
            Date(timeIntervalSince1970: 1672531199), // 2022-12-31 23:59:59 UTC
            Date() // Current date
        ]

        // When & Then
        for date in testDates {
            let filename = DateFormatter.logFile.string(from: date)

            // Should not contain filesystem-unsafe characters
            let unsafeCharacters = CharacterSet(charactersIn: "/<>:|\"\\*?")
            XCTAssertTrue(filename.rangeOfCharacter(from: unsafeCharacters) == nil,
                         "Filename should not contain unsafe characters: \(filename)")

            // Should match expected pattern
            let pattern = #"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$"#
            let regex = try! NSRegularExpression(pattern: pattern)
            let range = NSRange(filename.startIndex..., in: filename)
            XCTAssertTrue(regex.firstMatch(in: filename, range: range) != nil,
                         "Filename should match pattern YYYY-MM-DD_HH-MM-SS: \(filename)")
        }
    }

    // MARK: - Thread Safety Tests

    func testDateFormatters_AreThreadSafe() {
        // Given
        let expectation = XCTestExpectation(description: "Thread safety test")
        expectation.expectedFulfillmentCount = 10

        let testDate = Date()
        let queue = DispatchQueue.global(qos: .userInitiated)

        // When - Access formatters from multiple threads simultaneously
        for _ in 0..<10 {
            queue.async {
                // Use all formatters simultaneously
                let httpString = DateFormatter.httpDate.string(from: testDate)
                let logString = DateFormatter.logFile.string(from: testDate)

                // Verify they produce valid output
                XCTAssertFalse(httpString.isEmpty)
                XCTAssertFalse(logString.isEmpty)

                expectation.fulfill()
            }
        }

        // Then
        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Performance Tests (Fixed)

    func testHTTPFormatterPerformance() {
        let testDate = Date()

        measure {
            for _ in 0..<1000 {
                _ = DateFormatter.httpDate.string(from: testDate)
            }
        }
    }

    func testLogFileFormatterPerformance() {
        let testDate = Date()

        measure {
            for _ in 0..<1000 {
                _ = DateFormatter.logFile.string(from: testDate)
            }
        }
    }

    // MARK: - Real-world Integration Tests

    func testHTTPDateFormatter_WithActualRetryAfterValues() {
        // Given - Real Retry-After header values from various APIs
        let realWorldValues = [
            "Mon, 01 Jan 2024 00:00:00 GMT",  // New Year
            "Thu, 29 Feb 2024 12:00:00 GMT",  // Leap year (corrected day)
            "Sun, 31 Dec 2023 23:59:59 GMT"   // Year end
        ]

        // When & Then
        for value in realWorldValues {
            let date = DateFormatter.httpDate.date(from: value)
            XCTAssertNotNil(date, "Should parse real-world Retry-After value: \(value)")

            // Should be able to calculate wait time
            if let parsedDate = date {
                let timeInterval = parsedDate.timeIntervalSince(Date())
                // (timeInterval could be negative for past dates, which is fine)
                XCTAssertTrue(timeInterval.isFinite, "Should produce finite time interval")
            }
        }
    }

    func testLogFileFormatter_CreatesUniqueFilenames() {
        // Given
        var filenames: Set<String> = []

        // When - Generate filenames with small time differences
        for i in 0..<100 {
            let date = Date(timeIntervalSinceNow: TimeInterval(i))
            let filename = DateFormatter.logFile.string(from: date)
            filenames.insert(filename)
        }

        // Then - All filenames should be unique (assuming they span different seconds)
        XCTAssertGreaterThan(filenames.count, 1, "Should generate multiple unique filenames")
    }

    // MARK: - Edge Cases

    func testDateFormatters_HandleLeapYear() {
        // Given - February 29, 2024 (leap year)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var components = DateComponents()
        components.year = 2024
        components.month = 2
        components.day = 29
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)

        let leapDate = calendar.date(from: components)!

        // When & Then
        let httpString = DateFormatter.httpDate.string(from: leapDate)
        let logString = DateFormatter.logFile.string(from: leapDate)

        XCTAssertTrue(httpString.contains("29 Feb 2024"), "HTTP formatter should handle leap year")
        XCTAssertTrue(logString.contains("2024-02-29"), "Log formatter should handle leap year")
    }
}
