//
//  DateFormatters.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 09.03.26.
//

import Foundation

extension DateFormatter {
    /// HTTP date formatter for parsing Retry-After headers and similar HTTP date fields
    /// Format: "E, dd MMM yyyy HH:mm:ss zzz" (e.g., "Wed, 09 Mar 2026 18:30:45 GMT")
    static let httpDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// Log filename date formatter
    static let logFile: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
