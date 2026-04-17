//
//  IOSAgent.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 22.05.2025.
//

@preconcurrency import OpenAI
import Foundation
import Logging

class IOSAgent: Loggable {

    enum Error: Swift.Error, LocalizedError {
        case unableToInitialisePrompt
        case unexpectedResponse
        case unableToSendImage
        case unableToCreateLogDirectory
        case unableToWriteLogFile
        case authenticationFailed
        case insufficientBalance
        case screenshotWithoutS3URL
        case scriptFailed(message: String)
        case backendReportedError(statusCode: Int, message: String)
        case missingOpenRouterKey
        case missingS3Credentials
        case missingBase64ImageData
        case rateLimited(retryAfter: TimeInterval, headers: [String: Any])
        case requestThrottled(info: String)

        var errorDescription: String? {
            switch self {
            case .unableToInitialisePrompt:
                return "Failed to initialize test prompt"
            case .unexpectedResponse:
                return "Received unexpected response from AI service"
            case .unableToSendImage:
                return "Failed to process screenshot"
            case .unableToCreateLogDirectory:
                return "Failed to create log directory"
            case .unableToWriteLogFile:
                return "Failed to write log file"
            case .authenticationFailed:
                return "OpenRouter authentication failed. Please check your API key."
            case .insufficientBalance:
                return "OpenRouter balance is insufficient. Please add funds to continue running tests."
            case .screenshotWithoutS3URL:
                return "Screenshot processing failed: S3 URL is required but not available. This indicates a configuration or upload issue."
            case .scriptFailed(let message):
                return "run_script failed: \(message)"
            case .backendReportedError(let statusCode, let message):
                return "Server error (\(statusCode)): \(message)"
            case .missingOpenRouterKey:
                return "OpenRouter API key is missing. Please add it in Settings."
            case .missingS3Credentials:
                return "AWS S3 credentials are missing. Please add them in Settings."
            case .missingBase64ImageData:
                return "Screenshot processing failed: base64 image data is required when S3 is not configured."
            case .rateLimited(let retryAfter, _):
                return "Rate limited by OpenRouter. Please wait \(Int(retryAfter)) seconds before retrying. The free tier has request limits."
            case .requestThrottled(let info):
                return "Request throttled: \(info)"
            }
        }
    }

    /// Information extracted from rate limit response headers
    struct RateLimitInfo {
        let retryAfter: TimeInterval
        let limit: Int?
        let remaining: Int?
        let resetTime: Date?
        let headers: [String: Any]

        init(from response: HTTPURLResponse) {
            // Normalize header keys to lowercase strings
            let rawHeaders = response.allHeaderFields
            var normalizedHeaders: [String: Any] = [:]
            for (key, value) in rawHeaders {
                let keyString = String(describing: key).lowercased()
                normalizedHeaders[keyString] = value
            }
            headers = normalizedHeaders

            // Parse Retry-After header (seconds or HTTP date), case-insensitive, handle NSNumber
            let retryAfterValue = headers["retry-after"]
            if let retryAfterString = retryAfterValue as? String {
                if let seconds = TimeInterval(retryAfterString) {
                    retryAfter = seconds
                } else if let date = DateFormatter.parseHTTPDate(retryAfterString) {
                    retryAfter = max(0, date.timeIntervalSinceNow)
                } else {
                    retryAfter = 60.0 // Default fallback
                }
            } else if let retryAfterNumber = retryAfterValue as? NSNumber {
                retryAfter = retryAfterNumber.doubleValue
            } else {
                retryAfter = 60.0 // Default for 429 without Retry-After
            }

            // Parse rate limit headers (various formats, case-insensitive)
            limit = (headers["x-ratelimit-limit"] as? String).flatMap(Int.init) ??
                   (headers["x-rate-limit-limit"] as? String).flatMap(Int.init)

            remaining = (headers["x-ratelimit-remaining"] as? String).flatMap(Int.init) ??
                       (headers["x-rate-limit-remaining"] as? String).flatMap(Int.init)

            if let resetString = headers["x-ratelimit-reset"] as? String ?? headers["x-rate-limit-reset"] as? String,
               let resetTimestamp = TimeInterval(resetString) {
                resetTime = Date(timeIntervalSince1970: resetTimestamp)
            } else {
                resetTime = nil
            }
        }
        
        var description: String {
            var parts: [String] = []
            if let limit = limit, let remaining = remaining {
                parts.append("limit: \(limit), remaining: \(remaining)")
            }
            if let resetTime = resetTime {
                let formatter = DateFormatter()
                formatter.dateStyle = .none
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeStyle = .medium
                parts.append("resets at: \(formatter.string(from: resetTime))")
            }
            return parts.isEmpty ? "rate limited" : parts.joined(separator: ", ")
        }
    }

    enum Constants {
        static let iPhoneImageSize = 512
        static let iPadImageSize = 1024

        static let pointOutImageSize = 1024
    }

    final class ErrorDecodingMiddleware: OpenAIMiddleware, @unchecked Sendable {
        private let stateQueue = DispatchQueue(label: "io.qalti.middleware.error.state")
        private var _insufficientBalance: Bool = false
        private var _authenticationFailed: Bool = false
        private var _timeout: Bool = false
        private var _lastStatusCode: Int? = nil
        private var _lastErrorBody: String? = nil

        var insufficientBalance: Bool { stateQueue.sync { _insufficientBalance } }
        var authenticationFailed: Bool { stateQueue.sync { _authenticationFailed } }
        var timeout: Bool { stateQueue.sync { _timeout } }
        var lastStatusCode: Int? { stateQueue.sync { _lastStatusCode } }
        var lastErrorBody: String? { stateQueue.sync { _lastErrorBody } }

        func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) {
            guard let response = response as? HTTPURLResponse else { return (response, data) }
            let bodyString = data.flatMap { String(data: $0, encoding: .utf8) }
            stateQueue.sync {
                _lastStatusCode = response.statusCode
                if (400...599).contains(response.statusCode) {
                    _lastErrorBody = bodyString
                } else {
                    _lastErrorBody = nil
                }
            }
            switch response.statusCode {
            case 504:
                stateQueue.sync { _timeout = true }
                return (response, nil)
            case 402:
                stateQueue.sync { _insufficientBalance = true }
                return (response, nil)
            case 401:
                stateQueue.sync { _authenticationFailed = true }
                return (response, nil)
            default:
                return (response, data)
            }
        }
    }

    private struct PreparedQueryResult {
        let historyForLLM: [ChatQuery.ChatCompletionMessageParam]
        let authenticatedOpenAI: OpenAI
        let query: ChatQuery
        let errorCheckingMiddleware: ErrorDecodingMiddleware
    }

    private struct StreamedAssistantResult {
        let assistantContent: String
        let toolCalls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam]
        let didStreamAssistantMessage: Bool
    }

    private struct ToolExecutionResult {
        let lastResultImage: PlatformImage?
        let lastScreenshotURL: URL?
    }

    private(set) var isCancelled: Bool = false
    var apiCallCounter: Int = 0
    let logDirectory: URL

    private let commandExecutorTools: CommandExecutorToolsForAgent
    private let workingDirectoryForBash: URL
    private let testDirectory: URL
    private let credentialsService: any CredentialsServicing
    let errorCapturer: ErrorCapturing
    private let timeout: TimeInterval
    private var ongoingChatRequest: CancellableRequest? = nil
    private let runHistory: RunHistory
    private var streamRequestCounter: Int = 0

    func cancel() {
        isCancelled = true
        // MacPaw/OpenAI cancels the streaming request when the returned request token
        // is deallocated. Clearing our strong reference stops the stream.
        ongoingChatRequest = nil
    }

    init(
        runtime: IOSRuntime,
        elementLocator: UIElementLocator,
        workingDirectoryForBash: URL,
        testDirectory: URL,
        credentialsService: any CredentialsServicing,
        errorCapturer: ErrorCapturing,
        timeout: TimeInterval = 240.0,
        runHistory: RunHistory
    ) {
        self.credentialsService = credentialsService
        self.errorCapturer = errorCapturer
        self.timeout = timeout
        self.runHistory = runHistory
        self.workingDirectoryForBash = workingDirectoryForBash
        self.testDirectory = testDirectory.standardizedFileURL
        let screenshotUploader = ScreenshotUploader(credentialsService: credentialsService, errorCapturer: errorCapturer)

        commandExecutorTools = CommandExecutorToolsForAgent(
            runtime: runtime,
            elementLocator: elementLocator,
            screenshotUploader: screenshotUploader,
            agentImageSize: runtime.isIpad ? Constants.iPadImageSize : Constants.iPhoneImageSize,
            pointOutImageSize: Constants.pointOutImageSize,
            workingDirectoryForBash: workingDirectoryForBash
        )

        // Create log directory path
        let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dateString = DateFormatter.formatLogFileName(Date())
        logDirectory = downloadsPath.appendingPathComponent("test_run_logs").appendingPathComponent(dateString)
    }

    // MARK: - Public API
    func run(
        testCaseName: String,
        recordedSteps: String,
        maxIterations: Int,
        model: TestRunner.AvailableModel,
        stepUpdateCallback: (([String], Int?) -> Void)? = nil
    ) async throws {
        try runSync(
            testCaseName: testCaseName,
            recordedSteps: recordedSteps,
            maxIterations: maxIterations,
            model: model,
            stepUpdateCallback: stepUpdateCallback
        )
    }

    func runSync(
        testCaseName: String,
        recordedSteps: String,
        maxIterations: Int,
        model: TestRunner.AvailableModel,
        stepUpdateCallback: (([String], Int?) -> Void)? = nil
    ) throws {
        let lineByLine = recordedSteps.split(separator: "\n").map(String.init)
        let tools = try prepareInitialMessagesAndTools(testCaseName: testCaseName, recordedSteps: recordedSteps)

        if credentialsService.s3Settings == nil {
            logger.info("AWS S3 credentials missing; using base64 screenshots")
        }

        // Add initial screenshot message before starting LLM loop
        try appendInitialScreenshotOrThrow(model: model)

        var parsedResult: [String: Any]? = nil
        var executedCommands: [String] = []

        for iteration in 0..<maxIterations {
            if isCancelled {
                logger.debug("Task was cancelled, stopping execution")
                throw CancellationError()
            }

            let preparedQuery = try prepareQuery(model: model, tools: tools)
            let streamed = try streamWithRetries(
                preparedQuery: preparedQuery,
                toolCount: tools.count,
                iteration: iteration,
                // Internal retries are intentionally disabled (maxRetries: 0); retry logic
                // is handled at the higher-level TestRunner layer. If transient non-rate-limit
                // failures become a problem, consider restoring a small retry budget here.
                maxRetries: 0
            )

            guard streamed.toolCalls.isEmpty == false else {
                logger.debug("No tool calls in assistant response")
                if containsValidJSON(streamed.assistantContent) {
                    logger.debug("Found valid JSON in assistant response")
                    if streamed.didStreamAssistantMessage == false {
                        runHistory.append(.assistant(.init(content: .textContent(streamed.assistantContent), audio: nil, name: "assistant", toolCalls: nil)))
                    }
                    parsedResult = try extractJSON(from: streamed.assistantContent)
                    break
                } else {
                    logger.debug("No JSON found, asking for JSON or to continue test execution")
                    if streamed.didStreamAssistantMessage == false {
                        runHistory.append(.assistant(.init(content: .textContent(streamed.assistantContent), audio: nil, name: "assistant", toolCalls: nil)))
                    }
                    runHistory.append(.user(.init(content: .string(try Prompts.jsonContinuationPrompt()))))
                    continue
                }
            }

            let index: Int? = ChatQuery.ChatCompletionMessageParam.assistant(.init(content: .textContent(streamed.assistantContent))).extractLineNumber()

            // Enforce comment-before-action to maintain agent quality
            if try shouldRejectToolCallsWithoutComment(streamed: streamed) {
                continue
            }

            let line: String?
            if let index, index > 0, index <= lineByLine.count {
                line = lineByLine[index - 1]
            } else {
                line = nil
            }

            let toolExec = try runToolCalls(
                streamed.toolCalls,
                executedCommands: &executedCommands,
                index: index,
                line: line,
                iteration: iteration,
                maxIterations: maxIterations,
                stepUpdateCallback: stepUpdateCallback
            )

            try handleScreenshotPostToolCalls(
                lastResultImage: toolExec.lastResultImage,
                lastScreenshotURL: toolExec.lastScreenshotURL,
                useGeminiFix: model.separateImageAndText
            )

        }

        if let stepUpdateCallback = stepUpdateCallback {
            DispatchQueue.main.async {
                stepUpdateCallback([], nil)
            }
        }

        if let parsedResult = parsedResult {
            logger.debug("Returning parsed JSON result: \(parsedResult)")
            return
        } else {
            logger.warning("Max iterations reached without completion or valid JSON result")
            throw Error.unexpectedResponse
        }
    }

    private func streamWithRetries(
        preparedQuery: PreparedQueryResult,
        toolCount: Int,
        iteration: Int,
        maxRetries: Int
    ) throws -> StreamedAssistantResult {
        // We count "retries" excluding the initial attempt, so total attempts = maxRetries + 1.
        for attempt in 0...maxRetries {
            if attempt > 0 {
                // 1st retry right away, 2nd after small delay, 3rd after bigger delay.
                let delay: TimeInterval
                switch attempt {
                case 1: delay = 0.0
                case 2: delay = 1.0
                default: delay = 5.0
                }
                logger.info("Retrying LLM request (retry #\(attempt) of \(maxRetries)) after previous failure. Delay before retry: \(delay)s")
                if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            }

            do {
                return try streamResult(
                    authenticatedOpenAI: preparedQuery.authenticatedOpenAI,
                    query: preparedQuery.query,
                    historyForLLMCount: preparedQuery.historyForLLM.count,
                    toolCount: toolCount,
                    iteration: iteration
                )
            } catch {
                errorCapturer.capture(error: error)
                var effectiveError: Swift.Error = error

                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    logger.error("API call failed: cancelled (NSURLErrorCancelled/-999). This usually means the request was cancelled locally (e.g. user stopped the test, or a new request replaced the old one).")
                } else {
                    logger.error("API call failed: \(error)")
                }

                // If the agent was cancelled, don't retry.
                if isCancelled {
                    throw CancellationError()
                }

                // Handle non-retriable auth/billing errors immediately
                if preparedQuery.errorCheckingMiddleware.authenticationFailed {
                    throw Error.authenticationFailed
                } else if preparedQuery.errorCheckingMiddleware.insufficientBalance {
                    throw Error.insufficientBalance
                }

                // If OpenRouter returned a non-2xx error, log the body (high signal for debugging).
                if let status = preparedQuery.errorCheckingMiddleware.lastStatusCode,
                   (400...599).contains(status) {
                    let body = preparedQuery.errorCheckingMiddleware.lastErrorBody
                    if let body, !body.isEmpty {
                        logger.error("OpenRouter error (status \(status)): \(body)")
                    } else {
                        logger.error("OpenRouter error (status \(status)) with empty body")
                    }
                }

                // Decoding / protocol mismatch: if it happened on a non-2xx response,
                // treat it as a backend error so we can retry/log meaningfully.
                if let decodingError = error as? DecodingError {
                    let status = preparedQuery.errorCheckingMiddleware.lastStatusCode
                    if let status, (400...599).contains(status) {
                        let body = preparedQuery.errorCheckingMiddleware.lastErrorBody ?? "\(decodingError)"
                        logger.error("OpenRouter returned non-2xx with undecodable body (status \(status)): \(body)")
                        effectiveError = Error.backendReportedError(statusCode: status, message: body)
                    } else {
                        logger.error("Response format mismatch from OpenRouter: \(decodingError)")
                        throw Error.unexpectedResponse
                    }
                }

                let shouldRetry: Bool = {
                    if preparedQuery.errorCheckingMiddleware.timeout {
                        return true
                    }

                    // If we got an HTTP error from OpenRouter and it's not auth/billing, retry it.
                    //
                    // NOTE (2025-12): We observed that for streaming requests, MacPaw/OpenAI may surface
                    // non-2xx responses as `OpenAIError.statusError(response:..., statusCode: ...)`
                    // without reliably providing the response body to our middleware. That means we
                    // can't safely classify HTTP 400 errors by inspecting the body (e.g. "thought_signature")
                    // on the client side. To keep the system reliable, we retry all 400s here.
                    if let status = preparedQuery.errorCheckingMiddleware.lastStatusCode,
                       (400...599).contains(status) {
                        if status == 401 || status == 402 {
                            return false
                        }
                        return true
                    }

                    if nsError.domain == NSURLErrorDomain {
                        switch nsError.code {
                        case NSURLErrorCancelled:
                            return false
                        case NSURLErrorTimedOut,
                             NSURLErrorNetworkConnectionLost,
                             NSURLErrorCannotFindHost,
                             NSURLErrorCannotConnectToHost,
                             NSURLErrorDNSLookupFailed,
                             NSURLErrorNotConnectedToInternet:
                            return true
                        default:
                            break
                        }
                    }

                    return true
                }()

                if !shouldRetry || attempt >= maxRetries {
                    throw effectiveError
                }
            }
        }

        // Should be unreachable due to the loop logic above.
        throw Error.unexpectedResponse
    }

    private func prepareInitialMessagesAndTools(testCaseName: String, recordedSteps: String) throws -> [ChatQuery.ChatCompletionToolParam] {
        logger.debug("Starting new test run: \(testCaseName)")

        // Load .qaltirules if present
        let qaltiRules = findQaltiRulesContents()

        // Use the test execution template as the system prompt (filled with test details)
        let systemPromptContent = try Prompts.generateSystemPrompt(
            testName: testCaseName,
            recordedSteps: recordedSteps,
            qaltiRules: qaltiRules
        )

        logger.debug("Configuring tools:")
        let functionDefinitions = try Prompts.iosFunctionDefinitions()
        guard let systemMessage = ChatQuery.ChatCompletionMessageParam(role: .system, content: systemPromptContent) else {
            logger.error("Failed to initialize system message")
            throw Error.unableToInitialisePrompt
        }
        let tools = functionDefinitions.map(ChatQuery.ChatCompletionToolParam.init)

        // Initialize history with system prompt only
        runHistory.setHistory([systemMessage])

        return tools
    }

    /// Finds and reads `.qaltirules` starting from the test folder upward until root or ~/Documents/Qalti
    private func findQaltiRulesContents() -> String? {
        let startDir = testDirectory
        let fm = FileManager.default
        let stopDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("Qalti")
            .standardizedFileURL

        var current = startDir
        while true {
            let candidate = current.appendingPathComponent(".qaltirules")
            if fm.fileExists(atPath: candidate.path) {
                do {
                    let text = try String(contentsOf: candidate, encoding: .utf8)
                    logger.debug("Loaded .qaltirules from \(candidate.path)")
                    return text
                } catch {
                    logger.error("Failed to read .qaltirules at \(candidate.path): \(error)")
                    break
                }
            }
            if current.path == "/" || current == stopDir {
                break
            }
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }
        logger.debug("No .qaltirules found up to root or ~/Documents/Qalti")
        return nil
    }

    private func resolveScreenshotReference(
        context: String,
        imageData: Data?,
        imageURL: URL?
    ) throws -> (referenceURLString: String, imageData: Data) {
        if credentialsService.s3Settings != nil {
            guard let data = imageData else { throw Error.unableToSendImage }
            guard let url = imageURL else { throw Error.screenshotWithoutS3URL }
            let reference = url.absoluteString
            logScreenshotReference(reference, context: context)
            return (reference, data)
        }

        guard let data = imageData else { throw Error.missingBase64ImageData }
        let reference = data.toBase64JpegURLString()
        logScreenshotReference(reference, context: context)
        return (reference, data)
    }

    private func logScreenshotReference(_ reference: String, context: String) {
        if reference.hasPrefix("data:image/") {
            logger.debug("\(context): using base64 screenshot data URL (length \(reference.count))")
        } else {
            logger.debug("\(context): using screenshot URL \(reference)")
        }
    }

    /// Capture an initial screenshot and append it to chat history as a user message.
    private func appendInitialScreenshotOrThrow(model: TestRunner.AvailableModel) throws {
        let screenshotMessage = try Prompts.initialScreenshotMessage()
        let group = DispatchGroup()
        var initialImageData: Data? = nil
        var initialImageURL: URL? = nil
        group.enter()
        commandExecutorTools.screenshot { response in
            initialImageData = response.imageJpegData
            initialImageURL = response.imageJpegURL
            group.leave()
        }
        let waitResult = group.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            logger.error("Timeout while capturing initial screenshot")
            errorCapturer.capture(error: Error.unableToSendImage)
            throw Error.unableToSendImage
        }

        do {
            let resolved = try resolveScreenshotReference(
                context: "Initial screenshot",
                imageData: initialImageData,
                imageURL: initialImageURL
            )
            runHistory.appendUserWithScreenshot(
                textContent: screenshotMessage,
                imageURL: resolved.referenceURLString,
                imageData: resolved.imageData,
                useGeminiFix: false // the first image is handled correctly by API
            )
            logger.debug("Added initial screenshot to conversation history")
        } catch Error.screenshotWithoutS3URL {
            logger.error("Initial screenshot missing S3 URL; cannot proceed without image URL")
            errorCapturer.capture(error: Error.screenshotWithoutS3URL)
            throw Error.screenshotWithoutS3URL
        } catch Error.missingBase64ImageData {
            logger.error("Initial screenshot missing base64 data; cannot proceed without image data")
            errorCapturer.capture(error: Error.missingBase64ImageData)
            throw Error.missingBase64ImageData
        } catch {
            logger.error("Failed to capture initial screenshot")
            throw error
        }
    }

    private func prepareQuery(
        model: TestRunner.AvailableModel,
        tools: [ChatQuery.ChatCompletionToolParam]
    ) throws -> PreparedQueryResult {
        let historyForLLM = runHistory.getHistory(imageType: .url)
        logger.debug("Sending request to OpenRouter with \(historyForLLM.count) messages")
        if AppConstants.shouldLogAgentActions, AppConstants.isDebug {
            try saveMessagesToLog(runHistory.getHistory(imageType: .base64))
        }
        guard let openRouterKey = credentialsService.openRouterKey, !openRouterKey.isEmpty else {
            logger.error("OpenRouter API key missing")
            throw Error.missingOpenRouterKey
        }
        let query = ChatQuery(
            messages: historyForLLM,
            model: model.fullName,
            reasoningEffort: model.reasoning,
            maxCompletionTokens: 1000,
            temperature: 0.7,
            tools: tools
        )
        let configuration = OpenAI.Configuration(
            token: openRouterKey,
            host: "openrouter.ai",
            port: 443,
            scheme: "https",
            basePath: "/api/v1",
            timeoutInterval: timeout
        )
        let errorCheckingMiddleware = ErrorDecodingMiddleware()
        let authenticatedOpenAI = OpenAI(
            configuration: configuration,
            middlewares: [errorCheckingMiddleware]
        )
        return PreparedQueryResult(
            historyForLLM: historyForLLM,
            authenticatedOpenAI: authenticatedOpenAI,
            query: query,
            errorCheckingMiddleware: errorCheckingMiddleware
        )
    }

    private func streamResult(
        authenticatedOpenAI: OpenAI,
        query: ChatQuery,
        historyForLLMCount: Int,
        toolCount: Int,
        iteration: Int
    ) throws -> StreamedAssistantResult {
        streamRequestCounter += 1
        let streamID = "s\(streamRequestCounter)"
        typealias ToolCallParam = ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam
        typealias ReasoningDetail = ChatResult.Choice.Message.ReasoningDetail
        let accumulator = StreamingAccumulator()
        let semaphore = DispatchSemaphore(value: 0)
        let request = authenticatedOpenAI.chatsStream(query: query) { [accumulator, weak self] result in
            guard let self else { return }
            switch result {
            case .success(let chunk):
                if accumulator.beginStreamingIfNeeded() { _ = runHistory.beginAssistantStreaming() }
                for choice in chunk.choices {
                    if let deltaText = choice.delta.content, !deltaText.isEmpty {
                        accumulator.appendAssistantContent(deltaText)
                        runHistory.appendAssistantStreamingContent(deltaText)
                    }
                    if let details: [ReasoningDetail] = choice.delta.reasoningDetails, !details.isEmpty {
                        accumulator.appendReasoningDetails(details)
                    }
                    if let tcDeltas = choice.delta.toolCalls {
                        for tc in tcDeltas {
                            var name: String? = nil
                            var args: String? = nil
                            if let fn = tc.function { name = fn.name; args = fn.arguments }
                            accumulator.upsertToolCall(index: tc.index, id: tc.id, name: name, argumentsDelta: args)
                        }
                        let partial: [ToolCallParam] = accumulator.partialToolCalls()
                        if !partial.isEmpty { runHistory.updateAssistantStreamingToolCalls(partial) }
                    }
                }
            case .failure(let err):
                errorCapturer.capture(error: err)
                accumulator.setStreamError(err)
            }
        } completion: { [accumulator, weak self] err in
            guard let self else { return }
            if let err = err ?? accumulator.streamError {
                // MacPaw/OpenAI sometimes reports a non-2xx as a stream callback failure
                // and then cancels the underlying URLSession task, yielding NSURLErrorCancelled (-999)
                // in the completion. Preserve the *original* error if we already captured one.
                let nsError = err as NSError
                if nsError.domain == NSURLErrorDomain,
                   nsError.code == NSURLErrorCancelled,
                   accumulator.streamError != nil {
                    logger.error("LLM stream completion cancelled [\(streamID)] but preserving earlier stream error: \(String(describing: accumulator.streamError))")
                } else {
                    logger.error("LLM stream completion error [\(streamID)]: \(err)")
                    accumulator.setStreamError(err)
                }
                semaphore.signal()
            } else {
                let toolCalls = accumulator.finalizeBuiltToolCalls()
                let reasoningDetails = accumulator.reasoningDetails
                runHistory.finalizeAssistantStreaming(
                    toolCalls: toolCalls,
                    reasoningDetails: reasoningDetails.isEmpty ? nil : reasoningDetails
                )
                semaphore.signal()
            }
        }
        // we need to store request in class explicitly so it won't deallocate and cancel the stream
        self.ongoingChatRequest = request
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            logger.error("LLM stream wait timed out after \(timeout)s; clearing request reference")
        }
        self.ongoingChatRequest = nil
        if let err = accumulator.streamError { throw err }
        return StreamedAssistantResult(
            assistantContent: accumulator.assistantContent,
            toolCalls: accumulator.builtToolCalls,
            didStreamAssistantMessage: accumulator.didStreamAssistantMessage
        )
    }

    /// Reject tool calls without preceding comment to maintain agent decision quality
    private func shouldRejectToolCallsWithoutComment(streamed: StreamedAssistantResult) throws -> Bool {
        let assistantText = streamed.assistantContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // Allow tool calls if substantial comment provided (>20 chars)
        if assistantText.count > 20 {
            return false
        }

        logger.info("Tool calls rejected: Agent did not provide a comment before calling the tool")

        // Return error for each tool call
        for toolCall in streamed.toolCalls {
            let errorMessage = Prompts.generateMissingCommentError(toolName: toolCall.function.name)
            let errorResponse = ToolResponse(success: false, error: errorMessage)
            let jsonEncoder = JSONEncoder()
            let responseData = try jsonEncoder.encode(errorResponse)
            let responseString = String(data: responseData, encoding: .utf8) ?? "{\"success\": false}"
            runHistory.append(.tool(.init(content: .textContent(responseString), toolCallId: toolCall.id)))
        }

        return true
    }

    private func runToolCalls(
        _ toolCalls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam],
        executedCommands: inout [String],
        index: Int?,
        line: String?,
        iteration: Int,
        maxIterations: Int,
        stepUpdateCallback: (([String], Int?) -> Void)?
    ) throws -> ToolExecutionResult {
        var lastResultImage: PlatformImage? = nil
        var lastScreenshotURL: URL? = nil
        for toolCall in toolCalls {
            if isCancelled {
                logger.debug("Task was cancelled during tool call processing")
                throw CancellationError()
            }
            do {
                let command = try TargetCommand(from: toolCall.function)
                logger.debug("Successfully decoded command: \(command)")
                let commandString = command.toString()
                // Info log: iteration, line, and pretty action
                self.logPlannedAction(iteration: iteration, maxIterations: maxIterations, index: index, line: line, command: command)
                executedCommands.append(commandString)
                if let stepUpdateCallback = stepUpdateCallback {
                    let snapshot = executedCommands
                    DispatchQueue.main.async { stepUpdateCallback(snapshot, index) }
                }
                var toolResponseOpt: ToolResponse? = nil
                let group = DispatchGroup()
                group.enter()
                commandExecutorTools.executeCommand(command, errorCapturer: errorCapturer) { response in
                    toolResponseOpt = response
                    group.leave()
                }
                group.wait()
                guard let toolResponse = toolResponseOpt else { throw Error.unexpectedResponse }
                if let error = toolResponse.error { logger.debug("Tool response error: \(error)") }
                let (extractedJpegData, responseWithoutImage) = toolResponse.popImage()
                if let jpegData = extractedJpegData { lastResultImage = PlatformImage(data: jpegData) } else { logger.debug("No jpegData found in toolResponse") }
                if let imageJpegURL = toolResponse.imageJpegURL {
                    lastScreenshotURL = imageJpegURL
                    logScreenshotReference(imageJpegURL.absoluteString, context: "Tool response screenshot")
                }
                let jsonEncoder = JSONEncoder()
                let responseData = try jsonEncoder.encode(responseWithoutImage)
                let responseString = String(data: responseData, encoding: .utf8) ?? "{\"success\": false, \"error\": \"Failed to serialize response\"}"
                runHistory.append(.tool(.init(content: .textContent(responseString), toolCallId: toolCall.id)))
                logger.debug("Added tool response to conversation history")
            } catch let decodingError as CommandDecodingError {
                errorCapturer.capture(error: decodingError)
                logger.error("Command decoding error for \(toolCall.function.name): \(decodingError.localizedDescription)")
                let errorResponse = ToolResponse(success: false, error: decodingError.localizedDescription)
                let jsonEncoder = JSONEncoder()
                let responseData = try jsonEncoder.encode(errorResponse)
                let responseString = String(data: responseData, encoding: .utf8) ?? "{\"success\": false, \"error\": \"Failed to serialize error response\"}"
                runHistory.append(.tool(.init(content: .textContent(responseString), toolCallId: toolCall.id)))
                logger.debug("Added command decoding error response to conversation history")
            } catch {
                errorCapturer.capture(error: error)
                logger.error("Error processing tool call \(toolCall.function.name): \(error)")
                throw error
            }
        }
        return ToolExecutionResult(lastResultImage: lastResultImage, lastScreenshotURL: lastScreenshotURL)
    }

    private func handleScreenshotPostToolCalls(lastResultImage: PlatformImage?, lastScreenshotURL: URL?, useGeminiFix: Bool) throws {
        guard let finalImage = lastResultImage else { return }
        let imageData = finalImage.jpegData()
        do {
            let resolved = try resolveScreenshotReference(
                context: "Post-tool screenshot",
                imageData: imageData,
                imageURL: lastScreenshotURL
            )
            runHistory.appendUserWithScreenshot(
                textContent: try Prompts.screenshotMessage(),
                imageURL: resolved.referenceURLString,
                imageData: resolved.imageData,
                useGeminiFix: useGeminiFix
            )
            logger.debug("Added screenshot with both URL and base64 data to conversation history")
        } catch Error.screenshotWithoutS3URL {
            logger.error("Screenshot processing failed: S3 URL is required but not available")
            logger.error("This indicates a configuration or upload issue with the screenshot service")
            errorCapturer.capture(error: Error.screenshotWithoutS3URL)
            throw Error.screenshotWithoutS3URL
        } catch Error.missingBase64ImageData {
            logger.error("Screenshot processing failed: base64 data is required but not available")
            errorCapturer.capture(error: Error.missingBase64ImageData)
            throw Error.missingBase64ImageData
        }
    }

    // MARK: - Logging helpers
    private func logPlannedAction(iteration: Int, maxIterations: Int, index: Int?, line: String?, command: TargetCommand) {
        let lineLabel = index.map { "#\($0)" } ?? "NA"
        let lineText = line ?? ""
        let pretty = command.toString()
        let iterDisplay = String(format: "%02d", iteration + 1)
        logger.info("""
        Agent Iteration #\(iterDisplay)/\(maxIterations):
            Test Line   : \(lineLabel): \(lineText)
            Qalti Action: \(pretty)
        """)
    }

    private func containsValidJSON(_ text: String) -> Bool {
        do {
            _ = try extractJSON(from: text)
            return true
        } catch {
            return false
        }
    }

    private func extractJSON(from text: String) throws -> [String: Any] {
        // Try to find JSON in code blocks first
        if let jsonRange = text.range(of: "```json") {
            let afterJson = text[jsonRange.upperBound...]
            if let endRange = afterJson.range(of: "```") {
                let jsonString = afterJson[..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = jsonString.data(using: .utf8) {
                    return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                }
            }
        } else if let codeRange = text.range(of: "```") {
            let afterCode = text[codeRange.upperBound...]
            if let endRange = afterCode.range(of: "```") {
                let jsonString = afterCode[..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = jsonString.data(using: .utf8) {
                    return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                }
            }
        } else if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            let jsonString = String(text[start...end])
            if let data = jsonString.data(using: .utf8) {
                return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            }
        }
        throw NSError(domain: "IOSAgent", code: 1, userInfo: [NSLocalizedDescriptionKey: "No JSON found in response"])
    }
}
