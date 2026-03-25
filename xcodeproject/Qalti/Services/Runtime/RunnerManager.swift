import Foundation
import Logging

/// Manages the lifecycle of an iOS test runner process
class RunnerManager: Loggable {
    
    enum Status {
        case error(RunnerError)
        case waitingForUnlock
        case status(Update)
        
        enum RunnerError: Error, LocalizedError {
            case deviceNotTrusted
            case developerModeDisabled
            case timeout
            case authenticationCancelled
            case connectionError(Error)
            case certificateNotTrustedOnDevice
            case cancelled
            case xcodeBuildFailure(description: String)
            
            var errorDescription: String? {
                switch self {
                case .deviceNotTrusted:
                    return "Device is not trusted. Please trust this computer on your device."
                case .developerModeDisabled:
                    return "Developer mode is disabled. Please enable Developer Mode in Settings."
                case .timeout:
                    return "Connection to device timed out."
                case .authenticationCancelled:
                    return "Authentication was cancelled by user."
                case .connectionError(let error):
                    return "Connection error: \(error.localizedDescription)"
                case .certificateNotTrustedOnDevice:
                    return "The Developer App certificate isn’t trusted on this device. Open Settings → General → VPN & Device Management and trust your Developer App certificate, then retry."
                case .xcodeBuildFailure(let description):
                    return description
                case .cancelled:
                    return "Launch was cancelled"
                }
            }
        }
        
        enum Update {
            case waitingForConnection
            case deviceConnected
            case deviceUnlocked
            case testsRunning
        }
    }
    
    enum DeveloperModeStatus {
        case enabled
        case disabled
        case notTrusted
        case unknown
    }
    
    // MARK: - Private Properties
    
    private let deviceID: String
    private let isRealDevice: Bool
    private let idbManager: IdbManaging
    private let errorCapturer: ErrorCapturing
    private let runtimeUtils: IOSRuntimeUtils

    private var runnerProcess: Process?
    private var deviceConnectedTimer: Timer?
    private var outputPipe: Pipe?
    private var statusUpdateHandler: ((Status) -> Void)?
    private var deviceConnected = false
    private var restartOnExit = false
    private var restartAttemptCount = 0
    private var lastRestartAt: Date = .distantPast
    private var shouldStop = false
    private var seenTrustOrCodesignHint = false
    private var emittedFatalDeviceTrustError = false

    // MARK: - Initialization
    
    init(
        deviceID: String,
        isRealDevice: Bool,
        idbManager: IdbManaging,
        errorCapturer: ErrorCapturing
    ) {
        self.deviceID = deviceID
        self.isRealDevice = isRealDevice
        self.idbManager = idbManager
        self.errorCapturer = errorCapturer
        self.runtimeUtils = IOSRuntimeUtils(errorCapturer: errorCapturer)
    }

    deinit {
        stopRunner()
    }
    
    // MARK: - Public Methods
    
    /// Launches the test runner using xcodebuild with xctestrun file
    private var controlServerPort: Int = AppConstants.defaultControlPort
    private var screenshotServerPort: Int = AppConstants.defaultScreenshotPort

    func launchRunner(
        controlServerPort: Int = AppConstants.defaultControlPort,
        screenshotServerPort: Int = AppConstants.defaultScreenshotPort,
        statusUpdate: @escaping (Status) -> Void
    ) {
        shouldStop = false
        self.statusUpdateHandler = statusUpdate
        self.controlServerPort = controlServerPort
        self.screenshotServerPort = screenshotServerPort

        performPreFlightChecks { [weak self] result in
            guard let self else { return }

            if shouldStop {
                statusUpdate(.error(.cancelled))
            }

            switch result {
            case .failure(let error):
                statusUpdate(.error(error))
                return
            case .success:
                break
            }
            
            DispatchQueue.global().async {
                self.startXcodeBuildProcess()
            }
        }
    }
    
    /// Stops the running test runner process
    func stopRunner(forRestart: Bool = false) {
        shouldStop = !forRestart
        guard let process = runnerProcess else { return }
        if process.isRunning {
            logger.info("Stopping runner xcodebuild process")
            process.terminate()
        }

        if let outputPipe = outputPipe {
            outputPipe.fileHandleForReading.readabilityHandler = nil
        }
        outputPipe = nil
        
        deviceConnectedTimer?.invalidate()
        deviceConnectedTimer = nil

        deviceConnected = false
        runnerProcess = nil

        if !forRestart {
            restartOnExit = false
            restartAttemptCount = 0
        }

        if !forRestart {
            statusUpdateHandler = nil
        }
    }
    
    // MARK: - Private Methods
    
    /// Performs comprehensive pre-flight checks for real devices
    private func performPreFlightChecks(completion: @escaping (Result<Void, Status.RunnerError>) -> Void) {
        guard isRealDevice else {
            completion(.success(()))
            return
        }

        DispatchQueue.global().async { [weak self] in
            guard let self else {
                completion(.success(()))
                return
            }
            
            do {
                let targets = try idbManager.listTargets()
                let currentTarget = targets.first { $0.udid == self.deviceID }

                if let target = currentTarget {
                    if let error = self.checkForErrors(on: target) {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                } else {
                    completion(.failure(.timeout))
                }
            } catch {
                logger.error("Failed to check device status: \(error.localizedDescription)")
                completion(.failure(.connectionError(error)))
            }
        }
    }
    
    /// Determines if there's a critical error based on device details
    private func checkForErrors(on target: TargetInfo) -> Status.RunnerError? {
        guard let device = target.device else {
            return .timeout
        }
        
        if device.isPaired == false {
            return .deviceNotTrusted
        }

        let developerModeStatus = self.checkDeveloperModeStatus()

        switch developerModeStatus {
        case .notTrusted:
            return .deviceNotTrusted
        case .disabled:
            return .developerModeDisabled
        case .enabled, .unknown:
            return nil
        }
    }

    /// Checks developer mode status using devicectl command
    private func checkDeveloperModeStatus() -> DeveloperModeStatus {
        let detailsCommand = ["xcrun", "devicectl", "device", "info", "details", "--device", deviceID]
        let result = runtimeUtils.runConsoleCommand(command: detailsCommand)
        guard case .success(let deviceDetails) = result else { return .unknown }

        let lines = deviceDetails.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("developerModeStatus:") {
                if line.contains("enabled") {
                    return .enabled
                } else if line.contains("disabled") {
                    return .disabled
                }
            }
        }

        return .notTrusted
    }
    
    /// Starts the xcodebuild process after pre-flight checks pass
    private func startXcodeBuildProcess(cleanDerivedData: Bool = false) {
        do {
            stopRunner(forRestart: true)

            let destination: String = isRealDevice ? "platform=iOS,id=\(deviceID)" : "platform=iOS Simulator,id=\(deviceID)"
            killExistingXcodeBuildProcesses(for: destination)

            if shouldStop {
                statusUpdateHandler?(.error(.cancelled))
                return
            }

            let runnerCompilerEnv = EnvironmentSanitizer.sanitizedEnvironment(
                from: ProcessInfo.processInfo.environment,
                isSimulator: !isRealDevice,
                intendedUDID: deviceID
            )
            var finalEnv = runnerCompilerEnv
            finalEnv["CONTROL_SERVER_PORT"] = String(controlServerPort)
            finalEnv["SCREENSHOT_SERVER_PORT"] = String(screenshotServerPort)

            let build = try RunnerCompiler.buildAndRun(
                deviceID: deviceID,
                isRealDevice: isRealDevice,
                controlServerPort: controlServerPort,
                screenshotServerPort: screenshotServerPort,
                cleanDerivedData: cleanDerivedData,
                env: finalEnv
            )

            runnerProcess = build.process
            outputPipe = build.pipe
            restartOnExit = true
            attachTerminationHandler()
            
            setupCompletionTracking()
            startOutputMonitoring()
            setupDeviceConnectedTimer()

        } catch {
            logger.error("Error starting xcodebuild process: \(error.localizedDescription)")
            statusUpdateHandler?(.error(.xcodeBuildFailure(description: "Xcode build error: \(error.localizedDescription)")))
        }
    }

    /// Restarts xcodebuild if it exits unexpectedly, with simple backoff
    private func attachTerminationHandler() {
        runnerProcess?.terminationHandler = { [weak self] proc in
            guard let self else { return }

            if shouldStop {
                statusUpdateHandler?(.error(.cancelled))
                return
            }

            let status = Int(proc.terminationStatus)
            logger.debug("xcodebuild terminated (status=\(status)). restartOnExit=\(self.restartOnExit)")
            // Stop reading from the old pipe, if any
            self.outputPipe?.fileHandleForReading.readabilityHandler = nil
            guard self.restartOnExit else { return }
            // Throttle restarts: allow up to 3 within 1 hour
            let now = Date()
            if now.timeIntervalSince(self.lastRestartAt) > 3600 {
                self.restartAttemptCount = 0
            }
            self.lastRestartAt = now
            if self.restartAttemptCount >= 3 {
                logger.warning("xcodebuild restart suppressed to avoid loop (attempts=\(self.restartAttemptCount))")
                statusUpdateHandler?(.error(.xcodeBuildFailure(description: "Xcode exited unexpectedly (check logs)")))
                return
            }
            self.restartAttemptCount += 1
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startXcodeBuildProcess(cleanDerivedData: true)
            }
        }
    }
    
    /// Sets up completion tracking for the launch process
    private func setupCompletionTracking() {
        deviceConnected = false
        seenTrustOrCodesignHint = false
        emittedFatalDeviceTrustError = false
    }
    
    /// Sets up a 3-second timer to check for "Testing started" message
    private func setupDeviceConnectedTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.deviceConnectedTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                guard let self else { return }
                if !self.deviceConnected {
                    self.statusUpdateHandler?(.status(.waitingForConnection))
                }
            }
        }
    }

    /// Kills any existing xcodebuild processes targeting the same destination
    private func killExistingXcodeBuildProcesses(for destination: String) {
        let psResult = runtimeUtils.runConsoleCommand(command: ["ps", "aux"])
        guard case .success(let processes) = psResult else { return }

        let lines = processes.components(separatedBy: .newlines)
        let runtimeUtils = runtimeUtils

        for line in lines {
            if line.contains("xcodebuild") && line.contains(destination) {

                let components = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                if components.count >= 2, let pid = Int(components[1]) {
                    logger.debug("Killing existing xcodebuild process with PID: \(pid) for destination: \(destination)")
                    runtimeUtils.runConsoleCommand(command: ["kill", "-TERM", "\(pid)"])

                    DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                        runtimeUtils.runConsoleCommand(command: ["kill", "-KILL", "\(pid)"])
                    }
                }
            }
        }
    }

    /// Starts monitoring xcodebuild output using readabilityHandler
    private func startOutputMonitoring() {
        guard let outputPipe = outputPipe else { return }
        
        let fileHandle = outputPipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            guard let self else { return }

            let data = handle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    self.processOutputChunk(output)
                }
            }
        }
    }
    
    /// Processes a single output line and handles status updates
    private func processOutputLine(_ line: String) {
        if line.contains("Testing started") {
            deviceConnected = true
            deviceConnectedTimer?.invalidate()
            deviceConnectedTimer = nil
            statusUpdateHandler?(.status(.deviceConnected))
            return
        }
        
        if line.contains("Canceled by user") || line.contains("Authentication cancelled") {
            statusUpdateHandler?(.error(.authenticationCancelled))
            return
        }
        
        if line.contains("Server started on port") {
            statusUpdateHandler?(.status(.testsRunning))
            return
        }
        
        if line.contains("Timed out waiting for all destinations") {
            statusUpdateHandler?(.error(.timeout))
            return
        }
        
        if line.contains("Unlock") && line.contains("to Continue") {
            statusUpdateHandler?(.waitingForUnlock)
        } else if line.contains("Running tests...") {
            statusUpdateHandler?(.status(.deviceUnlocked))
        }
    }

    /// Processes a chunk of xcodebuild output to detect failures and surface clear guidance
    private func processOutputChunk(_ chunk: String) {
        let lines = chunk.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.contains("setsockopt") { continue }
            logger.debug("xcodebuild output: \(trimmed)")
            processOutputLine(trimmed)
        }

        guard isRealDevice else { return }

        // Aggregate-based failure parsing for trust/codesigning issues
        let lower = chunk.lowercased()
        let trustPhrases = [
            "verify that the developer app certificate",
            "profile has not been explicitly trusted",
            "invalid code signature",
            "inadequate entitlements",
            "request to open",
            "failed to install or launch the test runner"
        ]

        if trustPhrases.contains(where: { lower.contains($0) }) {
            seenTrustOrCodesignHint = true
            if !emittedFatalDeviceTrustError {
                emittedFatalDeviceTrustError = true
                restartOnExit = false
                shouldStop = true
                statusUpdateHandler?(.error(.certificateNotTrustedOnDevice))
                stopRunner(forRestart: false)
                return
            }
        }

        // Extract a concise outer/first underlying error if present
        if !emittedFatalDeviceTrustError, let concise = extractConciseFailureMessage(from: chunk) {
            statusUpdateHandler?(.error(.xcodeBuildFailure(description: concise)))
        }
    }

    /// Attempts to extract a concise error description from nested "Underlying Error" messages
    private func extractConciseFailureMessage(from text: String) -> String? {
        // Prefer the first occurrence after "Testing failed:" or outermost failure sentence
        let lines = text.components(separatedBy: .newlines)
        var capture = false
        var candidates: [String] = []

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.contains("Testing failed:") { capture = true; continue }
            if capture {
                // Stop if we reach the summary markers
                if line.contains("** TEST FAILED **") || line.contains("** TEST SUCCEEDED **") { break }
                candidates.append(line)
            }
        }

        // If we captured, try to find the first sentence or underlying error
        if !candidates.isEmpty {
            let joined = candidates.joined(separator: " ")
            if let underlyingRange = joined.range(of: "Underlying Error:") {
                // Capture from the first "Underlying Error:" up to the first ")" OR the next "Underlying Error:", whichever comes first
                let rest = joined[underlyingRange.upperBound...]
                let nextUnderlying = rest.range(of: "(Underlying Error:")?.lowerBound
                let nextParen = rest.firstIndex(of: ")")

                var endIndex: String.Index? = nil
                switch (nextParen, nextUnderlying) {
                case let (p?, u?):
                    endIndex = p < u ? p : u
                case let (p?, nil):
                    endIndex = p
                case let (nil, u?):
                    endIndex = u
                default:
                    endIndex = nil
                }

                let slice: Substring
                if let end = endIndex {
                    slice = rest[..<end]
                } else {
                    slice = rest
                }

                let snippet = slice
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !snippet.isEmpty { return String(snippet) }
            }

            // Fallback: first non-empty candidate line
            if let first = candidates.first { return first }
        }

        return nil
    }
} 
