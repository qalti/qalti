//
//  MarkdownStreamer.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import Foundation

enum MarkdownStreamer {

    static func splitContent(from text: String, isStreaming: Bool) -> (stable: String, pending: String) {
        var processed = stripResultBlock(text)

        processed = formatLinePrefix(processed)

        if !isStreaming { return (processed, "") }

        if processed.count < 5 { return ("", processed) }
        if processed.hasSuffix("\n") { return (processed, "") }

        if let lastIndex = processed.lastIndex(of: "\n") {
            let splitIndex = processed.index(after: lastIndex)
            return (String(processed[..<splitIndex]), String(processed[splitIndex...]))
        }

        return ("", processed)
    }

    /// Detects "Line 1/5: **Action" on a single line and splits it.
    static func formatLinePrefix(_ text: String) -> String {
        let pattern = #"(Line \d+(?:/\d+)?:)\s+(?:\*\*?|\s)*(Analysis|Verification|Tip|Original Step)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "$1\n\n**$2"
        )
    }

    /// Cleans the pending line to look like plain text before it "snaps" to Markdown.
    /// This removes the "ugly" phase of seeing **asterisks** or #hashes typing out.
    static func cleanPendingText(_ text: String) -> String {
        var clean = text
        let prefixes = ["#", "-", ">"]
        for char in prefixes {
            let trimmed = clean.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(char), let range = clean.range(of: char) {
                clean.remove(at: range.lowerBound)
            }
        }
        clean = clean.replacingOccurrences(of: "**", with: "")
        return clean
    }

    /// Removes the JSON Result block from the stream so it doesn't render as a code block.
    static func stripResultBlock(_ text: String) -> String {
        // result block is always at the end.
        if let range = text.range(of: "```json", options: .backwards) {
            let suffix = text[range.upperBound...]
            let trimmedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)

            if suffix.contains("test_result") ||
                suffix.contains("\"test_result\"") ||
                trimmedSuffix.hasPrefix("{") {

                return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return text
    }
}
