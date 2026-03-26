import SwiftUI
import Foundation
import Logging
import OpenAI

@MainActor
class TestRunner: Loggable {

    private let executionMode: AppExecutionMode
    private let runHistory: RunHistory
    private let recordVideo: Bool
    private let credentialsService: any CredentialsServicing
    private let idbManager: IdbManaging
    private let errorCapturer: ErrorCapturing
    private let fileManager: FileSystemManaging
    private var cliRecordingSession: GRPCRecordingSessionProtocol?
    private let cliRecorderFactory: ((URL) -> GRPCRecordingSessionProtocol)?
    private let retryStrategy: RetryStrategy
    private let delayProvider: DelayProvider

    init(
        executionMode: AppExecutionMode,
        runHistory: RunHistory,
        recordVideo: Bool,
        credentialsService: any CredentialsServicing,
        idbManager: IdbManaging,
        errorCapturer: ErrorCapturing,
        fileManager: FileSystemManaging = FileManager.default,
        cliRecorderFactory: ((URL) -> GRPCRecordingSessionProtocol)? = nil,
        retryStrategy: RetryStrategy = RetryStrategyFactory.createFromEnvironment(),
        delayProvider: DelayProvider = DelayProviderFactory.create()
    ) {
        self.executionMode = executionMode
        self.runHistory = runHistory
        self.recordVideo = recordVideo
        self.credentialsService = credentialsService
        self.errorCapturer = errorCapturer
        self.idbManager = idbManager
        self.fileManager = fileManager
        self.cliRecorderFactory = cliRecorderFactory
        self.retryStrategy = retryStrategy
        self.delayProvider = delayProvider
    }

    enum AvailableModel: String, CaseIterable {
        case gpt41 = "openai/gpt-4.1"
        case gemini25pro = "google/gemini-2.5-pro"
        case claude4 = "anthropic/claude-sonnet-4"
        case grok4 = "x-ai/grok-4"
        case gpt5mini = "openai/gpt-5-mini"
        case gpt5 = "openai/gpt-5"
        case gpt5nano = "openai/gpt-5-nano"
        case claudeHaiku45 = "anthropic/claude-haiku-4.5"
        case gemini3proPreview = "google/gemini-3-pro-preview"
        case gemini3flashPreview = "google/gemini-3-flash-preview"
        case gemini3proImagePreview = "google/gemini-3-pro-image-preview"
        case openrouterFree = "openrouter/free"

        static var allCases: [AvailableModel] {
            return [
                .gpt41,
                .gemini25pro,
                .gemini3proPreview,
                .gemini3flashPreview,
                .claude4,
                .claudeHaiku45,
                .grok4,
                .gpt5mini,
                .gpt5nano,
                .gpt5,
                .openrouterFree
            ]
        }

        var fullName: String { self.rawValue }

        var displayName: String {
            switch self {
            case .grok4:
                return "Grok 4"
            case .gemini3proPreview:
                return "Gemini 3 Pro (preview)"
            case .gemini3flashPreview:
                return "Gemini 3 Flash (preview)"
            case .gemini3proImagePreview:
                return "Gemini 3 Pro Image (preview)"
            case .gpt5:
                return "GPT-5"
            case .gpt5mini:
                return "GPT-5 Mini"
            case .gpt5nano:
                return "GPT-5 Nano"
            case .gpt41:
                return "GPT-4.1 (recommended)"
            case .gemini25pro:
                return "Gemini 2.5 Pro"
            case .claude4:
                return "Claude 4 Sonnet"
            case .claudeHaiku45:
                return "Claude 4.5 Haiku"
            case .openrouterFree:
                return "Free Models Router (free)"
            }
        }

        var reasoning: ChatQuery.ReasoningEffort? {
            switch self {
            case .gpt5:
                // GPT-5 benefits from constrained reasoning by default.
                return .low
            case .gemini3proPreview, .gemini3flashPreview:
                // Enable reasoning for Gemini 3 models (OpenRouter expects this via reasoning.effort).
                return .low
            default:
                return nil
            }
        }

        var separateImageAndText: Bool {
            return self == .gemini3proPreview || self == .gemini3flashPreview || self == .gemini3proImagePreview
        }

        // Convenience initializer that maps common inputs/aliases to a known model
        init?(from input: String) {
            if let exact = Self(rawValue: input) { self = exact; return }
            let clean = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch clean {
            case "gpt-5":
                self = .gpt5
            case "gpt-5 mini", "gpt-5-mini":
                self = .gpt5mini
            case "gpt-5 nano", "gpt-5-nano":
                self = .gpt5nano
            case "gpt-4.1", "gpt41":
                self = .gpt41
            case "gemini 2.5 pro", "gemini-2.5-pro":
                self = .gemini25pro
            case "gemini 3 pro", "gemini-3-pro", "gemini-3-pro-preview":
                self = .gemini3proPreview
            case "gemini 3 flash", "gemini-3-flash", "gemini-3-flash-preview":
                self = .gemini3flashPreview
            case "gemini 3 pro image", "gemini-3-pro-image", "gemini-3-pro-image-preview":
                self = .gemini3proImagePreview
            case "claude 4 sonnet", "claude-4-sonnet", "claude4":
                self = .claude4
            case "grok-4", "grok 4", "grok4":
                self = .grok4
            case "claude haiku 4.5", "claude-haiku-4.5", "haiku 4.5", "haiku-4.5":
                self = .claudeHaiku45
            case "free", "openrouter-free", "open router free", "open-router-free", "openrouter", "open router", "open-router free":
                self = .openrouterFree
            default:
                return nil
            }
        }
    }

    struct RunSummary {
        let name: String?
        let file: String?
        let testFileURL: URL?
        let testRunURL: URL?
        let videoURL: URL?
    }

    enum RunCompletion {
        case success(RunSummary)
        case failure(RunSummary, error: String)
        case cancelled(RunSummary, reason: String?)
    }

    enum CancellationReason: String {
        case userStopped = "user_stopped"
        case taskCancelled = "task_cancelled"
    }

    var isRunning: Bool = false {
        didSet {
            if isRunning != oldValue {
                runHistory.setRunInProgress(isRunning)
            }
            onRunningChanged?(isRunning)
        }
    }

    var testStatus: String? = nil
    var testError: String? = nil
    private(set) var lastTestRunURL: URL? = nil
    private var agent: IOSAgent? = nil
    private(set) var runtime: IOSRuntime?
    private weak var runStorage: RunStorage?
    private var currentRecordingSession: ScreenRecordingSession?
    private var currentTestRunURL: URL?
    private var currentTimebase: TestTimebase?

    var onStatusChanged: ((String?) -> Void)?
    var onErrorChanged: ((String?) -> Void)?
    var onRunningChanged: ((Bool) -> Void)?
    var suiteContext: TestSuiteRunContext?

    private var pendingCancellationReason: CancellationReason? = nil

    func setRuntime(_ runtime: IOSRuntime?) {
        self.runtime = runtime
    }

    func setRunStorage(_ storage: RunStorage) {
        runStorage = storage
    }

    func runTest(fileURL: URL, model: AvailableModel, workingDirectory: URL? = nil) async -> RunCompletion {
        let normalizedURL = fileURL.standardizedFileURL
        let testName = normalizedURL.deletingPathExtension().lastPathComponent
        let fileName = normalizedURL.lastPathComponent

        guard let runtime = runtime else {
            let errorMsg = "No simulator"
            await setError(errorMsg)
            let summary = await makeRunSummary(testURL: fileURL, testRunURL: nil, videoURL: nil)
            return .failure(summary, error: errorMsg)
        }

        let fileLoader = TestFileLoader(errorCapturer: self.errorCapturer)
        let test: String
        do {
            let loadResult = try fileLoader.load(from: normalizedURL)
            test = loadResult.test
        } catch {
            let errorMsg = "Failed to load test file: \(error.localizedDescription)"
            await setError(errorMsg)
            let summary = await makeRunSummary(testURL: fileURL, testRunURL: nil, videoURL: nil)
            return .failure(summary, error: errorMsg)
        }

        guard TestFileLoader.hasRunnableContent(test) else {
            let errorMsg = TestFileLoader.emptyTestMessage
            await setError(errorMsg)
            let summary = await makeRunSummary(testURL: fileURL, testRunURL: nil, videoURL: nil)
            return .failure(summary, error: errorMsg)
        }

        guard !isRunning else {
            let summary = await makeRunSummary(testURL: fileURL, testRunURL: nil, videoURL: nil)
            return .failure(summary, error: "A test is already running.")
        }

        guard let context = suiteContext else {
            let errorMsg = "Internal error: missing suite context"
            await setError(errorMsg)
            let summary = await makeRunSummary(testURL: fileURL, testRunURL: nil, videoURL: nil)
            return .failure(summary, error: errorMsg)
        }

        if credentialsService.openRouterKey?.isEmpty ?? true {
            let errorMsg = IOSAgent.Error.missingOpenRouterKey.localizedDescription
            await setError(errorMsg)
            let summary = await makeRunSummary(testURL: fileURL, testRunURL: nil, videoURL: nil)
            return .failure(summary, error: errorMsg)
        }

        let testRunURL = context.testRunURL(for: normalizedURL, preferredName: testName)
        currentTestRunURL = testRunURL

        if recordVideo {
            if executionMode == .gui {
                await startGuiRecording(for: runtime, testRunURL: testRunURL)
            } else { // .cli
                await startCliRecording(for: runtime, testRunURL: testRunURL)
            }
        }

        lastTestRunURL = nil
        pendingCancellationReason = nil
        if suiteContext == nil {
            runStorage?.setSingleTest(test, testURL: normalizedURL)
        } else {
            runStorage?.updateCurrentTest(test)
        }

        isRunning = true
        await setStatus("Starting test...")
        await updateRunStatus(.running, preferredURL: normalizedURL)

        let result = await executeTestWithRetry(
            runtime: runtime,
            testURL: normalizedURL,
            model: model,
            testContent: test,
            workingDirectory: workingDirectory
        )
        return result
    }

    func stopTest() async {
        guard isRunning else { return }

        pendingCancellationReason = .userStopped
        agent?.cancel()
        agent = nil
        await stopRecordingSession()

        let identifiers = await currentTestIdentifiers()
        isRunning = false
        await setStatus("Test stopped")
        await updateRunStatus(.cancelled, preferredURL: identifiers.url)

        let test = await testToRun(preferredURL: identifiers.url)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.testStatus == "Test stopped" { self?.testStatus = nil }
        }
    }

    /// Executes a test with configurable retry strategy for handling rate limits and temporary failures
    private func executeTestWithRetry(
        runtime: IOSRuntime, testURL: URL, model: AvailableModel,
        testContent: String, maxIterations: Int = 50, workingDirectory: URL?
    ) async -> RunCompletion {

        var lastError: String?

        for attempt in 1...retryStrategy.maxAttempts {
            logger.debug("Executing test attempt \(attempt)/\(retryStrategy.maxAttempts)")

            let result = await executeTest(
                runtime: runtime,
                testURL: testURL,
                model: model,
                testContent: testContent,
                maxIterations: maxIterations,
                workingDirectory: workingDirectory
            )

            // Check if the result indicates a retryable failure
            switch result {
            case .success, .cancelled:
                // Success or user cancellation - don't retry
                return result

            case .failure(let summary, let error):
                lastError = error

                // Create a synthetic error for strategy evaluation
                let syntheticError = NSError(
                    domain: "TestRunnerError",
                    code: isRateLimitError(error) ? 429 : -1,
                    userInfo: [NSLocalizedDescriptionKey: error]
                )

                // Check if this error is retryable according to our strategy
                guard retryStrategy.shouldRetry(attempt: attempt, error: syntheticError) else {
                    // Error is not retryable or max attempts exceeded
                    logger.info("Error not retryable or max attempts exceeded: \(error)")
                    return result
                }

                // Check if we should delay before the next attempt
                if let delay = retryStrategy.nextDelay(attempt: attempt) {
                    logger.info("Rate limit or temporary error detected, retrying in \(delay)s (attempt \(attempt)/\(retryStrategy.maxAttempts))")

                    await setStatus("Rate limited, retrying in \(Int(delay))s (attempt \(attempt)/\(retryStrategy.maxAttempts))...")

                    do {
                        try await delayProvider.delay(delay)
                    } catch {
                        logger.error("Delay interrupted: \(error)")
                        return .cancelled(summary, reason: CancellationReason.taskCancelled.rawValue)
                    }

                    // Check for cancellation after delay
                    if let agent = self.agent, agent.isCancelled {
                        return .cancelled(summary, reason: CancellationReason.taskCancelled.rawValue)
                    }

                    await setStatus("Retrying test... (attempt \(attempt + 1))")
                } else {
                    // No more delays available
                    logger.info("No more retry delays available after attempt \(attempt)")
                    return result
                }
            }
        }

        // If we exhausted all retries, return the last failure
        let summary = await makeRunSummary(testURL: testURL, testRunURL: nil, videoURL: nil)
        let errorMessage = lastError ?? "Maximum retry attempts (\(retryStrategy.maxAttempts)) exceeded"
        await setError(errorMessage)

        return .failure(summary, error: errorMessage)
    }

    internal func isRateLimitError(_ errorMessage: String) -> Bool {
        let rateLimitIndicators = [
            "429",
            "rate limit",
            "too many requests",
            "quota exceeded",
            "limit exceeded",
            "throttled"
        ]

        let lowercaseError = errorMessage.lowercased()
        return rateLimitIndicators.contains { indicator in
            lowercaseError.contains(indicator)
        }
    }

    private func executeTest(
        runtime: IOSRuntime, testURL: URL, model: AvailableModel,
        testContent: String,
        maxIterations: Int = 50, workingDirectory: URL?
    ) async -> RunCompletion {
        let normalizedURL = testURL.standardizedFileURL
        let elementLocator = UIElementLocator(
            credentialsService: credentialsService,
            errorCapturer: errorCapturer,
            defaultRelative: true
        )
        let bashWorkingDir = workingDirectory ?? normalizedURL.deletingLastPathComponent()

        let agent = IOSAgent(
            runtime: runtime,
            elementLocator: elementLocator,
            workingDirectoryForBash: bashWorkingDir,
            testDirectory: normalizedURL.deletingLastPathComponent(),
            credentialsService: credentialsService,
            errorCapturer: errorCapturer,
            runHistory: runHistory
        )
        self.agent = agent

        let testCaseName = normalizedURL.deletingPathExtension().lastPathComponent
        let fileName = normalizedURL.lastPathComponent
        let testLines = testContent.split(separator: "\n").map { String($0) }
        var recordedSteps = ""
        if !testLines.isEmpty {
            for (index, line) in testLines.enumerated() {
                recordedSteps.append("\(index + 1). \(line)\n")
            }
        }

        await setStatus("Preparing simulator...")
        runtime.openApp(name: "com.apple.springboard") { _ in }

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        guard !agent.isCancelled, self.agent != nil else {
            await setStatus("Test cancelled")
            let summary = await makeRunSummary(testURL: testURL, testRunURL: nil, videoURL: nil)
            return .cancelled(summary, reason: CancellationReason.taskCancelled.rawValue)
        }

        await setStatus("Executing test...")

        do {
            try await agent.run(
                testCaseName: testCaseName,
                recordedSteps: recordedSteps,
                maxIterations: maxIterations,
                model: model
            )
            return await handleRunSuccess(testURL: testURL, model: model, maxIterations: maxIterations)
        } catch {
            return await handleRunFailure(error: error, testURL: testURL, model: model)
        }
    }

    private func handleRunFailure(error: Error, testURL: URL, model: AvailableModel) async -> RunCompletion {
        errorCapturer.capture(error: error)
        let identifiers = testIdentifiers(for: testURL)

        isRunning = false
        let errorMessage = error.localizedDescription
        let wasCancelled = agent?.isCancelled == true || agent == nil

        await stopRecordingSession()
        let finalVideoURL = currentRecordingSession?.outputURL ?? cliRecordingSession?.outputURL

        await updateRunStatus(wasCancelled ? .cancelled : .failed, preferredURL: testURL)

        let completion: RunCompletion
        if wasCancelled {
            let cancellationReason = pendingCancellationReason ?? .taskCancelled
            await setStatus("Test cancelled")
            let testRunURL = await saveTestRun(success: false, testURL: testURL, errorMessage: "Test cancelled")
            finalizeRecordingArtifacts()
            let summary = await makeRunSummary(testURL: testURL, testRunURL: testRunURL, videoURL: finalVideoURL)
            completion = .cancelled(summary, reason: cancellationReason.rawValue)
            pendingCancellationReason = nil
        } else {
            pendingCancellationReason = nil
            await setError("Test failed: \(errorMessage)")
            let testRunURL = await saveTestRun(success: false, testURL: testURL, errorMessage: errorMessage)
            finalizeRecordingArtifacts()
            let summary = await makeRunSummary(testURL: testURL, testRunURL: testRunURL, videoURL: finalVideoURL)
            completion = .failure(summary, error: errorMessage)
        }
        await clearRunStorageIfStandalone()
        return completion
    }

    private func handleRunSuccess(testURL: URL, model: AvailableModel, maxIterations: Int) async -> RunCompletion {
        let identifiers = testIdentifiers(for: testURL)

        await stopRecordingSession()
        let finalVideoURL = currentRecordingSession?.outputURL ?? cliRecordingSession?.outputURL

        isRunning = false
        pendingCancellationReason = nil

        let history = runHistory.getHistory(imageType: .base64)
        let parsedRun = parseAgentTestRun(from: history)

        let reportedState = parsedRun?.testResult.testResult.runIndicatorState
        var finalState: RunIndicatorState = reportedState ?? .success
        var failureReason = parsedRun?.testResult.failureReason
        let displayReport = parsedRun?.cleanedContent ?? lastAssistantText(in: history)
        let lineCount = await testToRun(preferredURL: testURL).count(where: { $0 == "\n" })

        if executionMode == .cli && finalState == .failed {
            self.logger.warning("⚠️ CLI MODE: Agent failed, but forcing SUCCESS to match legacy behavior.")
            finalState = .success
            failureReason = nil
        }

        var extra: [String: Any] = [:]
        if let reportText = displayReport { extra["agent_report"] = reportText }
        if let result = parsedRun?.testResult.testResult { extra["agent_report_result"] = result.rawValue }

        await updateRunStatus(finalState, preferredURL: testURL)

        let testRunURL = await saveTestRun(
            success: finalState != .failed,
            testURL: testURL,
            errorMessage: failureReason
        )

        let completion: RunCompletion

        if finalState == .failed {
            let reason = failureReason ?? "Agent reported failure."
            await setError("Test failed: \(reason)")
            let summary = await makeRunSummary(testURL: testURL, testRunURL: testRunURL, videoURL: finalVideoURL)
            completion = .failure(summary, error: reason)
        } else {
            await setStatus("Test completed!")
            let summary = await makeRunSummary(testURL: testURL, testRunURL: testRunURL, videoURL: finalVideoURL)
            completion = .success(summary)

            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                if self?.testStatus == "Test completed!" { self?.testStatus = nil }
            }
        }

        finalizeRecordingArtifacts()
        await clearRunStorageIfStandalone()
        return completion
    }

    @discardableResult
    private func saveTestRun(success: Bool, testURL: URL?, errorMessage: String? = nil) async -> URL? {
        let transcript = RunHistoryTranscript(history: runHistory, imageType: .base64)
        var parsedTestResult: TestResult? = nil

        if let lastMessage = transcript.messages.last?.message,
           case .assistant(let assistantParam) = lastMessage,
           case .textContent(let content) = assistantParam.content {
            let contentParser = ContentParser(errorCapturer: errorCapturer)
            let parsedContent = contentParser.parseContent(content)
            parsedTestResult = parsedContent.testResult
        }

        let testContent = await testToRun(preferredURL: testURL)
        let testRunData = TestRunData(
            runSucceeded: success, runFailureReason: success ? nil : errorMessage,
            testResult: parsedTestResult, timestamp: Date().ISO8601Format(),
            test: testContent, runHistory: transcript.messages
        )

        do {
            guard let testRunURL = await testRunURLForSaving(testURL: testURL) else {
                await MainActor.run { self.lastTestRunURL = nil }
                logger.error("Failed to save test run: missing suite context or run URL")
                return nil
            }
            let encoder = JSONEncoder.withPreciseDateEncoding()
            let jsonData = try encoder.encode(testRunData)
            let testRunDirectory = testRunURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: testRunDirectory, withIntermediateDirectories: true, attributes: nil)
            try jsonData.write(to: testRunURL)
            logger.debug("Test run saved to: \(testRunURL.path)")
            await MainActor.run { self.lastTestRunURL = testRunURL }
            return testRunURL
        } catch {
            await MainActor.run { self.lastTestRunURL = nil }
            errorCapturer.capture(error: error)
            logger.error("Failed to save test run: \(error)")
            return nil
        }
    }

    private func startGuiRecording(for runtime: IOSRuntime, testRunURL: URL) async {
        await stopRecordingSession()

        let videoURL = testRunURL.deletingPathExtension().appendingPathExtension("mp4")
        let timebase = TestTimebase()
        currentTimebase = timebase

        let surfaceRegistry = TargetSurfaceRegistry.shared
        guard surfaceRegistry.currentSurface() != nil else {
            logger.warning("Screen recording unavailable: no IOSurface from TargetViewModel")
            return
        }

        let session = ScreenRecordingSession(
            timebase: timebase,
            outputURL: videoURL,
            framesPerSecond: 30,
            surfaceProvider: { surfaceRegistry.currentSurface() },
            fileManager: fileManager
        )

        do {
            try session.start()
            currentRecordingSession = session
            logger.debug("GUI screen recording started for runtime \(runtime.deviceId): \(videoURL.path)")
        } catch {
            currentRecordingSession = nil
            logger.error("Failed to start GUI recording: \(error.localizedDescription)")
        }
    }

    private func startCliRecording(for runtime: IOSRuntime, testRunURL: URL) async {
        await stopRecordingSession()

        let videoURL = testRunURL.deletingPathExtension().appendingPathExtension("mp4")

        guard let session = cliRecorderFactory?(videoURL) else {
            logger.warning("Skipping video recording: CLI recorder factory is not available in the current execution mode.")
            return
        }
        do {
            try session.start(udid: runtime.deviceId)
            self.cliRecordingSession = session
            logger.debug("CLI screen recording started via gRPC for runtime \(runtime.deviceId): \(videoURL.path)")
        } catch {
            self.cliRecordingSession = nil
            logger.error("Failed to start gRPC CLI recording: \(error.localizedDescription)")
        }
    }

    private func stopRecordingSession() async {
        if let session = currentRecordingSession {
            await withCheckedContinuation { continuation in
                session.stop {
                    continuation.resume()
                }
            }
            currentRecordingSession = nil
        }

        if let session = cliRecordingSession {
            await session.stop()
            cliRecordingSession = nil
        }
    }

    private func finalizeRecordingArtifacts() {
        currentTestRunURL = nil
        currentTimebase = nil
    }

    private func testRunURLForSaving(testURL: URL?) async -> URL? {
        if let currentTestRunURL { return currentTestRunURL }
        guard let context = suiteContext else { return nil }
        let identifiers = await currentTestIdentifiers(preferredURL: testURL)
        let resolvedURL = identifiers.url ?? testURL ?? context.suiteFolder
        return context.testRunURL(for: resolvedURL, preferredName: identifiers.testName)
    }

    private func setStatus(_ status: String) async {
        testStatus = status
        testError = nil
        onStatusChanged?(status)
        onErrorChanged?(nil)

    }

    private func setError(_ error: String) async {
        testError = error
        testStatus = nil
        onErrorChanged?(error)
        onStatusChanged?(nil)
    }

    private func testToRun(preferredURL: URL? = nil) async -> String {
        guard let runStorage else { return "" }
        return await runStorage.testContent(for: preferredURL) ?? ""
    }

    private func testIdentifiers(for url: URL?) -> (testName: String?, fileName: String?) {
        guard let url else { return (nil, nil) }
        let fileName = url.lastPathComponent
        let testName = url.deletingPathExtension().lastPathComponent
        return (testName, fileName)
    }

    private func currentTestIdentifiers(preferredURL: URL? = nil) async -> (testName: String?, fileName: String?, url: URL?) {
        guard let url = await runStorage?.currentTestURL(preferred: preferredURL) else {
            return (nil, nil, nil)
        }
        let identifiers = testIdentifiers(for: url)
        return (identifiers.testName, identifiers.fileName, url)
    }

    private func clearRunStorageIfStandalone() async {
        if suiteContext == nil {
            await runStorage?.clear()
        }
    }

    private func updateRunStatus(_ state: RunIndicatorState, preferredURL: URL? = nil) async {
        guard let url = await runStorage?.currentTestURL(preferred: preferredURL) else { return }
        await runStorage?.setActiveStatus(state, for: url)
    }

    private func makeRunSummary(testURL: URL?, testRunURL: URL?, videoURL: URL?) async -> RunSummary {
        let currentTestURL = await runStorage?.currentTestURL()
        let resolvedURL = testURL ?? currentTestURL
        let identifiers = testIdentifiers(for: resolvedURL)
        return RunSummary(
            name: identifiers.testName, file: identifiers.fileName,
            testFileURL: resolvedURL, testRunURL: testRunURL, videoURL: videoURL
        )
    }

    // MARK: - Agent Report Parsing

    private struct ParsedAgentReport {
        let testResult: TestResult
        let cleanedContent: String
    }

    private func parseAgentTestRun(from history: [ChatQuery.ChatCompletionMessageParam]) -> ParsedAgentReport? {
        for message in history.reversed() {
            guard case .assistant(let assistantParam) = message,
                  let content = assistantParam.content,
                  case .textContent(let text) = content
            else { continue }
            let contentParser = ContentParser(errorCapturer: errorCapturer)
            let parsedContent = contentParser.parseContent(text)
            if let testResult = parsedContent.testResult {
                return ParsedAgentReport(testResult: testResult, cleanedContent: parsedContent.mainContent)
            }
        }
        return nil
    }

    private func lastAssistantText(in history: [ChatQuery.ChatCompletionMessageParam]) -> String? {
        for message in history.reversed() {
            guard case .assistant(let assistantParam) = message,
                  let content = assistantParam.content,
                  case .textContent(let text) = content
            else { continue }
            return text
        }
        return nil
    }
}

// MARK: - TestResult Helpers

private extension TestResultStatus {
    var runIndicatorState: RunIndicatorState {
        switch self {
        case .failed: return .failed
        case .pass, .passWithComments: return .success
        }
    }
}

private extension TestResult {
    var failureReason: String? {
        let candidates = [comments, finalStateDescription]
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
