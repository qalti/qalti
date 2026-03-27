//
//  DateFormatters.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 09.03.26.
//

import Foundation

// DateFormatter is not thread-safe. All shared instances are kept private;
// access them only through the thread-safe static functions below.
extension DateFormatter {

    private static let _httpDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let _logFile: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let formatterLock = NSLock()

    /// Formats `date` as an HTTP date string (e.g. `"Mon, 09 Mar 2026 18:30:45 GMT"`). Thread-safe.
    static func formatHTTPDate(_ date: Date) -> String {
        formatterLock.withLock { _httpDate.string(from: date) }
    }

    /// Parses an HTTP-format date string (Retry-After / Date header). Thread-safe.
    static func parseHTTPDate(_ string: String) -> Date? {
        formatterLock.withLock { _httpDate.date(from: string) }
    }

    /// Formats `date` as a filesystem-safe log filename component (e.g. `"2026-03-09_18-30-45"`). Thread-safe.
    static func formatLogFileName(_ date: Date) -> String {
        formatterLock.withLock { _logFile.string(from: date) }
    }
}
