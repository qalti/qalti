//
//  JSONDecoder+Extensions.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 13.11.25.
//

import Foundation

extension JSONDecoder {
    /// Creates a configured JSONDecoder for parsing Qalti's test reports.
    /// It handles multiple date formats:
    /// - ISO 8601 without fractional seconds (e.g., "2025-11-13T10:00:01Z")
    /// - Unix timestamp as a Double (e.g., 1673629201.123)
    static func withPreciseDateDecoding() -> JSONDecoder {
        let decoder = JSONDecoder()

        decoder.dateDecodingStrategy = .custom { decoder -> Date in
            let container = try decoder.singleValueContainer()

            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }

            let dateString = try container.decode(String.self)

            // --- Formatter 1: High Precision ---
            let formatterWithFractionalSeconds = DateFormatter()
            formatterWithFractionalSeconds.locale = Locale(identifier: "en_US_POSIX")
            formatterWithFractionalSeconds.timeZone = TimeZone(secondsFromGMT: 0)
            formatterWithFractionalSeconds.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
            if let date = formatterWithFractionalSeconds.date(from: dateString) {
                return date
            }

            // --- Formatter 2: Low Precision ---
            let formatterWithoutFractionalSeconds = DateFormatter()
            formatterWithoutFractionalSeconds.locale = Locale(identifier: "en_US_POSIX")
            formatterWithoutFractionalSeconds.timeZone = TimeZone(secondsFromGMT: 0)
            formatterWithoutFractionalSeconds.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            if let date = formatterWithoutFractionalSeconds.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format '\(dateString)'. Expected ISO 8601 with/without fractional seconds (e.g., '2025-11-13T10:00:01.123Z' or '2025-11-13T10:00:01Z') or Unix timestamp.")
        }

        return decoder
    }
}
