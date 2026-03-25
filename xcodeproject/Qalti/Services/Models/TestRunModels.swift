//
//  TestRunModels.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 06.11.25.
//

import Foundation
import OpenAI

// MARK: - Unified Interface and Latest Version

typealias TestRunData = TestRunDataV2
typealias TestReportData = TestRunData

protocol TestRunDataProtocol {
    var version: Int { get }
    var runSucceeded: Bool { get }
    var runFailureReason: String? { get }
    var testResult: TestResult? { get }
    var timestamp: String { get }
    var test: String { get }
    var runHistory: [CodableChatMessage] { get }

    var isTestPassed: Bool { get }
    var displayStatusMessage: String { get }
}

extension TestRunDataProtocol {
    var isTestPassed: Bool {
        return testResult?.testResult == .pass
    }

    var displayStatusMessage: String {
        if !runSucceeded {
            return "Loaded test run (Run Failed: \(runFailureReason ?? "Unknown"))"
        } else if let result = testResult {
            return "Loaded test run (Result: \(result.testResult.displayText))"
        } else if version == 0 {
            return "Loaded v0 run (Success)"
        } else {
            return "Loaded test run (Run Succeeded)"
        }
    }

}

struct CodableChatMessage: Codable {
    let message: ChatQuery.ChatCompletionMessageParam
    let timestamp: Date
    /// Structured assistant comments extracted from assistant messages.
    /// For legacy reports (versions 1 and 0), this field will be nil because
    /// the assistant message format differs and cannot be reliably parsed.
    let parsedComments: [ParsedAgentComment]?

    enum CodingKeys: String, CodingKey {
        case message
        case timestamp
        case parsedComments = "parsed_comments"
    }
}

// MARK: - Parsed Agent Comment (per assistant message)

struct ParsedAgentComment: Codable {
    let currentLine: Int?
    let totalLines: Int?
    let originalStep: String?
    let analysis: String?
    let tip: String?
    let verification: String?

    enum CodingKeys: String, CodingKey {
        case currentLine = "current_line"
        case totalLines = "total_lines"
        case originalStep = "original_step"
        case analysis
        case tip
        case verification
    }
}

// MARK: - Versioned Models (pure data containers)

struct TestRunDataV2: Codable, TestRunDataProtocol {
    let version: Int
    let originalVersion: Int?
    let runSucceeded: Bool
    let runFailureReason: String?
    let testResult: TestResult?
    let timestamp: String
    let test: String
    let runHistory: [CodableChatMessage]

    // MARK: - Initializers

    /// Creates a new, version-stamped test run.
    /// Use this initializer when saving a new test run.
    init(
        runSucceeded: Bool,
        runFailureReason: String?,
        testResult: TestResult?,
        timestamp: String,
        test: String,
        runHistory: [CodableChatMessage]
    ) {
        self.version = 2 // Always create the latest version.
        self.originalVersion = nil
        self.runSucceeded = runSucceeded
        self.runFailureReason = runFailureReason
        self.testResult = testResult
        self.timestamp = timestamp
        self.test = test
        self.runHistory = runHistory
    }

    /// Creates a `TestRunDataV2` instance for migration purposes.
    internal init(
        version: Int,
        originalVersion: Int?,
        runSucceeded: Bool,
        runFailureReason: String?,
        testResult: TestResult?,
        timestamp: String,
        test: String,
        runHistory: [CodableChatMessage]
    ) {
        self.version = version
        self.originalVersion = originalVersion
        self.runSucceeded = runSucceeded
        self.runFailureReason = runFailureReason
        self.testResult = testResult
        self.timestamp = timestamp
        self.test = test
        self.runHistory = runHistory
    }
}

struct TestRunDataV1: Decodable {
    let version: Int
    let runSucceeded: Bool
    let runFailureReason: String?
    let testResult: TestResult?
    let timestamp: String
    let test: String
    let runHistory: [ChatQuery.ChatCompletionMessageParam]

    internal init(
        version: Int,
        runSucceeded: Bool,
        runFailureReason: String?,
        testResult: TestResult?,
        timestamp: String,
        test: String,
        runHistory: [ChatQuery.ChatCompletionMessageParam]
    ) {
        self.version = version
        self.runSucceeded = runSucceeded
        self.runFailureReason = runFailureReason
        self.testResult = testResult
        self.timestamp = timestamp
        self.test = test
        self.runHistory = runHistory
    }
}

struct TestRunDataV05: Decodable {
    let version: Int
    let runSucceeded: Bool
    let runFailureReason: String?
    let testResult: TestResult?
    let timestamp: String
    let testActions: [Action]
    let runHistory: [ChatQuery.ChatCompletionMessageParam]
}

struct TestRunDataV0: Decodable {
    let success: Bool
    let errorMessage: String?
    let timestamp: String
    let testActions: [Action]
    let runHistory: [ChatQuery.ChatCompletionMessageParam]
}
