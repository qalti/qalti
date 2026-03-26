import Foundation
import OpenAI
import Logging

enum ExitCode: Int32 {
    case success = 0
    case failure = 1
    case invalidUsage = 2
}

// MARK: - CLI Configuration
struct CLIConfiguration {
    struct DeviceSelection {
        enum DeviceType: String, CaseIterable {
            case simulator, real

            var description: String {
                switch self {
                case .simulator: return "iOS Simulator"
                case .real: return "Real iOS Device"
                }
            }
        }

        var udid: String?
        var deviceName: String?
        var osVersion: String?
        var type: DeviceType = .simulator
    }

    let testFile: URL
    let token: String
    let model: TestRunner.AvailableModel
    let promptsDir: URL?
    let testRunPath: URL?
    let testRunDir: URL?
    let allureDir: URL?
    let workingDirectory: URL?
    let device: DeviceSelection
    let controlPort: Int
    let screenshotPort: Int
    let appPath: URL?
    let maxIterations: Int
    let stderrLogLevel: Logger.Level
    let logPrefix: String?
    let recordVideo: Bool
    let deleteSuccessfulVideos: Bool
}

// MARK: - CLI Command Implementation
struct CLICommand {
    struct CLIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    enum ControlFlow: Error { case helpRequested }
    private static let logger = AppLogging.logger("CLI")

    /// The main synchronous entry point for the CLI command.
    static func run(
        dateProvider: DateProvider,
        idbManager: IdbManaging,
        errorCapturer: ErrorCapturing
    ) async -> ExitCode {
        let credentialsService = CredentialsService(errorCapturer: errorCapturer)

        do {
            let config = try performSetup()
            let runHistory = RunHistory()
            let startTime = dateProvider.now()

            // Kick off the main asynchronous logic.
            return await runAsyncMain(
                executionMode: .cli,
                config: config,
                runHistory: runHistory,
                startTime: startTime,
                dateProvider: dateProvider,
                credentialsService: credentialsService,
                idbManager: idbManager,
                errorCapturer: errorCapturer
            )

        } catch ControlFlow.helpRequested {
            printUsage()
            return .success
        } catch {
            let message = (error as? CLIError)?.message ?? error.localizedDescription
            fputs("Error: \(message)\n", stderr)
            printUsage()
            return .invalidUsage
        }
    }

    // MARK: - Helper Functions
    /// Loads a test file without hydrating any prior run history; CLI runs always start clean.
    static func loadTestFile(_ url: URL, fileLoader: TestFileLoader) throws -> String {
        logger.debug("Loading test file: \(url.lastPathComponent)")
        let result = try fileLoader.load(from: url)

        switch result.source {
        case .jsonRun:
            logger.debug("Loaded test run; CLI runs always start with a fresh history")
        case .jsonActions:
            logger.debug("Loaded actions from JSON")
        case .plainText:
            logger.debug("Loaded actions from text file")
        }

        return result.test
    }

    private static func setupDevice(
        _ selection: CLIConfiguration.DeviceSelection,
        controlServerPort: Int,
        screenshotServerPort: Int,
        idbManager: IdbManaging,
        errorCapturer: ErrorCapturing,
        environment: EnvironmentProviding = SystemEnvironmentProvider()
    ) throws -> IOSRuntime {
        if let envUDID = environment.deviceUDID,
           let selectedUDID = selection.udid,
           envUDID != selectedUDID {

            logger.warning("""
                [Qalti] Detected conflicting device specifications.
                        - Explicitly targeted UDID: \(selectedUDID)
                        - Environment variable DEVICE_UDID: \(envUDID)
                        --> Prioritizing the explicitly targeted device.
                """)
        }

        do {
            if let udid = selection.udid {
                logger.debug("Using device with UDID: \(udid)")

                if selection.type == .simulator {
                    let runtime = IOSRuntime(
                        simulatorID: udid,
                        controlServerPort: controlServerPort,
                        screenshotServerPort: screenshotServerPort,
                        idbManager: idbManager,
                        errorCapturer: errorCapturer
                    )
                    // Boot if needed
                    let targets = try idbManager.listTargets()
                    if let target = targets.first(where: { $0.udid == udid }),
                       target.state?.lowercased() != "booted" {
                        logger.debug("Booting simulator…")
                        try idbManager.bootSimulator(udid: udid, verify: true)
                    }
                    _ = try? idbManager.connect(udid: udid, isSimulator: true)
                    return runtime
                } else {
                    let runtime = try IOSRuntime.makeForRealDevice(
                        deviceID: udid,
                        controlServerPort: controlServerPort,
                        screenshotServerPort: screenshotServerPort,
                        idbManager: idbManager,
                        errorCapturer: errorCapturer
                    )
                    _ = try? idbManager.connect(udid: udid, isSimulator: false)
                    return runtime
                }
            } else {
                logger.debug("Searching for device: name=\(selection.deviceName ?? "any"), OS=\(selection.osVersion ?? "any"), type=\(selection.type)")

                let targets = try idbManager.listTargets()
                let preferredType: TargetType = selection.type == .simulator ? .simulator : .device

                guard let target = targets.first(where: { t in
                    t.targetType == preferredType &&
                    (selection.deviceName == nil || t.name == selection.deviceName!) &&
                    (selection.osVersion == nil || t.osVersion == selection.osVersion!)
                }) else {
                    let available = targets.filter { $0.targetType == preferredType }
                        .map { "\($0.name) (\($0.osVersion ?? "unknown OS"))" }
                        .joined(separator: ", ")
                    throw CLIError(message: "No matching \(selection.type) found. Available: \(available)")
                }

                logger.info("Found target: \(target.name) (\(target.osVersion ?? "unknown OS")) - \(target.udid)")

                let runtime = try IOSRuntime(
                    target: target,
                    controlServerPort: controlServerPort,
                    screenshotServerPort: screenshotServerPort,
                    idbManager: idbManager,
                    errorCapturer: errorCapturer
                )

                let isSim = target.targetType == .simulator

                if isSim && target.state?.lowercased() != "booted" {
                    logger.debug("Booting simulator…")
                    try idbManager.bootSimulator(udid: target.udid, verify: true)
                }

                _ = try? idbManager.connect(udid: target.udid, isSimulator: isSim)
                return runtime
            }
        } catch let error as IOSRuntimeError {
            if case .ghostTunnelDetected = error {
                let formattedMessage = CLIErrorFormatter.ghostTunnelErrorMessage(technicalDetail: error.localizedDescription)
                throw CLIError(message: formattedMessage)
            }
            throw CLIError(message: "Device setup failed (IOSRuntimeError): \(error.localizedDescription)")

        } catch {
            throw CLIError(message: "Device setup failed: \(error.localizedDescription)")
        }
    }

    private static func installApp(_ appPath: URL, on runtime: IOSRuntime, idbManager: IdbManaging) throws {
        logger.debug("Installing app: \(appPath.lastPathComponent)")

        let udid = runtime.deviceId

        let semaphore = DispatchSemaphore(value: 0)
        var caughtError: Error? = nil
        idbManager.installApp(appPath: appPath.path, udid: udid, makeDebuggable: false) { result in
            switch result {
            case .success(let bundleId):
                logger.debug("App installed successfully: \(bundleId)")
            case .failure(let error):
                caughtError = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let err = caughtError { throw err }
    }

    private static func startRunner(on runtime: IOSRuntime, controlPort: Int, screenshotPort: Int) async throws {
        logger.info("Starting runner (xcodebuild pipeline)...")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var completed = false

            runtime.runner.launchRunner(controlServerPort: controlPort, screenshotServerPort: screenshotPort) { status in
                if completed { return }

                switch status {
                case .error(let err):
                    completed = true
                    continuation.resume(throwing: err)
                case .status(let update):
                    if case .testsRunning = update {
                        logger.info("Runner started. Tests are running.")
                        completed = true
                        continuation.resume(returning: ())
                    } else {
                        switch update {
                        case .waitingForConnection:
                            logger.info("Waiting for connection...")
                        case .deviceConnected:
                            logger.info("Device connected, starting agent...")
                        case .deviceUnlocked:
                            logger.info("Device unlocked, initializing...")
                        case .testsRunning:
                            break
                        }
                    }
                case .waitingForUnlock:
                    logger.info("Waiting for device unlock...")
                }
            }
        }
    }

    // MARK: - Argument Parsing
    static func parseArguments(
        from arguments: [String],
        environment: EnvironmentProviding = SystemEnvironmentProvider()
    ) throws -> CLIConfiguration {
        // Check for help flags first
        if arguments.contains(where: { ["-help", "--help", "-h"].contains($0) }) {
            throw ControlFlow.helpRequested
        }

        guard let testFilePath = arguments.first(where: { !$0.hasPrefix("-") }) else {
            throw CLIError(message: "Missing test file path")
        }

        // Parse options
        var token = environment.allVariables["OPENROUTER_API_KEY"] ?? ""
        var model: TestRunner.AvailableModel? = nil
        var promptsDir: URL? = nil
        var testRunPath: URL? = nil
        var testRunDir: URL? = nil
        var allureDir: URL? = nil
        var workingDirectory: URL? = nil
        var device = CLIConfiguration.DeviceSelection()
        var appPath: URL? = nil
        var maxIterations = 50
        var logPrefix: String? = nil
        // Default level depends on build type
        var stderrLevel: Logger.Level = AppConstants.isDebug ? .debug : .info

        var controlPort: Int = AppConstants.defaultControlPort
        var screenshotPort: Int = AppConstants.defaultScreenshotPort
        var recordVideo = false
        var deleteSuccessfulVideos = false

        var i = 0
        while i < arguments.count {
            let arg = arguments[i]

            switch arg {
            case "--token", "-t":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for \(arg)") }
                token = arguments[i]

            case "--log-level":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --log-level") }
                let value = arguments[i].lowercased()
                switch value {
                case "trace": stderrLevel = .trace
                case "debug": stderrLevel = .debug
                case "info": stderrLevel = .info
                case "notice": stderrLevel = .notice
                case "warning": stderrLevel = .warning
                case "error": stderrLevel = .error
                case "critical": stderrLevel = .critical
                default:
                    throw CLIError(message: "Invalid --log-level '\(arguments[i])'. Allowed: trace, debug, info, notice, warning, error, critical")
                }

            case "--model":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --model") }
                let input = arguments[i]
                if let parsed = TestRunner.AvailableModel(from: input) {
                    model = parsed
                }

            case "--prompts-dir":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --prompts-dir") }
                promptsDir = URL(fileURLWithPath: arguments[i]).standardizedFileURL

            case "--report-path":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --report-path") }
                testRunPath = URL(fileURLWithPath: arguments[i]).standardizedFileURL

            case "--report-dir":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --report-dir") }
                testRunDir = URL(fileURLWithPath: arguments[i]).standardizedFileURL

            case "--allure-dir":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --allure-dir") }
                allureDir = URL(fileURLWithPath: arguments[i]).standardizedFileURL

            case "--working-dir":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --working-dir") }
                workingDirectory = URL(fileURLWithPath: arguments[i]).standardizedFileURL

            case "--log-prefix":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --log-prefix") }
                logPrefix = arguments[i]

            case "--device-name":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --device-name") }
                device.deviceName = arguments[i]

            case "--os":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --os") }
                device.osVersion = arguments[i]

            case "--type":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --type") }
                guard let deviceType = CLIConfiguration.DeviceSelection.DeviceType(rawValue: arguments[i].lowercased()) else {
                    throw CLIError(message: "Invalid device type '\(arguments[i])'. Must be 'simulator' or 'real'")
                }
                device.type = deviceType

            case "--udid":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --udid") }
                device.udid = arguments[i]

            case "--app-path":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --app-path") }
                appPath = URL(fileURLWithPath: arguments[i]).standardizedFileURL

            case "--iterations":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --iterations") }
                guard let iterations = Int(arguments[i]) else {
                    throw CLIError(message: "Invalid iterations value '\(arguments[i])'. Must be a number")
                }
                maxIterations = iterations

            case "--control-port":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --control-port") }
                guard let value = Int(arguments[i]) else {
                    throw CLIError(message: "Invalid --control-port value '\(arguments[i])'. Must be a number")
                }
                controlPort = value

            case "--screenshot-port":
                i += 1
                guard i < arguments.count else { throw CLIError(message: "Missing value for --screenshot-port") }
                guard let value = Int(arguments[i]) else {
                    throw CLIError(message: "Invalid --screenshot-port value '\(arguments[i])'. Must be a number")
                }
                screenshotPort = value

            case "--record-video":
                recordVideo = true

            case "--delete-successful-videos":
                deleteSuccessfulVideos = true

            default:
                if !arg.hasPrefix("-") {
                    // This is the test file path, skip it
                    break
                } else if arg == "-NSDocumentRevisionsDebugMode" {
                    break
                } else {
                    throw CLIError(message: "Unknown option: \(arg)")
                }
            }

            i += 1
        }

        // CLI requires an OpenRouter API key via --token or OPENROUTER_API_KEY.
        let tokenTrimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let missingToken = tokenTrimmed.isEmpty
        if missingToken {
            throw CLIError(message: "No OpenRouter API key provided. Use --token or set OPENROUTER_API_KEY in the environment.")
        }

        let testFileURL = URL(fileURLWithPath: testFilePath).standardizedFileURL

        if device.udid == nil {
            if let envUDID = environment.deviceUDID, !envUDID.isEmpty {
                device.udid = envUDID
            }
        }

        return CLIConfiguration(
            testFile: testFileURL,
            token: tokenTrimmed,
            model: model ?? .gpt41,
            promptsDir: promptsDir,
            testRunPath: testRunPath,
            testRunDir: testRunDir,
            allureDir: allureDir,
            workingDirectory: workingDirectory,
            device: device,
            controlPort: controlPort,
            screenshotPort: screenshotPort,
            appPath: appPath,
            maxIterations: maxIterations,
            stderrLogLevel: stderrLevel,
            logPrefix: logPrefix,
            recordVideo: recordVideo,
            deleteSuccessfulVideos: deleteSuccessfulVideos
        )
    }



    // MARK: - Private Helper Methods

    /// Handles all initial synchronous setup and argument parsing.
    private static func performSetup() throws -> CLIConfiguration {
        let allArgs = CommandLine.arguments

        // Find the "cli" subcommand and take everything after it.
        guard let cliIndex = allArgs.firstIndex(of: "cli") else {
            throw CLIError(message: "Internal error: 'cli' command not found in arguments")
        }
        let commandArgs = Array(allArgs.suffix(from: cliIndex + 1))

        let config = try parseArguments(from: commandArgs)
        let logFileName = config.logPrefix.flatMap { $0.isEmpty ? nil : "\($0)_qalti.log" }
        AppLogging.bootstrap(stderrLevel: config.stderrLogLevel, fileLevel: .debug, logFileName: logFileName)

        logger.info("Starting Qalti CLI…")
        logger.info("Test file: \(config.testFile.path)")
        logger.info("Model: \(config.model)")
        FileManager.temporaryDirectorySuffix = String(config.controlPort)
        return config
    }

    /// The core asynchronous logic for running the test and handling its result.
    @MainActor
    private static func runAsyncMain(
        executionMode: AppExecutionMode,
        config: CLIConfiguration,
        runHistory: RunHistory,
        startTime: Date,
        dateProvider: DateProvider,
        credentialsService: CredentialsService,
        idbManager: IdbManaging,
        errorCapturer: ErrorCapturing
    ) async -> ExitCode {
        var finalResult: TestRunner.RunCompletion?
        var executionError: Error?

        do {
            let fileLoader = TestFileLoader(errorCapturer: errorCapturer)
            let testContent = try loadTestFile(config.testFile, fileLoader: fileLoader)
            if !config.token.isEmpty {
                credentialsService.setApiKeyForCLI(config.token)
            }
            guard credentialsService.bearer != nil else {
                throw CLIError(message: "OpenRouter API key required.")
            }
            if let promptsDir = config.promptsDir {
                PromptLoader.setPromptsDirectoryOverride(promptsDir)
            }
            let fileManager = FileManager.default

            let runtime = try setupDevice(
                config.device,
                controlServerPort: config.controlPort,
                screenshotServerPort: config.screenshotPort,
                idbManager: idbManager,
                errorCapturer: errorCapturer
            )
            try await startRunner(on: runtime, controlPort: config.controlPort, screenshotPort: config.screenshotPort)
            defer { runtime.runner.stopRunner() }
            if let appPath = config.appPath { try installApp(appPath, on: runtime, idbManager: idbManager) }

            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Qalti")
            let runsRoot = documentsURL.appendingPathComponent("Runs")
            let plan = try RunPlan(items: [config.testFile], runsRoot: runsRoot)
            let context = TestSuiteRunContext(plan: plan, runsRoot: runsRoot, testsRoot: nil)


            let runner = TestRunner(
                executionMode: .cli,
                runHistory: runHistory,
                recordVideo: config.recordVideo,
                credentialsService: credentialsService,
                idbManager: idbManager,
                errorCapturer: errorCapturer,
                fileManager: fileManager,
                cliRecorderFactory: { outputURL in
                    return GRPCRecordingSession(
                        outputURL: outputURL,
                        idbManager: idbManager,
                        fileManager: fileManager
                    )
                }
            )

            runner.setRuntime(runtime)
            runner.setRunStorage(RunStorage())
            runner.suiteContext = context

            finalResult = await runner.runTest(fileURL: config.testFile, model: config.model, workingDirectory: config.workingDirectory)
        } catch {
            executionError = error
        }

        let exitCode = processFinalResult(
            config: config,
            result: finalResult,
            error: executionError,
            runHistory: runHistory,
            errorCapturer: errorCapturer,
            dateProvider: dateProvider
        )

        generateFinalReport(
            config: config,
            runHistory: runHistory,
            startTime: startTime,
            result: finalResult,
            error: executionError,
            errorCapturer: errorCapturer,
            dateProvider: dateProvider
        )

        return exitCode
    }

    /// Processes the final result of the test run to determine the exit code and log messages.
    @MainActor
    private static func processFinalResult(
        config: CLIConfiguration,
        result: TestRunner.RunCompletion?,
        error: Error?,
        runHistory: RunHistory,
        errorCapturer: ErrorCapturing,
        dateProvider: DateProvider
    ) -> ExitCode {
        if let error = error {
            let errorMessage = (error as? CLIError)?.message ?? (error as? IdbError)?.description ?? error.localizedDescription
            logger.error("Test execution failed: \(errorMessage)")
            if let testRunURL = buildTestRunURL(config: config, dateProvider: dateProvider) {
                let test = (try? String(contentsOf: config.testFile, encoding: .utf8)) ?? ""
                saveTestRun(
                    test: test,
                    to: testRunURL,
                    dateProvider: dateProvider,
                    success: false,
                    error: errorMessage,
                    runHistory: runHistory,
                    errorCapturer: errorCapturer,
                    fileManager: FileManager.default
                )
            }
            return .failure
        }

        if let result = result {
            switch result {
            case .success(let summary):
                logger.info("Test completed successfully.")
                if let url = summary.testRunURL { logger.info("Report saved to: \(url.path)") }
                if let videoURL = summary.videoURL, config.deleteSuccessfulVideos {
                    try? FileManager.default.removeItem(at: videoURL)
                    logger.info("Deleted video of successful run.")
                }
                return .success
            case .failure(_, let error):
                logger.error("Test failed: \(error)")
                return .failure
            case .cancelled(_, let reason):
                logger.error("Test cancelled: \(reason ?? "unknown reason")")
                return .failure
            }
        }

        logger.error("Test finished in an unknown state.")
        return .failure
    }

    /// Centralized function to generate the Allure report, regardless of outcome.
    private static func generateFinalReport(
        config: CLIConfiguration,
        runHistory: RunHistory,
        startTime: Date,
        result: TestRunner.RunCompletion?,
        error: Error?,
        errorCapturer: ErrorCapturing,
        dateProvider: DateProvider
    ) {
        guard let allureDir = config.allureDir else { return }

        let isSuccess: Bool
        let errorMessage: String?

        if let error = error {
            isSuccess = false
            errorMessage = (error as? CLIError)?.message ?? error.localizedDescription
        } else if let result = result {
            switch result {
            case .success:
                isSuccess = true
                errorMessage = nil
            case .failure(_, let err):
                isSuccess = false
                errorMessage = err
            case .cancelled(_, let reason):
                isSuccess = false
                errorMessage = "Cancelled: \(reason ?? "No reason given.")"
            }
        } else {
            isSuccess = false
            errorMessage = "Test finished in an unknown state."
        }

        do {
            let transcript = RunHistoryTranscript(history: runHistory, imageType: .base64)
            var parsedTestResult: TestResult? = nil
            if let lastMessage = transcript.messages.last?.message, case .assistant(let assistantParam) = lastMessage, case .textContent(let content) = assistantParam.content {
                let contentParser = ContentParser(errorCapturer: errorCapturer)
                parsedTestResult = contentParser.parseContent(content).testResult
            }

            try generateAllureReport(
                config: config,
                allureDir: allureDir,
                dateProvider: dateProvider,
                testStartTime: startTime,
                success: isSuccess,
                error: errorMessage,
                testResult: parsedTestResult,
                runHistory: runHistory
            )
        } catch {
            logger.error("Failed to generate Allure report: \(error.localizedDescription)")
        }
    }

    // MARK: - Report Generation

    static func defaultReportFilename(for config: CLIConfiguration, dateProvider: DateProvider) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy_MM_dd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let timestamp = formatter.string(from: dateProvider.now())
        return "\(config.testFile.deletingPathExtension().lastPathComponent)_\(timestamp).json"
    }

    static func buildTestRunURL(config: CLIConfiguration, dateProvider: DateProvider) -> URL? {
        let defaultFilename = defaultReportFilename(for: config, dateProvider: dateProvider)

        if let dir = config.testRunDir {
            return dir.appendingPathComponent(defaultFilename)
        }

        if let explicit = config.testRunPath {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: explicit.path, isDirectory: &isDirectory) {
                return isDirectory.boolValue ? explicit.appendingPathComponent(defaultFilename) : explicit
            } else {
                return explicit.hasDirectoryPath ? explicit.appendingPathComponent(defaultFilename) : explicit
            }
        }

        let reportsDir = config.testFile.deletingLastPathComponent().appendingPathComponent("reports")
        return reportsDir.appendingPathComponent(defaultFilename)
    }

    private static func generateAllureReport(
        config: CLIConfiguration,
        allureDir: URL,
        dateProvider: DateProvider,
        testStartTime: Date,
        success: Bool,
        error: String?,
        testResult: TestResult?,
        runHistory: RunHistory
    ) throws {
        logger.debug("Generating Allure report to: \(allureDir.path)")

        let testName = config.testFile.deletingPathExtension().lastPathComponent
        let testEndTime = dateProvider.now()

        let allureConverter = AllureConverter(
            outputDirectory: allureDir,
            testName: testName,
            testStartTime: testStartTime,
            testEndTime: testEndTime,
            testSuccess: success,
            errorMessage: error
        )

        // Convert using the enhanced chat history with timestamps
        try allureConverter.convertAndSave(
            from: runHistory.enhancedChatHistory,
            runSucceeded: success,
            runFailureReason: error,
            testResult: testResult
        )

        logger.debug("Allure report generated successfully")
    }

    private static func saveTestRun(
        test: String,
        to url: URL,
        dateProvider: DateProvider,
        success: Bool, error: String?,
        runHistory: RunHistory,
        errorCapturer: ErrorCapturing,
        fileManager: FileSystemManaging
    ) {
        let transcript = RunHistoryTranscript(history: runHistory, imageType: .base64)

        var parsedTestResult: TestResult? = nil
        if let lastMessage = transcript.messages.last?.message,
           case .assistant(let assistantParam) = lastMessage,
           case .textContent(let content) = assistantParam.content {
            let contentParser = ContentParser(errorCapturer: errorCapturer)
            let parsedContent = contentParser.parseContent(content)
            parsedTestResult = parsedContent.testResult
        }

        let testRunData = TestRunData(
            runSucceeded: success,
            runFailureReason: success ? nil : error,
            testResult: parsedTestResult,
            timestamp: dateProvider.now().ISO8601Format(),
            test: test,
            runHistory: transcript.messages
        )

        do {
            let encoder = JSONEncoder.withPreciseDateEncoding()
            let data = try encoder.encode(testRunData)

            // Create directory if needed
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

            try data.write(to: url)

            logger.debug("Test run saved to: \(url.path)")
        } catch {
            logger.error("Failed to save test run: \(error.localizedDescription)")
        }
    }

    // MARK: - Usage
    private static func printUsage() {
        let usage = """
        Qalti CLI - Run iOS tests from command line
        
        USAGE:
            qalti cli <test-file> --token OPENROUTER_API_KEY [options]
        
        ARGUMENTS:
            <test-file>                Path to test file (.test, .txt, or .json)
        
        OPTIONS:
            --app-path <path>          App bundle to install before testing (.app or .ipa)
            --token, -t <token>        OpenRouter API key (or set OPENROUTER_API_KEY env var).
            --model <model>            AI model to use (default: gpt-4.1)
                                       Available: gpt-4.1, gemini-2.5-pro, claude-4-sonnet, claude-3.5-sonnet,
                                       openrouter/free (free models)
            --prompts-dir <dir>        Custom prompts directory
            --report-path <file>       Output report path (default: ./reports/test_TIMESTAMP.json)
            --allure-dir <dir>         Generate Allure report files in specified directory
            --working-dir <dir>        Working directory for bash commands
            
        DEVICE SELECTION:
            --udid <udid>              Device UDID (takes precedence)
            --device-name <name>       Device name (e.g., "iPhone 16")
            --os <version>             OS version (e.g., "iOS 18.2")
            --type <type>              Device type: simulator (default) or real
        
        RECORDING OPTIONS:
            --record-video             Enable video recording of the test run.
            --delete-successful-videos Delete the video recording if the test run is successful.
            
        OTHER OPTIONS:
            --log-level <level>        Stderr log level: trace|debug|info|notice|warning|error|critical (default: info)
            --log-prefix <prefix>      Prefix the log file name (e.g., <prefix>_qalti.log)
            --iterations <n>           Max test iterations (default: 50)
            --help, -h                 Show this help
        
        EXAMPLES:
            # Basic usage
            qalti cli ./tests/login.test --token sk-or-v1-xxx
            
            # Run with video recording
            qalti cli ./tests/login.test --token sk-or-v1-xxx --record-video
            
            # Using UDID with app install
            qalti cli ./tests/app.test --udid 12345-67890 --app-path ./MyApp.app
            
            # Custom prompts and report location
            qalti cli ./tests/checkout.test --prompts-dir ./custom-prompts --report-path ./reports/checkout-run.json
        """
        print(usage)
    }
}
