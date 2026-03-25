//
//  AllureErrorExtractor.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import Foundation

/// A stateless helper to extract human-readable error messages from tool responses.
enum AllureErrorExtractor {

    static let unknownErrorMessage = "Unknown error (Check raw response)"

    /// Recursively tries to find a human-readable string in the error dictionary
    static func extractCleanError(from dict: [String: Any]) -> String {

        // 1. Check "error" key
        if let error = dict["error"] as? String, !error.isEmpty {
            // Check if error is nested JSON string (common in Python tools or wrapped errors)
            if error.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
               let data = error.data(using: .utf8),
               let nested = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                // Recurse
                let nestedResult = extractCleanError(from: nested)

                // Only use nested result if it found something specific.
                // If it returned "Unknown...", fall back to checking THIS level's keys.
                if nestedResult != unknownErrorMessage {
                    return nestedResult
                }
            } else {
                // It's a regular string, return it unless it's empty JSON brackets
                if error != "{}" && error != "{\n}" { return error }
            }
        }

        // 2. Check other common keys
        if let msg = dict["message"] as? String, !msg.isEmpty { return msg }
        if let reason = dict["failure_reason"] as? String, !reason.isEmpty { return reason }

        // 3. Check for specific Qalti context keys
        if let element = dict["element_name"] as? String {
            return "Interaction failed for element: '\(element)'"
        }

        return unknownErrorMessage
    }
}
