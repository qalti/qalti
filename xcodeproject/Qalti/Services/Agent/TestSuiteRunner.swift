import SwiftUI
import Foundation

@MainActor
final class TestSuiteRunner: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var suiteContext: TestSuiteRunContext?
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var testStatus: String?
    @Published private(set) var testError: String?
    @Published private(set) var isTestRunning: Bool = false
    @Published private(set) var hasRuntime: Bool = false
    @Published private(set) var currentRunHistory: RunHistory?

    private let credentialsService: CredentialsService
    private let idbManager: IdbManaging
    private let errorCapturer: ErrorCapturing

    private let fileLoader: TestFileLoader
    private let runsRoot: URL
    private let testsRoot: URL?

    private var results: [SuiteTestResult] = []
    private var currentModel: TestRunner.AvailableModel?
    private var currentTestStart: Date?
    private var currentRunner: TestRunner?
    private var runtime: IOSRuntime?
    private let runStorage: RunStorage
    let fileManager: FileSystemManaging
    var onTestWillStart: ((URL) -> Void)?

    private var recordVideoForCurrentSuite: Bool = false
    var deleteSuccessfulVideoForCurrentSuite: Bool = false

    init(
        documentsURL: URL,
        runStorage: RunStorage,
        credentialsService: CredentialsService,
        idbManager: IdbManaging,
        errorCapturer: ErrorCapturing,
        fileManager: FileSystemManaging = FileManager.default
    ) {
        let standardizedDocs = documentsURL.standardizedFileURL
        self.runsRoot = standardizedDocs.appendingPathComponent("Runs", isDirectory: true)
        self.testsRoot = standardizedDocs.appendingPathComponent("Tests", isDirectory: true)
        self.runStorage = runStorage
        self.credentialsService = credentialsService
        self.idbManager = idbManager
        self.errorCapturer = errorCapturer
        self.fileManager = fileManager

        self.fileLoader = TestFileLoader(errorCapturer: errorCapturer, fileManager: fileManager)
    }

    func setRuntime(_ runtime: IOSRuntime?) {
        self.runtime = runtime
        hasRuntime = runtime != nil
    }

    func presentUserError(_ message: String) {
        testError = message
        testStatus = nil
    }

    func clearUserMessages() {
        testError = nil
        statusMessage = nil
    }

    func stopCurrentRun() {
        guard let runner = currentRunner else { return }
        Task {
            await runner.stopTest()
        }
    }

    func runTests(
        at items: [URL],
        model: TestRunner.AvailableModel,
        recordVideo: Bool,
        deleteSuccessfulVideo: Bool
    ) {
        do {
            let plan = try RunPlan(items: items, runsRoot: runsRoot, fileManager: fileManager)
            guard ensureReadyForRun(isSuite: plan.isSuiteRun) else { return }

            recordVideoForCurrentSuite = recordVideo
            deleteSuccessfulVideoForCurrentSuite = deleteSuccessfulVideo

            startSuiteRun(with: plan, model: model)
        } catch {
            statusMessage = error.localizedDescription
            suiteContext = nil
            presentUserError(error.localizedDescription)
        }
    }

#if DEBUG
    /// **FOR TESTING ONLY:** Manually sets the `isRunning` state to simulate a test run in progress.
    /// This method is only available in DEBUG builds and should not be used in production code.
    func setIsRunningForTesting(_ running: Bool) {
        self.isRunning = running
    }
#endif
}

// MARK: - Suite lifecycle

private extension TestSuiteRunner {
    func ensureReadyForRun(isSuite: Bool) -> Bool {
        if isRunning {
            statusMessage = "Another suite run is already in progress."
            presentUserError("Another suite run is already in progress.")
            return false
        }

        if isTestRunning {
            let message = isSuite
                ? "Wait for the current test to finish before starting a suite."
                : "Finish the current test run before starting a new one."
            statusMessage = message
            presentUserError(message)
            return false
        }

        guard runtime != nil else {
            statusMessage = "No simulator or device is connected."
            presentUserError("No simulator")
            return false
        }

        if credentialsService.openRouterKey?.isEmpty ?? true {
            let message = IOSAgent.Error.missingOpenRouterKey.localizedDescription
            statusMessage = message
            presentUserError(message)
            return false
        }

        return true
    }

    func startSuiteRun(with plan: RunPlan, model: TestRunner.AvailableModel) {
        let tests = plan.tests
        let suiteFolder = plan.suiteFolder

        do {
            try fileManager.createDirectory(at: runsRoot, withIntermediateDirectories: true, attributes: nil)
            let preloadResult = preloadSuiteTests(from: tests)
            guard !preloadResult.loaded.isEmpty else {
                throw SuiteRunnerError.noRunnableTests(suiteFolder.lastPathComponent)
            }

            let context = TestSuiteRunContext(
                plan: plan,
                runsRoot: runsRoot,
                testsRoot: testsRoot,
                startedAt: Date()
            )
            if !plan.isSingleTest {
                try fileManager.createDirectory(at: context.runRoot, withIntermediateDirectories: true, attributes: nil)
            }

            prepareForSuite(
                context: context,
                tests: tests,
                preloadedTests: preloadResult.loaded,
                failedTests: preloadResult.failures,
                model: model
            )
            startNextTest()
        } catch {
            statusMessage = nil
            suiteContext = nil
            presentUserError(error.localizedDescription)
        }
    }

    func prepareForSuite(
        context: TestSuiteRunContext,
        tests: [URL],
        preloadedTests: [LoadedSuiteTest],
        failedTests: [(url: URL, reason: String)],
        model: TestRunner.AvailableModel
    ) {
        suiteContext = context
        setCurrentRunner(nil)

        var testsForRunStorage: [URL: String] = [:]
        for entry in preloadedTests {
            let key = normalized(entry.url)
            testsForRunStorage[key] = entry.test
        }
        runStorage.setSuiteTests(testsForRunStorage, queue: preloadedTests.map { $0.url })

        let pendingSuiteTests = runStorage.pendingTests
        runStorage.setActiveStatus(.queued, for: pendingSuiteTests)
        results = []
        currentModel = model
        isRunning = true
        totalCount = tests.count
        currentIndex = 0
        currentTestStart = nil
        statusMessage = "Running suite “\(context.suiteDisplayName)” (\(tests.count) test\(tests.count == 1 ? "" : "s"))."

        testStatus = "[Suite] Starting \(context.suiteDisplayName)"
        testError = nil

        for failure in failedTests {
            recordLoadFailure(for: failure.url, message: failure.reason)
        }
    }

    func finishSuite(cancelled: Bool, cancelledReason: String?) {
        guard isRunning else { return }
        setCurrentRunner(nil)

        if cancelled, !runStorage.pendingTests.isEmpty {
            recordRemainingPendingAsCancelled(reason: cancelledReason ?? "cancelled")
        }

        let summary = suiteSummary()
        if cancelled {
            testError = "Suite cancelled after \(results.count) test\(results.count == 1 ? "" : "s")."
            testStatus = nil
            statusMessage = "Suite cancelled."
        } else {
            if summary.failed == 0 {
                testError = nil
                testStatus = "Suite completed. Passed \(summary.passed) of \(results.count)."
            } else {
                testError = "\(summary.failed) test\(summary.failed == 1 ? "" : "s") failed."
                testStatus = "Suite completed with failures (passed \(summary.passed) of \(results.count))."
            }
            statusMessage = testStatus
        }

        isRunning = false
        currentModel = nil
        currentTestStart = nil
        suiteContext = nil
        currentRunHistory = nil
        totalCount = 0
        currentIndex = 0
        results.removeAll()
        runStorage.clear()
    }

    func suiteSummary() -> (passed: Int, failed: Int) {
        let passed = results.filter { $0.status == .success }.count
        let failed = results.filter { $0.status == .failure || $0.status == .loadFailed }.count
        return (passed, failed)
    }
}

// MARK: - Per-test lifecycle

extension TestSuiteRunner {
    func startNextTest() {
        guard isRunning else { return }

        if runStorage.pendingTests.isEmpty {
            finishSuite(cancelled: false, cancelledReason: nil)
            return
        }

        guard let context = suiteContext else {
            finishSuite(cancelled: true, cancelledReason: "Missing suite context.")
            return
        }

        guard let testURL = runStorage.popNextPendingTest() else {
            finishSuite(cancelled: false, cancelledReason: nil)
            return
        }
        currentIndex = results.count
        runStorage.setActiveStatus(.running, for: testURL)

        let normalizedURL = normalized(testURL)
        guard let test = runStorage.testContent(for: normalizedURL) else {
            recordLoadFailure(for: testURL, message: "Cached actions missing for test")
            startNextTest()
            return
        }

        guard TestFileLoader.hasRunnableContent(test) else {
            recordLoadFailure(for: testURL, message: TestFileLoader.emptyTestMessage)
            startNextTest()
            return
        }

        if let suiteIndex = runStorage.suiteIndex(for: normalizedURL) {
            runStorage.setCurrentTestIndex(suiteIndex)
            runStorage.updateTest(at: suiteIndex, testContent: test)
        }

        onTestWillStart?(testURL)

        // Create a fresh history instance for this run
        let runHistory = RunHistory()
        currentRunHistory = runHistory
        currentTestStart = Date()
        let displayName = context.relativePath(for: testURL)
        let prefix = "[Suite] \(results.count + 1)/\(totalCount)"
        testStatus = "\(prefix): \(displayName)"
        testError = nil

        let runner = makeTestRunner(context: context, runHistory: runHistory)
        setCurrentRunner(runner)

        Task {
            let completion = await runner.runTest(
                fileURL: testURL,
                model: currentModel ?? .gpt41,
                workingDirectory: nil
            )

            handleCompletion(completion)
        }
    }

    func handleCompletion(_ completion: TestRunner.RunCompletion) {
        setCurrentRunner(nil)
        guard isRunning else { return }

        let videoURL: URL?
        let testSucceeded: Bool

        switch completion {
        case .success(let summary):
            videoURL = summary.videoURL
            testSucceeded = true
            recordResult(summary: summary, status: .success, error: nil)
            startNextTest()
        case .failure(let summary, let error):
            videoURL = summary.videoURL
            testSucceeded = false
            recordResult(summary: summary, status: .failure, error: error)
            startNextTest()
        case .cancelled(let summary, let reason):
            videoURL = summary.videoURL
            testSucceeded = false
            recordResult(summary: summary, status: .cancelled, error: reason)
            finishSuite(cancelled: true, cancelledReason: reason)
        }

        if let videoURL = videoURL, testSucceeded, deleteSuccessfulVideoForCurrentSuite {
            do {
                try fileManager.removeItem(at: videoURL)
                print("[TestSuiteRunner] Deleted video of successful run: \(videoURL.lastPathComponent)")
            } catch {
                print("[TestSuiteRunner] Failed to delete video: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Result bookkeeping

private extension TestSuiteRunner {
    func recordResult(summary: TestRunner.RunSummary, status: SuiteTestResult.Status, error: String?) {
        let relativePath = summary.testFileURL.flatMap { suiteContext?.relativePath(for: $0) } ?? (summary.file ?? "Unknown test")
        let duration = currentTestStart.map { Date().timeIntervalSince($0) }

        appendResult(
            testURL: summary.testFileURL,
            relativePath: relativePath,
            status: status,
            error: error,
            duration: duration
        )
        currentTestStart = nil
        currentIndex = results.count
    }

    func recordLoadFailure(for url: URL, message: String) {
        let relativePath = suiteContext?.relativePath(for: url) ?? url.lastPathComponent
        appendResult(
            testURL: url,
            relativePath: relativePath,
            status: .loadFailed,
            error: message,
            duration: nil
        )
        currentIndex = results.count
        statusMessage = "Failed to load \(relativePath): \(message)"
    }

    func recordRemainingPendingAsCancelled(reason: String) {
        while let testURL = runStorage.popNextPendingTest() {
            let relativePath = suiteContext?.relativePath(for: testURL) ?? testURL.lastPathComponent
            appendResult(
                testURL: testURL,
                relativePath: relativePath,
                status: .cancelled,
                error: reason,
                duration: nil
            )
        }
        currentIndex = results.count
    }

    func runIndicatorState(for status: SuiteTestResult.Status) -> RunIndicatorState {
        switch status {
        case .success:
            return .success
        case .failure, .loadFailed:
            return .failed
        case .cancelled:
            return .cancelled
        }
    }

    func appendResult(
        testURL: URL?,
        relativePath: String,
        status: SuiteTestResult.Status,
        error: String?,
        duration: TimeInterval?
    ) {
        results.append(
            SuiteTestResult(
                testURL: testURL,
                relativePath: relativePath,
                status: status,
                error: error,
                duration: duration
            )
        )

        if let testURL {
            runStorage.setActiveStatus(runIndicatorState(for: status), for: testURL)
        }
    }
}

// MARK: - Helpers

private extension TestSuiteRunner {
    func normalized(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    func preloadSuiteTests(from tests: [URL]) -> (loaded: [LoadedSuiteTest], failures: [(url: URL, reason: String)]) {
        var loaded: [LoadedSuiteTest] = []
        var failures: [(url: URL, reason: String)] = []

        for url in tests {
            do {
                let loadResult = try fileLoader.load(from: url)
                if TestFileLoader.hasRunnableContent(loadResult.test) == false {
                    failures.append((url, TestFileLoader.emptyTestMessage))
                } else {
                    loaded.append(LoadedSuiteTest(url: url, test: loadResult.test))
                }
            } catch {
                failures.append((url, error.localizedDescription))
            }
        }

        return (loaded, failures)
    }

    func makeTestRunner(context: TestSuiteRunContext, runHistory: RunHistory) -> TestRunner {
        let fileManager = fileManager

        let runner = TestRunner(
            executionMode: .gui,
            runHistory: runHistory,
            recordVideo: recordVideoForCurrentSuite,
            credentialsService: credentialsService,
            idbManager: idbManager,
            errorCapturer: errorCapturer,
            fileManager: fileManager
        )
        runner.setRunStorage(runStorage)
        runner.setRuntime(runtime)
        runner.suiteContext = context
        return runner
    }

    func setCurrentRunner(_ runner: TestRunner?) {
        if currentRunner === runner {
            return
        }

        currentRunner?.onStatusChanged = nil
        currentRunner?.onErrorChanged = nil
        currentRunner?.onRunningChanged = nil

        currentRunner = runner

        guard let runner else {
            isTestRunning = false
            return
        }

        testStatus = runner.testStatus
        testError = runner.testError
        isTestRunning = runner.isRunning

        runner.onStatusChanged = { [weak self] status in
            self?.testStatus = status
        }

        runner.onErrorChanged = { [weak self] error in
            self?.testError = error
        }

        runner.onRunningChanged = { [weak self] isRunning in
            self?.isTestRunning = isRunning
        }
    }
}

// MARK: - Types

private extension TestSuiteRunner {
    struct LoadedSuiteTest {
        let url: URL
        let test: String
    }

    struct SuiteTestResult {
        enum Status {
            case success
            case failure
            case cancelled
            case loadFailed
        }

        let testURL: URL?
        let relativePath: String
        let status: Status
        let error: String?
        let duration: TimeInterval?
    }
}

protocol TestRunStateProviding: ObservableObject {
    var testStatus: String? { get }
    var testError: String? { get }
    var isTestRunning: Bool { get }
}

extension TestSuiteRunner: TestRunStateProviding {}
