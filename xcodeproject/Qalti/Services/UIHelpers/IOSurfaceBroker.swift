import Foundation
import Logging
import XPC
import IOSurface

public class IOSurfaceBroker: Loggable {
    
    static let shared = IOSurfaceBroker()
    static let serviceName = "com.aiqa.IOSurfaceBroker"
    
    private var ioSurfaceTimeoutTimer: Timer?
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Ensures the XPC service is properly launched and running
    public func ensureServiceRunning() throws {
        logger.debug("ensureServiceRunning called")
        
        // Check if we need to reinstall the service
        let needsReinstall = try checkIfServiceNeedsReinstall()
        
        if needsReinstall {
            logger.debug("Service needs reinstall, cleaning up and reinstalling...")
            try cleanupAndReinstallService()
        } else {
            logger.debug("Service is already properly installed and running")
        }
        
        logger.debug("Service launch completed")
    }
    
    /// Requests an IOSurface from the XPC service
    public func requestIOSurface(completion: @escaping (Result<IOSurface, Error>) -> Void) {
        logger.debug("requestIOSurface called")
        
        // Set up timeout timer (10 seconds)
        ioSurfaceTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            DispatchQueue.main.async {
                completion(.failure(IOSurfaceBrokerError.timeout))
                self.ioSurfaceTimeoutTimer = nil
            }
        }
        
        DispatchQueue.main.async {
            let connection = xpc_connection_create_mach_service(Self.serviceName, DispatchQueue.main, 0)
            xpc_connection_set_event_handler(connection) { event in
                self.logger.debug("XPC event: \(event)")
            }
            xpc_connection_resume(connection)
            
            let request = xpc_dictionary_create(nil, nil, 0)
            xpc_dictionary_set_string(request, "cmd", "acquire")
            
            xpc_connection_send_message_with_reply(connection, request, DispatchQueue.main) { reply in
                guard let xpcObject = xpc_dictionary_get_value(reply, "surf"),
                      let surface = IOSurfaceLookupFromXPCObject(xpcObject) else {
                    completion(.failure(IOSurfaceBrokerError.invalidResponse("Failed to get IOSurface from XPC reply")))
                    return
                }
                
                // Clean up on success
                self.ioSurfaceTimeoutTimer?.invalidate()
                self.ioSurfaceTimeoutTimer = nil
                
                completion(.success(surface))
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Path to the XPC service binary
    private var xpcServicePath: String {
        let appPath = Bundle.main.bundlePath
        return "\(appPath)/Contents/XPCServices/IOSurfaceBroker.xpc/Contents/MacOS/IOSurfaceBroker"
    }
    
    /// Path of the temporary LaunchAgent we drop under ~/Library/LaunchAgents/
    private var plistURL: URL {
        let dir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        return dir.appendingPathComponent("\(Self.serviceName).plist")
    }
    
    /// Checks if the XPC service needs to be reinstalled
    /// Returns true if plist doesn't exist, points to wrong file, or service isn't running
    private func checkIfServiceNeedsReinstall() throws -> Bool {
        logger.debug("Checking if service needs reinstall")
        
        // Check if plist exists
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            logger.debug("Plist doesn't exist, needs install")
            return true
        }
        
        // Validate plist contents
        if try !validatePlistContents() {
            logger.debug("Plist contents are invalid, needs reinstall")
            return true
        }
        
        // Check if service is actually running
        if try !isServiceRunning() {
            logger.debug("Service is not running, needs reinstall")
            return true
        }
        
        logger.debug("Service is properly installed and running")
        return false
    }
    
    /// Validates that the plist points to the correct XPC service path
    private func validatePlistContents() throws -> Bool {
        logger.debug("Validating plist contents")
        
        guard let plistData = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            logger.debug("Failed to read plist")
            return false
        }
        
        // Check if the program arguments point to the correct XPC service path
        guard let programArguments = plist["ProgramArguments"] as? [String],
              let programPath = programArguments.first else {
            logger.debug("No program arguments found in plist")
            return false
        }
        
        let isValid = programPath == xpcServicePath
        logger.debug("Plist validation result: \(isValid) (expected: \(xpcServicePath), found: \(programPath))")
        return isValid
    }
    
    /// Checks if the XPC service is currently running
    private func isServiceRunning() throws -> Bool {
        logger.debug("Checking if service is running")
        
        let uid = String(getuid())
        let exitCode = try runLaunchctl(arguments: ["print", "gui/\(uid)/\(Self.serviceName)"])
        
        // Exit code 0 means service is loaded and running
        let isRunning = exitCode == 0
        logger.debug("Service running check result: \(isRunning)")
        return isRunning
    }
    
    /// Cleans up existing service and reinstalls it
    private func cleanupAndReinstallService() throws {
        logger.debug("Cleaning up and reinstalling service")
        
        // Try to bootout existing service if it's running
        try? bootoutExistingService()
        
        // Remove existing plist
        try? FileManager.default.removeItem(at: plistURL)
        logger.debug("Removed existing plist")
        
        // Install and bootstrap new service
        try installAndBootstrapJob()
        logger.debug("Service reinstalled successfully")
    }
    
    /// Attempts to bootout the existing XPC service
    private func bootoutExistingService() throws {
        logger.debug("Attempting to bootout existing service")
        
        let uid = String(getuid())
        let exitCode = try runLaunchctl(arguments: ["bootout", "gui/\(uid)/\(Self.serviceName)"])
        
        if exitCode == 0 {
            logger.debug("Successfully booted out existing service")
        } else {
            logger.debug("Failed to bootout service (exit code: \(exitCode)) - may not have been running")
        }
    }
    
    /// Write a minimal job plist and bootstrap it into the GUI domain (`gui/<uid>`)
    private func installAndBootstrapJob() throws {
        logger.debug("installAndBootstrapJob called")
        
        // 1. build the plist in-memory
        logger.debug("Building plist for service: \(Self.serviceName)")
        let job: [String: Any] = [
            "Label": Self.serviceName,
            "MachServices": [Self.serviceName: true],
            "ProgramArguments": [xpcServicePath],
            "RunAtLoad": true,
            "KeepAlive": true
        ]
        
        logger.debug("Plist content: \(job)")
        logger.debug("XPC service path: \(xpcServicePath)")

        // 2. ensure ~/Library/LaunchAgents exists and write atomically
        logger.debug("Creating LaunchAgents directory and writing plist to: \(plistURL.path)")
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil)
        let data = try PropertyListSerialization.data(fromPropertyList: job,
                                                      format: .xml,
                                                      options: 0)
        try data.write(to: plistURL, options: .atomic)
        logger.debug("Plist written successfully")

        // 3. launchctl bootstrap gui/<uid> <plist>
        let uid = String(getuid())
        logger.debug("Bootstrapping job for UID: \(uid)")
        try runLaunchctl(arguments: ["bootstrap", "gui/\(uid)", plistURL.path])
        logger.debug("Job bootstrapped successfully")
    }
    
    /// Tiny wrapper so we get an exit status and possible stderr if things go wrong
    @discardableResult
    private func runLaunchctl(arguments: [String]) throws -> Int32 {
        logger.debug("runLaunchctl called with arguments: \(arguments)")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        
        // Capture stdout and stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe
        
        try task.run()
        // Read and log the output
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        task.waitUntilExit()
        
        if let stdoutString = String(data: stdoutData, encoding: .utf8), !stdoutString.isEmpty {
            logger.debug("launchctl stdout: \(stdoutString.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        
        if let stderrString = String(data: stderrData, encoding: .utf8), !stderrString.isEmpty {
            logger.debug("launchctl stderr: \(stderrString.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        
        logger.debug("launchctl exit code: \(task.terminationStatus)")
        return task.terminationStatus
    }
}

// MARK: - Error Types

public enum IOSurfaceBrokerError: Error {
    case timeout
    case invalidResponse(String)
    case serviceNotRunning
    case launchError(String)
} 
