import Foundation
import Darwin

final class WorkerExecutor {
    private let qalti: String
    private let token: String
    private let udid: String
    private let workerIndex: Int
    private let useRealDevice: Bool
    private let model: String?
    private let promptsDir: String?
    private let reportDir: String?
    private let allureDir: String?
    private let workingDir: String?
    private let appPath: String?
    private let iterations: Int?
    private let recordVideo: Bool
    private let deleteSuccessfulVideos: Bool
    private let controller: TestController
    private let verbose: Bool
    private let cleanup: Bool
    private let logPrefix: String?
    private let logLevel: String?

    init(
        qalti: String,
        token: String,
        udid: String,
        workerIndex: Int,
        useRealDevice: Bool,
        model: String?,
        promptsDir: String?,
        reportDir: String?,
        allureDir: String?,
        workingDir: String?,
        appPath: String?,
        iterations: Int?,
        recordVideo: Bool,
        deleteSuccessfulVideos: Bool,

        controller: TestController,
        verbose: Bool,
        cleanup: Bool,
        logPrefix: String? = nil,
        logLevel: String? = nil
    ) {
        self.qalti = qalti
        self.token = token
        self.udid = udid
        self.workerIndex = workerIndex
        self.useRealDevice = useRealDevice
        self.model = model
        self.promptsDir = promptsDir
        self.reportDir = reportDir
        self.allureDir = allureDir
        self.workingDir = workingDir
        self.appPath = appPath
        self.iterations = iterations
        self.recordVideo = recordVideo
        self.deleteSuccessfulVideos = deleteSuccessfulVideos

        self.controller = controller
        self.verbose = verbose
        self.cleanup = cleanup
        self.logPrefix = logPrefix
        self.logLevel = logLevel
    }

    func run(in group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                if !self.useRealDevice {
                    do {
                        try SimctlService.shutdownSimulators(udids: [self.udid], verbose: self.verbose)
                        if self.cleanup {
                            try SimctlService.deleteSimulators(udids: [self.udid], verbose: self.verbose)
                        } else if self.verbose {
                            print("[Scheduler] [W\(self.workerIndex)] Skipping deletion due to --no-cleanup")
                        }
                    } catch {
                        if self.verbose { print("[Scheduler] [W\(self.workerIndex)] Cleanup error: \(error)") }
                    }
                }
                group.leave()
            }

            while let test = self.controller.nextTest(for: self.udid) {
                self.runTest(test)
            }
        }
    }

    private func runTest(_ test: URL) {
        Log.v("[Scheduler] Starting: \(test.lastPathComponent) on \(udid)")

        let baseControlPort = 19000 + workerIndex * 10
        let ports = findAvailablePorts(startingAt: baseControlPort)
        let controlPort = ports.control
        let screenshotPort = ports.screenshot
        Log.v("[Scheduler] [W\(workerIndex)] Using \(controlPort),\(screenshotPort)")

        let (proc, outPipe, errPipe) = makeProcess(for: test, controlPort: controlPort, screenshotPort: screenshotPort)

        let prefix = "[W\(workerIndex)][\(test.lastPathComponent)]"
        var outBuffer = ""
        var errBuffer = ""
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            outBuffer += text
            while let range = outBuffer.range(of: "\n") {
                let line = String(outBuffer[..<range.lowerBound])
                print("\(prefix) \(line)")
                outBuffer.removeSubrange(outBuffer.startIndex...range.lowerBound)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            errBuffer += text
            while let range = errBuffer.range(of: "\n") {
                let line = String(errBuffer[..<range.lowerBound])
                fputs("\(prefix)\(line)\n", stderr)
                fflush(stderr)
                errBuffer.removeSubrange(errBuffer.startIndex...range.lowerBound)
            }
        }

        let finished = DispatchSemaphore(value: 0)
        proc.terminationHandler = { p in
            let code = p.terminationStatus
            Log.v("[Scheduler] Finished (code \(code)): \(test.lastPathComponent) on \(self.udid)")
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            if let data = try? outPipe.fileHandleForReading.readToEnd(), data.count > 0, let text = String(data: data, encoding: .utf8) {
                outBuffer += text
            }
            if let data = try? errPipe.fileHandleForReading.readToEnd(), data.count > 0, let text = String(data: data, encoding: .utf8) {
                errBuffer += text
            }

            if !outBuffer.isEmpty {
                print("\(prefix) \(outBuffer)")
            }
            if !errBuffer.isEmpty {
                fputs("\(prefix)\(errBuffer)\n", stderr)
                fflush(stderr)
            }

            self.controller.reportResult(for: test, code: code)
            finished.signal()
        }

        do { try proc.run() } catch {
            Log.v("[Scheduler] Failed to start Qalti for \(test.path): \(error.localizedDescription)")
            controller.reportResult(for: test, code: 1)
            return
        }

        finished.wait()
    }

    private func isPortAvailable(_ port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        if sock < 0 { return false }
        defer { close(sock) }

        var yes: Int32 = 1
        let optLen = socklen_t(MemoryLayout<Int32>.size)
        withUnsafePointer(to: &yes) { ptr in
            _ = setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, ptr, optLen)
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        var addrCopy = addr
        let result = withUnsafePointer(to: &addrCopy) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                bind(sock, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private func findAvailablePorts(startingAt startPort: Int) -> (control: Int, screenshot: Int) {
        var port = max(startPort, 1024)
        let lowerBound = 1024
        let upperBound = 65534
        let initial = port
        repeat {
            if isPortAvailable(port) && isPortAvailable(port + 1) {
                return (control: port, screenshot: port + 1)
            }
            port += 2
            if port > upperBound { port = lowerBound }
        } while port != initial

        Log.v("[Scheduler] [W\(workerIndex)] No free ports found in range; using \(startPort),\(startPort + 1) anyway")
        return (control: startPort, screenshot: startPort + 1)
    }

    private func makeProcess(for test: URL, controlPort: Int, screenshotPort: Int) -> (Process, Pipe, Pipe) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        var args: [String] = []
        args.append(qalti)
        args.append("cli")
        args.append(test.path)
        args.append(contentsOf: ["--token", token])
        if useRealDevice {
            args.append(contentsOf: ["--udid", udid, "--type", "real"]) // pin real device
        } else {
            args.append(contentsOf: ["--udid", udid, "--type", "simulator"]) // pin simulator
        }
        if let model = model { args.append(contentsOf: ["--model", model]) }
        if let promptsDir = promptsDir { args.append(contentsOf: ["--prompts-dir", promptsDir]) }
        if let reportDir = reportDir { args.append(contentsOf: ["--report-dir", reportDir]) }
        if let allureDir = allureDir { args.append(contentsOf: ["--allure-dir", allureDir]) }
        if let workingDir = workingDir { args.append(contentsOf: ["--working-dir", workingDir]) }
        if let appPath = appPath { args.append(contentsOf: ["--app-path", appPath]) }
        if let iterations = iterations { args.append(contentsOf: ["--iterations", String(iterations)]) }

        if recordVideo {
            args.append("--record-video")
        }
        if deleteSuccessfulVideos {
            args.append("--delete-successful-videos")
        }

        args.append(contentsOf: ["--control-port", String(controlPort)])
        args.append(contentsOf: ["--screenshot-port", String(screenshotPort)])
        if let logPrefix = logPrefix, !logPrefix.isEmpty {
            args.append(contentsOf: ["--log-prefix", logPrefix])
        }
        if let logLevel = logLevel, !logLevel.isEmpty {
            args.append(contentsOf: ["--log-level", logLevel])
        }

        proc.arguments = args
        let env = ProcessInfo.processInfo.environment
        proc.environment = env

        let stdoutPipe = Pipe(); let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        return (proc, stdoutPipe, stderrPipe)
    }
}
