//
//  ContentParser.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 18.12.25.
//

import Foundation
import Logging
import SwiftUI

// MARK: - Test Result Types

enum TestResultStatus: String, Codable, CaseIterable {
    case pass = "pass"
    case passWithComments = "pass with comments"
    case failed = "failed"

    var displayText: String {
        switch self {
        case .pass:
            return "PASS"
        case .passWithComments:
            return "PASS WITH COMMENTS"
        case .failed:
            return "FAILED"
        }
    }

    var color: Color {
        switch self {
        case .pass:
            return .green
        case .passWithComments:
            return .orange
        case .failed:
            return .red
        }
    }

    var icon: String {
        switch self {
        case .pass:
            return "checkmark.circle.fill"
        case .passWithComments:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
}

struct TestResult: Codable {
    let testResult: TestResultStatus
    let comments: String
    let testObjectiveAchieved: Bool
    let stepsFollowedExactly: Bool
    let adaptationsMade: [String]
    let finalStateDescription: String

    enum CodingKeys: String, CodingKey {
        case testResult = "test_result"
        case comments
        case testObjectiveAchieved = "test_objective_achieved"
        case stepsFollowedExactly = "steps_followed_exactly"
        case adaptationsMade = "adaptations_made"
        case finalStateDescription = "final_state_description"
    }
}

struct ParsedContent {
    let mainContent: String
    let testResult: TestResult?
}

// MARK: - Content Parser

class ContentParser: Loggable {

    private let errorCapturer: ErrorCapturing

    init(errorCapturer: ErrorCapturing) {
        self.errorCapturer = errorCapturer
    }

    func parseContent(_ text: String) -> ParsedContent {
        var mainContent = text
        var testResult: TestResult? = nil

        // Find raw JSON objects with TestResult structure
        let rawJsonPattern = #"\{\s*"test_result"\s*:\s*"[^"]*"[\s\S]*?\}"#

        do {
            let regex = try NSRegularExpression(pattern: rawJsonPattern, options: [])
            let matches = regex.matches(in: mainContent, options: [], range: NSRange(location: 0, length: mainContent.count))

            // Take only the first match (since we expect only one test result per message)
            if let firstMatch = matches.first {
                if let jsonRange = Range(firstMatch.range, in: mainContent) {
                    let jsonString = String(mainContent[jsonRange])

                    // Try to parse as TestResult
                    if let parsedTestResult = Self.parseTestResult(from: jsonString, errorCapturer: errorCapturer) {
                        testResult = parsedTestResult

                        mainContent.removeSubrange(jsonRange)
                    }
                }
            }
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Failed to parse raw JSON regex: \(error)")
        }

        let emptyCodeBlockPattern = #"```(json)?\s*\n\s*\n```"#
        do {
            let regex = try NSRegularExpression(pattern: emptyCodeBlockPattern, options: [])
            let matches = regex.matches(in: mainContent, options: [], range: NSRange(location: 0, length: mainContent.count))

            for match in matches.reversed() {
                if let range = Range(match.range, in: mainContent) {
                    mainContent.removeSubrange(range)
                }
            }
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Failed to clean up empty code blocks: \(error)")
        }

        mainContent = mainContent.trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedContent(mainContent: mainContent, testResult: testResult)
    }

    // MARK: - Parsed Agent Comment

    /// Parse structured assistant comment produced by the agent as per <comment_format>.
    /// Returns nil if required markers are completely absent.
    static func parseAgentComment(_ text: String) -> ParsedAgentComment? {
        let source = text
        let full = source as NSString

        // Detect "Line X/Y"
        var currentLine: Int? = nil
        var totalLines: Int? = nil
        do {
            let linePattern = #"\bline\s*(\d+)\s*/\s*(\d+)\s*:?"#
            let regex = try NSRegularExpression(pattern: linePattern, options: [.caseInsensitive])
            if let match = regex.firstMatch(in: source, options: [], range: NSRange(location: 0, length: full.length)),
               match.numberOfRanges >= 3
            {
                if let r1 = Range(match.range(at: 1), in: source),
                   let r2 = Range(match.range(at: 2), in: source) {
                    currentLine = Int(source[r1])
                    totalLines = Int(source[r2])
                }
            }
        } catch {
            // ignore
        }

        // Helper to find a label range ignoring bold and optional colon
        func labelRange(_ label: String) -> Range<String.Index>? {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let pattern = #"(?is)\*{0,2}\s*"# + escaped + #"\s*:?\s*\*{0,2}"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: source, options: [], range: NSRange(location: 0, length: full.length))
            {
                return Range(match.range, in: source)
            }
            return nil
        }

        let labels = ["Original Step", "Analysis", "Verification", "Tip"]
        var headerLocations: [(name: String, start: String.Index, end: String.Index)] = []
        for label in labels {
            if let range = labelRange(label) {
                headerLocations.append((label, range.lowerBound, range.upperBound))
            }
        }
        guard headerLocations.isEmpty == false else {
            // No recognizable headers → not a structured comment
            return nil
        }
        headerLocations.sort(by: { $0.start < $1.start })

        // Build a map name -> content range
        var contents: [String: String] = [:]
        for (idx, header) in headerLocations.enumerated() {
            let start = header.end
            let limit = (idx + 1 < headerLocations.count) ? headerLocations[idx + 1].start : source.endIndex
            if start <= limit {
                let textSlice = source[start..<limit].trimmingCharacters(in: .whitespacesAndNewlines)
                contents[header.name.lowercased()] = textSlice
            }
        }

        let parsed = ParsedAgentComment(
            currentLine: currentLine,
            totalLines: totalLines,
            originalStep: contents["original step"],
            analysis: contents["analysis"],
            tip: contents["tip"],
            verification: contents["verification"]
        )

        // Return nil only if everything is empty and no line numbers detected
        if currentLine == nil,
           totalLines == nil,
           (parsed.originalStep?.isEmpty ?? true),
           (parsed.analysis?.isEmpty ?? true),
           (parsed.tip?.isEmpty ?? true),
           (parsed.verification?.isEmpty ?? true) {
            return nil
        }
        return parsed
    }

    /// Parse multiple structured assistant comments within a single message.
    /// Detects repeated blocks starting with "Line X/Y" and parses each block using `parseAgentComment`.
    /// Falls back to a single parse if no multiple line headers are present.
    static func parseAgentComments(_ text: String) -> [ParsedAgentComment]? {
        let source = text
        let ns = source as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        // Find all occurrences of "Line X/Y"
        let lineHeaderPattern = #"\bline\s*\d+\s*/\s*\d+\s*:?"#
        guard let regex = try? NSRegularExpression(pattern: lineHeaderPattern, options: [.caseInsensitive]) else {
            // Fallback to single parser
            if let single = parseAgentComment(text) { return [single] }
            return nil
        }
        let matches = regex.matches(in: source, options: [], range: fullRange)

        // If no or only one header found, fallback to single parsing
        if matches.count <= 1 {
            if let single = parseAgentComment(text) { return [single] }
            return nil
        }

        // Split the text into segments starting at each "Line X/Y" header
        var segments: [String] = []
        for (index, match) in matches.enumerated() {
            let start = match.range.location
            let end: Int = {
                if index + 1 < matches.count {
                    return matches[index + 1].range.location
                } else {
                    return ns.length
                }
            }()
            let range = NSRange(location: start, length: end - start)
            if let swiftRange = Range(range, in: source) {
                segments.append(String(source[swiftRange]))
            }
        }

        // Parse each segment with the single-block parser
        var results: [ParsedAgentComment] = []
        for segment in segments {
            if let parsed = parseAgentComment(segment) {
                results.append(parsed)
            }
        }

        return results.isEmpty ? nil : results
    }

    private static func parseTestResult(from jsonString: String, errorCapturer: ErrorCapturing) -> TestResult? {
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }

        do {
            let testResult = try JSONDecoder().decode(TestResult.self, from: data)
            return testResult
        } catch {
            errorCapturer.capture(error: error)
            // Can't use instance logger in static method
            // logger.error("Failed to decode TestResult JSON: \(error)")
            return nil
        }
    }
}
