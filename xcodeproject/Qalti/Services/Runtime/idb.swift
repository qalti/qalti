import Foundation
import Logging
import GRPC
import NIOCore
import NIOPosix
import IOSurface

public enum IdbError: Error, CustomStringConvertible {
    case commandFailed(code: Int, output: String)
    case invalidResponse(message: String)
    case connectionFailed(message: String)
    case notConnected(udid: String)
    case alreadyConnected(udid: String)
    case videoStreamFailed(message: String)

    public var description: String {
        switch self {
        case .commandFailed(let code, let output):
            return "IDB command failed with code \(code): \(output)"
        case .invalidResponse(let message):
            return "Invalid IDB response: \(message)"
        case .connectionFailed(let message):
            return "IDB connection failed: \(message)"
        case .notConnected(let udid):
            return "Not connected to target with UDID: \(udid)"
        case .alreadyConnected(let udid):
            return "Already connected to target with UDID: \(udid)"
        case .videoStreamFailed(let message):
            return "Video stream failed: \(message)"
        }
    }

    public var localizedDescription: String {
        return description
    }
}

public enum ButtonType {
    case applePay
    case home
    case lock
    case sideButton
    case siri
    
    /// Initializes ButtonType from a string with robust normalization
    /// Strips spaces, quotes, underscores, dashes, and converts to lowercase for comparison
    public init?(from string: String) {
        let normalized = string
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        
        switch normalized {
        case "applepay":
            self = .applePay
        case "home":
            self = .home
        case "lock":
            self = .lock
        case "sidebutton":
            self = .sideButton
        case "siri":
            self = .siri
        default:
            return nil
        }
    }
    
    fileprivate var hidButtonType: Idb_HIDEvent.HIDButtonType {
        switch self {
        case .applePay: return .applePay
        case .home: return .home
        case .lock: return .lock
        case .sideButton: return .sideButton
        case .siri: return .siri
        }
    }
}

public class IdbManager: Loggable {
    private let companionPath: String
    private var activeConnections: [String: ConnectionDetails] = [:]

    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 4)
    private let errorCapturer: ErrorCapturing

    struct ConnectionDetails {
        let process: Process?
        let client: Idb_CompanionServiceAsyncClient
        let port: Int
        let stdoutPipe: Pipe?
        let stderrPipe: Pipe?
    }

    public init(companionPath: String? = nil, errorCapturer: ErrorCapturing) {
        self.errorCapturer = errorCapturer

        // Default to the bundled idb_companion if not specified
        if let providedPath = companionPath {
            self.companionPath = providedPath
        } else {
            let bundle = Bundle.main
            let resourcesPath = bundle.resourcePath ?? ""
            let defaultPath = resourcesPath + "/simulatorbinaries/bin/idb_companion"
            self.companionPath = defaultPath
        }
    }


    /// Lists available simulator targets
    public func listTargets() throws -> [TargetInfo] {
        let output = try runCompanionCommand(["--list", "1"])

        var targets: [TargetInfo] = []
        for line in output.split(separator: "\n") where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let target = try? JSONDecoder().decode(TargetInfo.self, from: data) else {
                continue
            }
            targets.append(target)
        }
        return targets
    }

    /// Boots a simulator
    public func bootSimulator(udid: String, verify: Bool) throws {
        _ = try runCompanionCommand([
            "--boot", udid,
            "--verify-booted", verify ? "1" : "0"
        ])
    }

    /// Shuts down a simulator
    public func shutdownSimulator(udid: String) throws {
        _ = try runCompanionCommand(["--shutdown", udid])
    }

    /// Erases a simulator
    public func eraseSimulator(udid: String) throws {
        _ = try runCompanionCommand(["--erase", udid])
    }

    /// Checks if the connection is already present
    public func isConnected(udid: String) -> Bool {
        activeConnections[udid] != nil
    }

    /// Connects to a companion for a given simulator
    public func connect(udid: String, isSimulator: Bool) throws -> Int {
        if activeConnections[udid] != nil {
            throw IdbError.alreadyConnected(udid: udid)
        }

        let (process, port, stdoutPipe, stderrPipe) = try startCompanionServer(udid: udid, isSimulator: isSimulator)

        let channel = try GRPCChannelPool.with(
          target: .host("::1", port: port),
          transportSecurity: .plaintext,
          eventLoopGroup: eventLoopGroup
        )

        let companionClient = Idb_CompanionServiceAsyncClient(channel: channel)

        // Store connection details
        activeConnections[udid] = ConnectionDetails(
            process: process,
            client: companionClient,
            port: port,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )

        // Check and clean up testmanagerd data
        cleanupTestManagerData(udid: udid)
        
        return port
    }

    /// Cleans up testmanagerd data for a given simulator
    public func cleanupTestManagerData(udid: String) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let testDataPath = homeDir.appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(udid)/data/Containers/Data/InternalDaemon")
        
        do {
            let containerDirs = try FileManager.default.contentsOfDirectory(
                at: testDataPath, 
                includingPropertiesForKeys: nil
            )
            
            for containerDir in containerDirs {
                let metadataPath = containerDir.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                
                guard FileManager.default.fileExists(atPath: metadataPath.path) else {
                    continue
                }
                
                guard let plistData = try? Data(contentsOf: metadataPath),
                      let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                      let identifier = plist["MCMMetadataIdentifier"] as? String,
                      identifier == "com.apple.testmanagerd" 
                else {
                    continue
                }
                
                // This is a testmanagerd directory, delete it
                do {
                    try FileManager.default.removeItem(at: containerDir)
                    logger.debug("Cleaned up testmanagerd data at: \(containerDir.path)")
                } catch {
                    logger.warning("Failed to clean up testmanagerd data: \(error.localizedDescription)")
                }
            }
        } catch {
            logger.warning("Failed to access testmanagerd directories: \(error.localizedDescription)")
        }
    }

    func record(udid: String) throws -> RecordCall {
        guard let connection = activeConnections[udid] else {
            throw IdbError.notConnected(udid: udid)
        }

        let grpcCall = connection.client.makeRecordCall()
        return GRPCRecordCallAdapter(call: grpcCall)
    }

    /// Disconnects from a companion
    public func disconnect(udid: String) throws {
        guard let connection = activeConnections.removeValue(forKey: udid), connection.process?.isRunning == true else {
            throw IdbError.notConnected(udid: udid)
        }

        // Clean up log reading handlers
        connection.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        connection.stderrPipe?.fileHandleForReading.readabilityHandler = nil
        
        connection.process?.terminate()
        connection.process?.waitUntilExit()
    }

    /// Starts a companion server for a simulator
    private func startCompanionServer(udid: String, isSimulator: Bool, port: Int = 0) throws -> (Process, Int, Pipe, Pipe) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let finalPort: Int

        if port == 0 {
            finalPort = 18000 + Int(arc4random_uniform(1000))
        } else {
            finalPort = port
        }

        process.executableURL = URL(fileURLWithPath: companionPath)
        process.arguments = ["--udid", udid, "--grpc-port", String(finalPort), "--log-level", "info"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.setSanitizedEnvironment(isSimulator: isSimulator, intendedUDID: udid)

        // Set up non-blocking log reading
        setupLogReading(udid: udid, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)

        // will run killall idb_companion here: CloseAppOnWindowCloseManager
        try process.run()

        return (process, finalPort, stdoutPipe, stderrPipe)
    }
    
    /// Sets up non-blocking log reading from the companion process
    private func setupLogReading(udid: String, stdoutPipe: Pipe, stderrPipe: Pipe) {
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        
        // Setup stdout reading
        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        logger.debug("[udid:\(udid)] STDOUT: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }
                }
            }
        }
        
        // Setup stderr reading
        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        logger.debug("[udid:\(udid)] STDERR: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }
                }
            }
        }
    }

    /// Runs a command directly with idb_companion
    private func runCompanionCommand(_ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: companionPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        process.setSanitizedEnvironment(
            isSimulator: true,
            intendedUDID: "" // Not relevant, as the key will be removed
        )

        try process.run()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            return output
        } else {
            throw IdbError.commandFailed(
                code: Int(process.terminationStatus),
                output: output
            )
        }
    }
}

extension IdbManager {

    public func installApp(
        appPath: String, 
        udid: String, 
        makeDebuggable: Bool = false,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let connection = activeConnections[udid] else {
            completion(.failure(IdbError.notConnected(udid: udid)))
            return
        }

        Task {
            do {
                var requestStream: [Idb_InstallRequest] = [.with { $0.destination = .app }]
                if makeDebuggable {
                    requestStream.append(.with { $0.makeDebuggable = true })
                }
                requestStream.append(.with { request in request.payload = .with { $0.source = .filePath(appPath) } })

                var bundleID: String? = nil

                let stream = connection.client.install(requestStream)
                for try await response in stream {
                    if response.progress != 0 {
                        logger.debug("install progress: \(response.progress)%")
                    }
                    if !response.name.isEmpty {
                        bundleID = response.name
                    }
                }

                if let bundleID {
                    completion(.success(bundleID))
                } else {
                    completion(.failure(IdbError.invalidResponse(message: "No bundle ID in install response")))
                }
            } catch {
                errorCapturer.capture(error: error)
                completion(.failure(error))
            }
        }
    }

    func installXCTest(
        testBundlePath: String,
        udid: String,
        skipSigning: Bool = false,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let connection = activeConnections[udid] else {
            completion(.failure(IdbError.notConnected(udid: udid)))
            return
        }

        Task {
            do {
                var requestStream: [Idb_InstallRequest] = [.with { $0.destination = .xctest }]
                if skipSigning {
                    requestStream.append(.with { $0.skipSigningBundles = true })
                }
                requestStream.append(.with { request in
                    request.payload = .with { $0.source = .filePath(testBundlePath) }
                })

                var bundleID: String? = nil

                let stream = connection.client.install(requestStream)
                for try await response in stream {
                    if response.progress != 0 {
                        logger.debug("install progress: \(response.progress)%")
                    }
                    if !response.name.isEmpty {
                        bundleID = response.name
                    }
                }

                if let bundleID {
                    completion(.success(bundleID))
                } else {
                    completion(.failure(IdbError.invalidResponse(message: "No bundle ID in install response")))
                }
            } catch {
                errorCapturer.capture(error: error)
                completion(.failure(error))
            }
        }
    }

    func runUITest(
        testBundleId: String,
        appBundleId: String,
        testHostAppBundleId: String,
        udid: String,
        environmentVariables: [String: String] = [:],
        completion: @escaping (Error?) -> Void
    ) {
        guard let connection = activeConnections[udid] else {
            completion(IdbError.notConnected(udid: udid))
            return
        }

        Task {
            do {
                let request = Idb_XctestRunRequest.with { request in
                    request.testBundleID = testBundleId
                    request.collectLogs = false
                    request.reportAttachments = false
                    request.reportActivities = false
                    request.timeout = 365 * 24 * 60 * 60 * 1000
                    request.mode = Idb_XctestRunRequest.Mode.with { mode in
                        mode.mode = .ui(
                            Idb_XctestRunRequest.UI.with { uiMode in
                                uiMode.appBundleID = appBundleId
                                uiMode.testHostAppBundleID = testHostAppBundleId
                            }
                        )
                    }

                    request.environment = environmentVariables
                }

                let stream = connection.client.xctest_run(request)
                for try await response in stream {
                    if response.status == .running {
                        completion(nil)
                        return
                    }
                }
                
                // If we reached here without finding a running status
                completion(IdbError.invalidResponse(message: "Test didn't enter running state"))
            } catch {
                errorCapturer.capture(error: error)
                completion(error)
            }
        }
    }

    func touch(udid: String, x: Int32, y: Int32, up: Bool = false) throws {
        guard let connection = activeConnections[udid] else {
            throw IdbError.notConnected(udid: udid)
        }

        let request = Idb_HIDEvent.with { event in
            event.event = .press(Idb_HIDEvent.HIDPress.with { press in
                press.action = .with { action in
                    action.action = .touch(Idb_HIDEvent.HIDTouch.with { touch in
                        touch.point = .with { point in
                            point.x = Double(x)
                            point.y = Double(y)
                        }
                    })
                }
                press.direction = up ? .up : .down
            })
            
        }

        let semaphore = DispatchSemaphore(value: 0)
        var taskError: Error?

        Task {
            do {
                _ = try await connection.client.hid([request])
            } catch {
                errorCapturer.capture(error: error)
                taskError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = taskError {
            throw error
        }
    }

    func pressButton(udid: String, buttonType: ButtonType, up: Bool) throws {
        guard let connection = activeConnections[udid] else {
            throw IdbError.notConnected(udid: udid)
        }

        let request = Idb_HIDEvent.with { event in
            event.event = .press(Idb_HIDEvent.HIDPress.with { press in
                press.action = .with { action in
                    action.action = .button(Idb_HIDEvent.HIDButton.with { button in
                        button.button = buttonType.hidButtonType
                    })
                }
                press.direction = up ? .up : .down
            })
        }

        let semaphore = DispatchSemaphore(value: 0)
        var taskError: Error?

        Task {
            do {
                _ = try await connection.client.hid([request])
            } catch {
                errorCapturer.capture(error: error)
                taskError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = taskError {
            throw error
        }
    }

    func copyFromDevice(udid: String, bundleID: String, filepath: String, destinationPath: String) throws {
        guard let connection = activeConnections[udid] else {
            throw IdbError.notConnected(udid: udid)
        }

        let request = Idb_PullRequest.with { filePull in
            filePull.container = .with {
                $0.kind = .application
                $0.bundleID = bundleID
            }
            filePull.srcPath = filepath
            filePull.dstPath = destinationPath
        }

        let semaphore = DispatchSemaphore(value: 0)
        var taskError: Error?

        Task {
            do {
                for try await _ in connection.client.pull(request) {}
            } catch {
                errorCapturer.capture(error: error)
                taskError = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = taskError {
            throw error
        }
    }

    func copyToDevice(udid: String, filepath: String, bundleID: String, destinationPath: String) throws {
        guard let connection = activeConnections[udid] else {
            throw IdbError.notConnected(udid: udid)
        }

        let requests: [Idb_PushRequest] = [
            .with { push in
                push.inner = .with { target in
                    target.container = .with {
                        $0.kind = .application
                        $0.bundleID = bundleID
                    }
                    target.dstPath = destinationPath
                }
            },
            .with { push in
                push.payload = .with { $0.source = .filePath(filepath) }
            },
        ]

        let semaphore = DispatchSemaphore(value: 0)
        var taskError: Error?

        Task {
            do {
                _ = try await connection.client.push(requests)
            } catch {
                errorCapturer.capture(error: error)
                taskError = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = taskError {
            throw error
        }
    }

    public func displayIOSurface(
        udid: String,
        completion: @escaping (Result<IOSurface, Error>) -> Void
    ) {
        guard let connection = activeConnections[udid] else {
            completion(.failure(IdbError.notConnected(udid: udid)))
            return
        }

        // Ensure XPC service is running using the singleton
        do {
            try IOSurfaceBroker.shared.ensureServiceRunning()
        } catch {
            errorCapturer.capture(error: error)
            completion(.failure(error))
            return
        }
        
        Task {
            do {
                let request = Idb_GetMainScreenIOSurfaceRequest.with { req in
                    req.xpcService = IOSurfaceBroker.serviceName
                }
                let response = try await connection.client.get_main_screen_iosurface(request)
                
                // Check if the request was successful
                if response.status != "ok" {
                    await MainActor.run {
                        completion(.failure(IdbError.invalidResponse(message: "Server error: \(response.status)")))
                    }
                    return
                }

                // Use the IOSurfaceBroker singleton to get the IOSurface
                await MainActor.run {
                    IOSurfaceBroker.shared.requestIOSurface(completion: completion)
                }

            } catch {
                errorCapturer.capture(error: error)
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Lists installed applications on the device
    public func listApps(udid: String) throws -> [(name: String, bundleID: String)] {
        let currentKeys = activeConnections.keys.joined(separator: ", ")

        guard let connection = activeConnections[udid] else {
            throw IdbError.notConnected(udid: udid)
        }

        let request = Idb_ListAppsRequest.with { req in
            req.suppressProcessState = false
        }

        let semaphore = DispatchSemaphore(value: 0)
        var taskError: Error?
        var apps: [(name: String, bundleID: String)] = []

        Task {
            do {
                let response = try await connection.client.list_apps(request)
                apps = response.apps.map { appInfo in
                    (name: appInfo.name, bundleID: appInfo.bundleID)
                }
            } catch {
                errorCapturer.capture(error: error)
                taskError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = taskError {
            throw error
        }

        return apps
    }

}

public enum TargetType: String {
    case simulator
    case device
    case unknown
}

// TargetInfo struct with expanded device information
public struct TargetInfo: Codable {
    public let udid: String
    public let name: String
    public let state: String?
    public let type: String
    public let osVersion: String?
    public let architecture: String?
    public let model: String?
    public let device: DeviceDetails?

    enum CodingKeys: String, CodingKey {
        case udid, name, state, type, architecture, model, device
        case osVersion = "os_version"
    }

    public func isIPad() -> Bool {
        if let model, model.contains("iPad") {
            return true
        } else if let product = device?.productType, product.contains("iPad") {
            return true
        } else {
            return false
        }
    }

    public func isSupported() -> Bool {
        if let model, model.contains("iPad") || model.contains("iPhone") {
            return true
        } else if let product = device?.productType, product.contains("iPhone") || product.contains("iPad") {
            return true
        } else {
            return false
        }
    }

    public var targetType: TargetType {
        switch type.lowercased() {
        case "simulator":
            return .simulator
        case "device":
            return .device
        default:
            return .unknown
        }
    }
}

public struct DeviceDetails: Codable {
    public let isPaired: Bool?
    public let trustedHostAttached: Bool?
    public let hostAttached: Bool?
    public let passwordProtected: Bool?
    public let deviceClass: String?
    public let productType: String?

    enum CodingKeys: String, CodingKey {
        case isPaired = "IsPaired"
        case trustedHostAttached = "TrustedHostAttached"
        case hostAttached = "HostAttached"
        case passwordProtected = "PasswordProtected"
        case deviceClass = "DeviceClass"
        case productType = "ProductType"
    }
}

// FileHandle extension for reading until a delimiter
extension FileHandle {
    func readToEnd(of delimiter: String) throws -> Data? {
        var data = Data()
        let delimiterData = delimiter.data(using: .utf8)!

        while true {
            let chunk = self.readData(ofLength: 1)
            if chunk.isEmpty { return nil }

            data.append(chunk)

            if data.count >= delimiterData.count,
               data.suffix(delimiterData.count) == delimiterData {
                return data
            }
        }
    }
}
