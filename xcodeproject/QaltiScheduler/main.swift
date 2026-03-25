//
//  Created by Vyacheslav Gilevich on 25.08.2025.
//

import Foundation
import ArgumentParser
import Darwin
import Dispatch

struct QaltiScheduler: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "QaltiScheduler",
        abstract: "Clone and boot multiple iOS simulators and run Qalti CLI tests in parallel"
    )

    @Option(name: [.customShort("t"), .long], parsing: .upToNextOption, help: "Test files or directories (.test, .txt, .json or folders)")
    var tests: [String] = []

    @Option(name: [.customShort("d"), .long], help: "Simulator model (e.g., 'iPhone 16')")
    var deviceName: String?

    @Option(name: [.customShort("o"), .long], help: "iOS version (e.g., 18.2)")
    var os: String?

    @Option(name: [.customShort("w"), .long], help: "Number of parallel simulators")
    var workers: Int = 1

    @Option(name: [.long], help: "OpenRouter API key for Qalti CLI (or set OPENROUTER_API_KEY env var)")
    var token: String = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""

    @Flag(name: [.long], inversion: .prefixedNo, help: "Cleanup cloned simulators after run")
    var cleanup: Bool = true

    @Flag(name: [.customShort("v"), .long], help: "Enable verbose logging")
    var verbose: Bool = false

    // Real devices mode: when provided, skip simulator management and run over listed UDIDs
    @Flag(name: [.long], help: "Run tests over listed real device UDIDs instead of simulators")
    var realDevices: Bool = false

    @Option(name: [.long], parsing: .upToNextOption, help: "UDIDs of real devices to use (requires --real-devices)")
    var udids: [String] = []

    // Optional Qalti CLI arguments to pass through
    @Option(name: [.long], help: "AI model to use for Qalti CLI")
    var model: String?

    @Option(name: [.long], help: "Custom prompts directory for Qalti CLI")
    var promptsDir: String?

    @Option(name: [.long], help: "Report output file path for Qalti CLI")
    var reportDir: String?

    @Option(name: [.long], help: "Allure output directory for Qalti CLI")
    var allureDir: String?

    @Option(name: [.long], help: "Working directory for Qalti CLI bash commands")
    var workingDir: String?

    @Option(name: [.long], help: "App bundle path (.app or .ipa) to install before testing")
    var appPath: String?

    @Option(name: [.long], help: "Max iterations for Qalti CLI test run")
    var iterations: Int?

    @Flag(name: [.long], help: "Enable video recording for all test runs.")
    var recordVideo: Bool = false

    @Flag(name: [.long], help: "Automatically delete videos of successful test runs.")
    var deleteSuccessfulVideos: Bool = false

    @Option(name: [.long], help: "Stderr log level for Qalti CLI (trace|debug|info|notice|warning|error|critical)")
    var logLevel: String?

    func run() throws {
        // Collect test path strings from option, positionals, and possibly stdin
        var pathStrings = tests

        guard !pathStrings.isEmpty else {
            throw ValidationError("No test inputs provided. Pass files or directories, or pipe a list via stdin.")
        }

        let tokenTrimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tokenTrimmed.isEmpty else {
            throw ValidationError("No OpenRouter API key provided. Use --token or set OPENROUTER_API_KEY in the environment.")
        }

        // Resolve to concrete test files
        let allowedExts = ["test"]
        var resolved: [URL] = []
        for p in pathStrings {
            let url = URL(fileURLWithPath: p).standardizedFileURL
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    // expand directory
                    let files = try TestController.enumerateTests(in: url)
                    resolved.append(contentsOf: files)
                } else {
                    // single file; validate extension
                    let ext = url.pathExtension.lowercased()
                    if allowedExts.contains(ext) { resolved.append(url) }
                }
            }
        }

        // de-duplicate and sort
        let testsResolved = Array(Set(resolved)).sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }

        Log.setVerbose(verbose)
        Log.v("[Scheduler] Discovered \(testsResolved.count) test(s)")

        // Detect Qalti app before any simulator work
        guard let qaltiApp = SchedulerEnvironment.detectQaltiAppPath(verbose: verbose) else {
            throw ValidationError("Unable to locate Qalti app. Please ensure it is installed and accessible.")
        }
        let qalti = qaltiApp.appending(path: "Contents/MacOS/Qalti").path()

        var workerUDIDs: [String] = []
        var useRealDevices = false
        if realDevices {
            useRealDevices = true
            if deviceName != nil || os != nil {
                throw ValidationError("--real-devices cannot be combined with --device-name or --os")
            }
            if workers != 1 {
                throw ValidationError("--real-devices cannot be combined with --workers; number of workers is inferred from --udids")
            }
            guard !udids.isEmpty else {
                throw ValidationError("--real-devices requires at least one --udids value")
            }
            workerUDIDs = udids
            Log.v("[Scheduler] Using real devices: \(workerUDIDs.joined(separator: ", "))")
        } else {
            // Ensure xcrun present for simulator workflow
            if !udids.isEmpty {
                throw ValidationError("--udids was provided without --real-devices. Add --real-devices or remove --udids.")
            }
            guard FileManager.default.fileExists(atPath: "/usr/bin/xcrun") else {
                throw ValidationError("xcrun not found at /usr/bin/xcrun")
            }

            // Prepare simulators
            guard let deviceName = deviceName, let os = os else {
                throw ValidationError("Missing required options for simulators: --device-name and --os")
            }
            let (baseUDID, runtimeId) = try SimctlService.findOrCreateBaseSimulator(deviceName: deviceName, osVersion: os, verbose: verbose)
            Log.v("[Scheduler] Base simulator: \(baseUDID) @ \(runtimeId)")

            workerUDIDs = try SimctlService.cloneSimulators(sourceUDID: baseUDID, count: workers, deviceName: deviceName, osVersion: os, verbose: verbose)
            Log.v("[Scheduler] Cloned workers: \(workerUDIDs.joined(separator: ", "))")

            try SimctlService.bootSimulators(udids: workerUDIDs, verbose: verbose)
        }

        // Install termination cleanup (Ctrl+C etc.) after UDIDs are known
        let _terminationHandler = SignalTerminationHandler { [workerUDIDs, useRealDevices, cleanup, verbose] in
            Log.setVerbose(verbose)
            Log.v("[Scheduler] Caught termination signal. Spawning detached cleanup...")
            if !useRealDevices {
                SimctlService.launchDetachedCleanup(udids: workerUDIDs, cleanup: cleanup, verbose: verbose)
            }
            Darwin.exit(130)
        }

        // Dispatch tests greedily across workers
        // Run using controller/executors
        let controller = TestController(tests: testsResolved)
        let group = DispatchGroup()
        let udidToIndex: [String: Int] = Dictionary(uniqueKeysWithValues: workerUDIDs.enumerated().map { ($0.element, $0.offset) })

        for udid in workerUDIDs {
            let idx = udidToIndex[udid] ?? 0
            let executor = WorkerExecutor(
                qalti: qalti,
                token: tokenTrimmed,
                udid: udid,
                workerIndex: idx,
                useRealDevice: useRealDevices,
                model: model,
                promptsDir: promptsDir,
                reportDir: reportDir,
                allureDir: allureDir,
                workingDir: workingDir,
                appPath: appPath,
                iterations: iterations,
                recordVideo: recordVideo,
                deleteSuccessfulVideos: deleteSuccessfulVideos,
                controller: controller,
                verbose: verbose,
                cleanup: cleanup,
                logPrefix: "W\(idx)",
                logLevel: logLevel
            )
            executor.run(in: group)
        }

        group.wait()

        // Aggregate results
        let results = controller.resultsSnapshot()
        let failed = results.values.filter { $0 != 0 }.count
        let succeeded = results.count - failed
        print("[Scheduler] Completed. Success: \(succeeded), Failed: \(failed)")

        // After normal completion, clean up any orphaned QaltiWorker- simulators if no other scheduler is running
        SchedulerCleanup.performGlobalCleanupIfLeader(verbose: verbose)
        
        if failed > 0 { throw ExitCode(1) }
    }
}

QaltiScheduler.main()
