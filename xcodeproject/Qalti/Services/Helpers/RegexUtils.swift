//
//  RegexUtils.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import Foundation
import Logging

enum RegexUtils {
    /// Finds the first match for a given regex pattern and returns the content
    /// of the **first capturing group**.
    ///
    /// A capturing group is the part of the pattern enclosed in parentheses `()`.
    ///
    /// - Example: `matchRegex(pattern: "Name: (\\w+)", in: "Name: John")` returns `"John"`.
    ///
    /// - Parameters:
    ///   - pattern: The regular expression pattern. Must contain at least one capturing group.
    ///   - text: The string to search within.
    /// - Returns: The string content of the first capturing group, or `nil` if no match is found.
    static func matchRegex(pattern: String, in text: String) -> String? {
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
           match.numberOfRanges > 1 {
            return (text as NSString).substring(with: match.range(at: 1))
        }
        return nil
    }

    /// Finds all matches for a given regex pattern and returns an array of the contents
    /// of the **first capturing group** from each match.
    ///
    /// - Parameters:
    ///   - pattern: The regular expression pattern with at least one capturing group.
    ///   - text: The string to search within.
    /// - Returns: An array of strings, one for each match's first capturing group.
    static func matchesForRegex(pattern: String, in text: String) -> [String] {
        var results = [String]()
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)
            for match in matches where match.numberOfRanges > 1 {
                if let range = Range(match.range(at: 1), in: text) {
                    results.append(String(text[range]))
                }
            }
        }
        return results
    }
}
