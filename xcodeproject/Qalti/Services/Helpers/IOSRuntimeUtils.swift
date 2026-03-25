//
//  SystemUtils.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import Foundation
import Logging

class IOSRuntimeUtils: IOSRuntimeUtilsProviding {
    private let logger = Logger(label: "com.qalti.IOSRuntimeUtils")
    private let errorCapturer: ErrorCapturing

    struct BashScriptResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    init(errorCapturer: ErrorCapturing) {
        self.errorCapturer = errorCapturer
    }

    /// Runs a shell command and returns its stdout as a Result.
    /// - Parameters:
    ///   - command: The command and its arguments to execute.
    ///   - timeout: Optional timeout in seconds. If provided and the process doesn't finish in time,
    ///              the process will be terminated and a timeout error will be returned.
    @discardableResult
    func runConsoleCommand(command: [String], timeout: TimeInterval? = nil) -> Result<String, Error> {
#if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        var outputData = Data()
        let group = DispatchGroup()

        do {
            try process.run()
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Failed to run command: \(command.joined(separator: " "))\nError: \(error)")
            return .failure(error)
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            outputData = data
            group.leave()
        }

        var didTimeout = false
        if let timeout = timeout {
            if group.wait(timeout: .now() + timeout) == .timedOut {
                didTimeout = true
                if process.isRunning {
                    process.terminate()
                }
            } else {
                process.waitUntilExit()
            }
        } else {
            group.wait()
            process.waitUntilExit()
        }

        if didTimeout {
            return .failure(IOSRuntimeError.commandTimedOut)
        }

        return .success(String(data: outputData, encoding: .utf8) ?? "")
#else
        return .failure(IOSRuntimeError.unsupportedPlatform)
#endif
    }

    /// Checks if a given IP address is active on any local network interface.
    func isIPActiveLocally(_ ipAddress: String) -> Bool {
        let cleanIP = ipAddress.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "").dropLast(1)
        let command = ["/bin/sh", "-c", "ifconfig | grep -q '\(cleanIP)'"]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func getIphoneIP(for deviceID: String) -> Result<String, Error> {
        let detailsCommand = ["xcrun", "devicectl", "device", "info", "details", "--device", deviceID]

        switch runConsoleCommand(command: detailsCommand, timeout: 5.0) {
        case .success(let output):
            if let ipv6 = RegexUtils.matchRegex(pattern: "tunnelIPAddress:\\s*([a-fA-F0-9:.]+)", in: output) {
                if isIPActiveLocally(ipv6) {
                    return .success("[\(ipv6)]")
                } else {
                    return .failure(IOSRuntimeError.ghostTunnelDetected(ip: ipv6, udid: deviceID))
                }
            }
            return .failure(IOSRuntimeError.responseParseFailed(description: "Could not find tunnelIPAddress in devicectl output."))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Runs a bash script using /bin/bash -lc and returns stdout/stderr plus exit code.
    /// - Parameters:
    ///   - script: Full bash script contents.
    ///   - workingDirectory: Optional working directory to execute the script in.
    ///   - environment: Optional environment variables override.
    /// - Returns: A `BashScriptResult` with stdout, stderr, and exit code.
    /// - Throws: Any error thrown while launching the process.
    func runBashScript(
        _ script: String,
        workingDirectory: URL?,
        environment: [String: String]? = nil
    ) throws -> BashScriptResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", script]
        process.currentDirectoryURL = workingDirectory
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        stdoutPipe.fileHandleForReading.closeFile()
        stderrPipe.fileHandleForReading.closeFile()

        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

        return BashScriptResult(
            exitCode: process.terminationStatus,
            stdout: stdoutText.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
