//
//  JSONEncoder+Extensions.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 14.11.25.
//

import Foundation

extension JSONEncoder {
    /// Creates a configured JSONEncoder for saving Qalti's test reports.
    /// It formats dates as high-precision ISO 8601 strings (including fractional seconds).
    static func withPreciseDateEncoding() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"

        encoder.dateEncodingStrategy = .formatted(formatter)

        return encoder
    }
}
