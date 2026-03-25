//
//  VersionedTestRun.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 13.11.25.
//

import Foundation
import OpenAI

enum VersionedTestRun: Decodable {
    case v0(TestRunDataV0)
    case v05(TestRunDataV05)
    case v1(TestRunDataV1)
    case v2(TestRunDataV2)

    private struct VersionCheck: Decodable { let version: Int? }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let versionCheck = try container.decode(VersionCheck.self)

        switch versionCheck.version {
        case 2:
            self = .v2(try container.decode(TestRunDataV2.self))
        case 1:
            // this intermediate version is needed due to Slava releasing version that was not supposed to be released
            if let intermediate = try? container.decode(TestRunDataV05.self) {
                self = .v05(intermediate)
            } else {
                self = .v1(try container.decode(TestRunDataV1.self))
            }
        default:
            self = .v0(try container.decode(TestRunDataV0.self))
        }
    }

    func migrated(using contentParser: ContentParser) -> TestRunData {
        switch self {
        case .v2(let run):
            return run
        case .v1(let runV1):
            return migrate(from: runV1)                             // V1 -> V2
        case .v05(let runV05):
            let runV1 = migrate(from: runV05)                       // V0.5 -> V1
            return migrate(from: runV1)                             // V1 -> V2
        case .v0(let runV0):
            let runV1 = migrate(from: runV0, using: contentParser)  // V0 -> V1
            return migrate(from: runV1)                             // V1 -> V2
        }
    }

    // MARK: - Migration Functions

    private func migrate(from v0: TestRunDataV0, using contentParser: ContentParser) -> TestRunDataV1 {
        let testResult: TestResult?
        if let lastMessage = v0.runHistory.last,
           case .assistant(let assistantParam) = lastMessage,
           let content = assistantParam.content, case .textContent(let text) = content {
            testResult = contentParser.parseContent(text).testResult
        } else {
            testResult = nil
        }

        let test = v0.testActions
            .map { $0.parsedAction ?? $0.action }
            .joined(separator: "\n")

        return TestRunDataV1(
            // Intentionally set the version to 0 here. This intermediate V1 object
            // acts as a carrier for the *original* version number (0) up to the
            // next migration step (V1 -> V2), where it will be correctly assigned
            // to the `originalVersion` property.
            version: 0,
            runSucceeded: v0.success,
            runFailureReason: v0.errorMessage,
            testResult: testResult,
            timestamp: v0.timestamp,
            test: test,
            runHistory: v0.runHistory
        )
    }

    private func migrate(from v05: TestRunDataV05) -> TestRunDataV1 {
        let test = v05.testActions
            .map { $0.parsedAction ?? $0.action }
            .joined(separator: "\n")

        return TestRunDataV1(
            // Preserve original major version bucket as 0 for V0.x lineage.
            version: 0,
            runSucceeded: v05.runSucceeded,
            runFailureReason: v05.runFailureReason,
            testResult: v05.testResult,
            timestamp: v05.timestamp,
            test: test,
            runHistory: v05.runHistory
        )
    }

    private func migrate(from v1: TestRunDataV1) -> TestRunDataV2 {
        let runDate = ISO8601DateFormatter().date(from: v1.timestamp) ?? Date()

        return TestRunDataV2(
            version: 2,
            originalVersion: v1.version,
            runSucceeded: v1.runSucceeded,
            runFailureReason: v1.runFailureReason,
            testResult: v1.testResult,
            timestamp: v1.timestamp,
            test: v1.test,
            runHistory: v1.runHistory.map { message in
                // For legacy runs (v1 and earlier), assistant messages used a different
                // format that is not reliably parseable into structured comments.
                // Preserve them as-is and keep `parsedComments` nil.
                return CodableChatMessage(
                    message: message,
                    timestamp: runDate,
                    parsedComments: nil
                )
            }
        )
    }
}
