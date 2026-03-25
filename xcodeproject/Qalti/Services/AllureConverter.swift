//
//  AllureConverter.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import Foundation
import OpenAI

// MARK: - AllureConverter Class

class AllureConverter {

    private static let filePrefixFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // "yyyyMMdd_HHmmss_SSS" includes milliseconds to minimize the chance of collision
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    enum Error: Swift.Error, LocalizedError {
        case invalidOutputDirectory
        case failedToCreateDirectory
        case failedToWriteFile(String)
        case failedToExtractScreenshot
        case invalidChatHistory

        var errorDescription: String? {
            switch self {
            case .invalidOutputDirectory:
                return "Invalid Allure output directory path"
            case .failedToCreateDirectory:
                return "Failed to create Allure results directory"
            case .failedToWriteFile(let path):
                return "Failed to write Allure file to: \(path)"
            case .failedToExtractScreenshot:
                return "Failed to extract screenshot from chat history"
            case .invalidChatHistory:
                return "Invalid or empty chat history provided"
            }
        }
    }

    let outputDirectory: URL
    private let testName: String
    private let testStartTime: Date
    private let testEndTime: Date
    private let testSuccess: Bool
    private let errorMessage: String?
    private let dateProvider: DateProvider

    init(
        outputDirectory: URL,
        testName: String,
        testStartTime: Date,
        testEndTime: Date,
        testSuccess: Bool,
        errorMessage: String? = nil,
        dateProvider: DateProvider = SystemDateProvider()
    ) {
        self.outputDirectory = outputDirectory
        self.testName = testName
        self.testStartTime = testStartTime
        self.testEndTime = testEndTime
        self.testSuccess = testSuccess
        self.errorMessage = errorMessage
        self.dateProvider = dateProvider
    }

    // MARK: - Public API

    func convertAndSave(from runData: TestRunData) throws {
        guard !runData.runHistory.isEmpty else { throw Error.invalidChatHistory }
        try createOutputDirectoryIfNeeded()

        let filePrefix = AllureConverter.filePrefixFormatter.string(from: dateProvider.now())
        let steps = try parseStepsFromChatHistory(runData.runHistory, filePrefix: filePrefix)

        try buildAndSaveResult(
            runSucceeded: runData.runSucceeded,
            runFailureReason: runData.runFailureReason,
            testResult: runData.testResult,
            steps: steps,
            filePrefix: filePrefix
        )
    }

    func convertAndSave(from enhancedHistory: [EnhancedMessage], runSucceeded: Bool, runFailureReason: String? = nil, testResult: TestResult? = nil) throws {
        guard !enhancedHistory.isEmpty else { throw Error.invalidChatHistory }
        try createOutputDirectoryIfNeeded()

        let filePrefix = AllureConverter.filePrefixFormatter.string(from: dateProvider.now())
        let steps = try parseStepsFromEnhancedHistory(enhancedHistory, filePrefix: filePrefix)

        try buildAndSaveResult(
            runSucceeded: runSucceeded,
            runFailureReason: runFailureReason,
            testResult: testResult,
            steps: steps,
            filePrefix: filePrefix
        )
    }

    // MARK: - Logic & Construction

    private func buildAndSaveResult(
        runSucceeded: Bool,
        runFailureReason: String?,
        testResult: TestResult?,
        steps: [AllureTestResult.AllureStep],
        filePrefix: String
    ) throws {
        let status = determineAllureStatus(
            runSucceeded: runSucceeded,
            runFailureReason: runFailureReason,
            testResult: testResult,
            steps: steps
        )

        var description: String?
        var statusDetails: AllureTestResult.AllureStatusDetails?

        if status == .passed {
            description = testResult?.comments
            statusDetails = nil
        } else {
            let message = runFailureReason ?? "Test execution failed due to errors in steps."
            description = message
            statusDetails = AllureTestResult.AllureStatusDetails(message: message, trace: testResult?.finalStateDescription)
        }

        let allureResult = createAllureTestResult(
            uuid: UUID().uuidString,
            status: status,
            statusDetails: statusDetails,
            description: description,
            steps: steps
        )

        try saveAllureTestResult(allureResult, filePrefix: filePrefix)
    }

    func determineAllureStatus(
        runSucceeded: Bool,
        runFailureReason: String?,
        testResult: TestResult?,
        steps: [AllureTestResult.AllureStep]
    ) -> AllureStatus {
        if !runSucceeded {
            return .broken
        }

        if let result = testResult {
            switch result.testResult {
            case .pass:
                return .passed
            case .failed:
                return .failed
            case .passWithComments:
                return .broken
            }
        }
        return .passed
    }

    // MARK: - Parsing (Internal for Testing)

    func parseStepsFromChatHistory(_ history: [CodableChatMessage], filePrefix: String) throws -> [AllureTestResult.AllureStep] {
        var steps: [AllureTestResult.AllureStep] = []
        var stepCounter = 0
        var currentAssistantMessage: String?

        for (index, message) in history.enumerated() {
            switch message.message {
            case .assistant(let assistantParam):
                currentAssistantMessage = extractAssistantContent(from: assistantParam.content)
                if let toolCalls = assistantParam.toolCalls {
                    var currentStartTime = message.timestamp
                    for toolCall in toolCalls {
                        stepCounter += 1
                        let endTime = findToolEndTime(history: history, startIndex: index + 1, toolCallId: toolCall.id, defaultStart: currentStartTime)

                        steps.append(createAllureStep(
                            stepNumber: stepCounter,
                            toolCall: toolCall,
                            assistantMessage: currentAssistantMessage,
                            startTime: currentStartTime,
                            endTime: endTime
                        ))
                        currentStartTime = endTime
                    }
                }
            case .tool(let toolParam):
                if !steps.isEmpty, let toolResponse = extractToolContent(from: toolParam.content) {
                    steps[steps.count - 1] = updateStepWithToolResponse(
                        step: steps[steps.count - 1],
                        toolResponse: toolResponse
                    )
                }
            case .user(let userParam):
                if case .contentParts(let parts) = userParam.content, !steps.isEmpty {
                    var attachments: [AllureTestResult.AllureAttachment] = []

                    let imageParams = parts.compactMap { part -> ChatQuery.ChatCompletionMessageParam.ContentPartImageParam? in
                        if case .image(let imageParam) = part {
                            return imageParam
                        }
                        return nil
                    }

                    for (imageIndex, imageParam) in imageParams.enumerated() {
                        let attachmentName = AllureNamer.screenshotName(
                            step: stepCounter,
                            imageIndex: imageIndex,
                            totalImagesInMessage: imageParams.count
                        )

                        if let filename = try saveScreenshotAttachment(
                            prefix: filePrefix + "_",
                            imageUrl: imageParam.imageUrl.url,
                            stepNumber: stepCounter,
                            imageIndex: imageIndex
                        ) {
                            attachments.append(.init(name: attachmentName, source: filename, type: "image/jpeg"))
                        }
                    }
                    if !attachments.isEmpty {
                        steps[steps.count-1] = addAttachmentsToStep(step: steps[steps.count-1], attachments: attachments)
                    }
                }
            default: break
            }
        }
        return steps
    }

    func parseStepsFromEnhancedHistory(_ history: [EnhancedMessage], filePrefix: String) throws -> [AllureTestResult.AllureStep] {
        var steps: [AllureTestResult.AllureStep] = []
        var stepCounter = 0
        var currentAssistantMessage: String?

        for (index, message) in history.enumerated() {
            switch message {
            case .assistant(let assistantParam, let timestamp):
                currentAssistantMessage = extractAssistantContent(from: assistantParam.content)
                if let toolCalls = assistantParam.toolCalls {
                    var currentStartTime = timestamp
                    for toolCall in toolCalls {
                        stepCounter += 1
                        let endTime = findToolEndTime(history: history, startIndex: index + 1, toolCallId: toolCall.id, defaultStart: currentStartTime)

                        steps.append(createAllureStep(
                            stepNumber: stepCounter,
                            toolCall: toolCall,
                            assistantMessage: currentAssistantMessage,
                            startTime: currentStartTime,
                            endTime: endTime
                        ))
                        currentStartTime = endTime
                    }
                }
            case .tool(let toolParam, _):
                if !steps.isEmpty, let toolResponse = extractToolContent(from: toolParam.content) {
                    steps[steps.count - 1] = updateStepWithToolResponse(
                        step: steps[steps.count - 1],
                        toolResponse: toolResponse
                    )
                }
            case .user(let userParam, let enhancedParts, _):
                if !steps.isEmpty {
                    var attachments: [AllureTestResult.AllureAttachment] = []

                    if let enhancedParts = enhancedParts {
                        let imageParts = enhancedParts.filter { if case .imageWithData = $0 { return true } else { return false } }

                        for (imageIndex, part) in imageParts.enumerated() {
                            if case .imageWithData(_, let base64) = part, let data = Data(fromImageDataString: base64) {
                                let attachmentName = AllureNamer.screenshotName(
                                    step: stepCounter,
                                    imageIndex: imageIndex,
                                    totalImagesInMessage: imageParts.count
                                )
                                let filename = try saveScreenshotFromBase64(
                                    prefix: filePrefix + "_",
                                    base64Data: data,
                                    stepNumber: stepCounter,
                                    imageIndex: imageIndex
                                )
                                attachments.append(.init(name: attachmentName, source: filename, type: "image/jpeg"))
                            }
                        }
                    } else if case .contentParts(let parts) = userParam.content {
                        let imageParams = parts.compactMap { part -> ChatQuery.ChatCompletionMessageParam.ContentPartImageParam? in
                            if case .image(let imageParam) = part { return imageParam }
                            return nil
                        }

                        for (imageIndex, imageParam) in imageParams.enumerated() {
                            let attachmentName = AllureNamer.screenshotName(
                                step: stepCounter,
                                imageIndex: imageIndex,
                                totalImagesInMessage: imageParams.count
                            )
                            if let filename = try saveScreenshotAttachment(
                                prefix: filePrefix + "_",
                                imageUrl: imageParam.imageUrl.url,
                                stepNumber: stepCounter,
                                imageIndex: imageIndex
                            ) {
                                attachments.append(.init(name: attachmentName, source: filename, type: "image/jpeg"))
                            }
                        }
                    }
                    if !attachments.isEmpty {
                        steps[steps.count-1] = addAttachmentsToStep(step: steps[steps.count-1], attachments: attachments)
                    }
                }
            default: break
            }
        }
        return steps
    }

    // MARK: - Step Helpers

    func updateStepWithToolResponse(step: AllureTestResult.AllureStep, toolResponse: String) -> AllureTestResult.AllureStep {
        var status: AllureStatus = .passed
        var statusDetails = step.statusDetails

        if let data = toolResponse.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let success = dict["success"] as? Bool, !success {
                status = .failed

                let cleanError = AllureErrorExtractor.extractCleanError(from: dict)
                let originalIntent = statusDetails?.message ?? "No context"

                statusDetails = AllureTestResult.AllureStatusDetails(
                    message: "Failed: \(cleanError)",
                    trace: "Error: \(cleanError)\n\nIntent: \(originalIntent)\n\nRaw: \(toolResponse)"
                )
            }
        } else {
            status = .broken
            statusDetails = AllureTestResult.AllureStatusDetails(message: "Tool output format error", trace: toolResponse)
        }

        return AllureTestResult.AllureStep(
            name: step.name,
            status: status,
            statusDetails: statusDetails,
            start: step.start,
            stop: step.stop,
            attachments: step.attachments,
            parameters: step.parameters
        )
    }

    private func findToolEndTime(history: [CodableChatMessage], startIndex: Int, toolCallId: String, defaultStart: Date) -> Date {
        for i in startIndex..<history.count {
            if case .tool(let tool) = history[i].message, tool.toolCallId == toolCallId {
                return history[i].timestamp
            }
        }
        return defaultStart.addingTimeInterval(0.1)
    }

    private func findToolEndTime(history: [EnhancedMessage], startIndex: Int, toolCallId: String, defaultStart: Date) -> Date {
        for i in startIndex..<history.count {
            if case .tool(let tool, let timestamp) = history[i], tool.toolCallId == toolCallId {
                return timestamp
            }
        }
        return defaultStart.addingTimeInterval(0.1)
    }

    func createAllureStep(
        stepNumber: Int,
        toolCall: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam,
        assistantMessage: String?,
        startTime: Date,
        endTime: Date
    ) -> AllureTestResult.AllureStep {

        let toolName = toolCall.function.name

        // 1. Generate a human-readable name from the LLM's comment
        let rawDescription = AllureDescriptionExtractor.extractDescription(from: assistantMessage)
        let cleanDescription = AllureDescriptionExtractor.cleanForStepName(rawDescription)

        // Format: "1. [tap] Tapping login button"
        let stepName: String
        if let cleanDescription {
            stepName = "\(stepNumber). [\(toolName)] \(cleanDescription)"
        } else {
            stepName = "\(stepNumber). [\(toolName)]"
        }

        // 2. Add 'tool' as a parameter so it's searchable
        var parameters: [AllureTestResult.AllureParameter] = [
            .init(name: "tool", value: toolName)
        ]

        // 3. Add existing tool arguments
        if let data = toolCall.function.arguments.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let argParams = dict.map { AllureTestResult.AllureParameter(name: $0.key, value: String(describing: $0.value)) }
            parameters.append(contentsOf: argParams)
        }

        return AllureTestResult.AllureStep(
            name: stepName,
            status: .passed, // Default to passed, updated later
            statusDetails: assistantMessage.map { AllureTestResult.AllureStatusDetails(message: $0, trace: nil) },
            start: Int64(startTime.timeIntervalSince1970 * 1000),
            stop: Int64(endTime.timeIntervalSince1970 * 1000),
            attachments: nil,
            parameters: parameters.isEmpty ? nil : parameters
        )
    }

    // MARK: - Final Result Creation

    private func createAllureTestResult(
        uuid: String,
        status: AllureStatus,
        statusDetails: AllureTestResult.AllureStatusDetails?,
        description: String?,
        steps: [AllureTestResult.AllureStep]
    ) -> AllureTestResult {
        let testCaseId = UUID().uuidString
        let historyId = testName.data(using: .utf8)?.sha256 ?? UUID().uuidString
        let labels = [
            AllureTestResult.AllureLabel(name: "framework", value: "qalti"),
            AllureTestResult.AllureLabel(name: "host", value: Host.current().localizedName ?? "unknown"),
            AllureTestResult.AllureLabel(name: "language", value: "swift"),
            AllureTestResult.AllureLabel(name: "feature", value: testName)
        ]
        return AllureTestResult(
            uuid: uuid,
            historyId: historyId,
            testCaseId: testCaseId,
            fullName: testName,
            name: testName,
            status: status,
            statusDetails: statusDetails,
            description: description,
            start: Int64(testStartTime.timeIntervalSince1970 * 1000),
            stop: Int64(testEndTime.timeIntervalSince1970 * 1000),
            steps: steps,
            labels: labels,
            links: [],
            attachments: nil
        )
    }

    // MARK: - File System Helpers (Private)

    private func createOutputDirectoryIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: outputDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            } catch { throw Error.failedToCreateDirectory }
        }
    }

    private func saveAllureTestResult(_ result: AllureTestResult, filePrefix: String) throws {
        let fileURL = outputDirectory.appendingPathComponent("\(filePrefix)-result.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            try encoder.encode(result).write(to: fileURL)
        } catch { throw Error.failedToWriteFile(fileURL.path) }
    }

    private func saveScreenshotAttachment(prefix: String, imageUrl: String, stepNumber: Int, imageIndex: Int) throws -> String? {
        if imageUrl.hasPrefix("data:image/"), let base64 = imageUrl.components(separatedBy: ",").last, let data = Data(base64Encoded: base64) {
            return try saveScreenshotFromBase64(prefix: prefix, base64Data: data, stepNumber: stepNumber, imageIndex: imageIndex)
        }
        return nil
    }

    private func saveScreenshotFromBase64(prefix: String, base64Data: Data, stepNumber: Int, imageIndex: Int) throws -> String {
        let filename = String(format: "%@step_%03d_screenshot_%02d.jpeg", prefix, stepNumber, imageIndex)
        let url = outputDirectory.appendingPathComponent(filename)
        try base64Data.write(to: url)
        return filename
    }

    private func addAttachmentsToStep(step: AllureTestResult.AllureStep, attachments: [AllureTestResult.AllureAttachment]) -> AllureTestResult.AllureStep {
        return .init(name: step.name, status: step.status, statusDetails: step.statusDetails, start: step.start, stop: step.stop, attachments: attachments, parameters: step.parameters)
    }

    private func extractAssistantContent(from content: ChatQuery.ChatCompletionMessageParam.TextOrRefusalContent?) -> String? {
        guard let content = content else { return nil }
        if case .textContent(let text) = content { return text }
        return nil
    }

    private func extractToolContent(from content: ChatQuery.ChatCompletionMessageParam.TextContent) -> String? {
        if case .textContent(let text) = content { return text }
        return nil
    }
}
