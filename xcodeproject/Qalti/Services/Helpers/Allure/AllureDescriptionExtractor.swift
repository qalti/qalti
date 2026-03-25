//
//  AllureDescriptionExtractor.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import Foundation

/// A stateless helper to parse LLM assistant messages and extract human-readable step descriptions.
enum AllureDescriptionExtractor {

    private static let unwantedTrailingPunctuation = CharacterSet(charactersIn: ".,!?;")

    static func extractDescription(from message: String?) -> String? {
        guard let text = message, !text.isEmpty else { return nil }
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            if line.contains("**Tip:**") {
                return cleanLine(line, separator: "**Tip:**")
            }
        }

        for line in lines {
            if line.contains("**Analysis:**") {
                let fullAnalysis = cleanLine(line, separator: "**Analysis:**")
                return fullAnalysis?.components(separatedBy: ".").first
            }
        }

        for line in lines {
            if line.contains("**Original Step:**") {
                return cleanLine(line, separator: "**Original Step:**")
            }
        }
        return nil
    }

    /// Cleans a description string specifically for use as a concise Allure step name.
    /// It removes trailing whitespaces and common sentence-ending punctuation,
    /// but preserves structural punctuation like closing quotes or parentheses.
    static func cleanForStepName(_ description: String?) -> String? {
        guard let desc = description else { return nil }

        let charactersToTrim = Self.unwantedTrailingPunctuation.union(.whitespacesAndNewlines)
        return desc.trimmingCharacters(in: charactersToTrim)
    }

    private static func cleanLine(_ line: String, separator: String) -> String? {
        let parts = line.components(separatedBy: separator)
        if let lastPart = parts.last {
            var clean = lastPart.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.hasPrefix("-") {
                clean = String(clean.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return clean
        }
        return nil
    }
}
