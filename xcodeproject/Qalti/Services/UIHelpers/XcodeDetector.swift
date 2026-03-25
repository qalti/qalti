//
//  XcodeDetector.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 28.06.2025.
//

import Foundation
import AppKit
import OSLog

@MainActor
class XcodeDetector: ObservableObject, Loggable {
    
    enum XcodeLocation {
        case applications(String, version: String?)
        case downloads(String, version: String?)
        case custom(String, version: String?)
        case notFound
        
        var path: String? {
            switch self {
            case .applications(let path, _), .downloads(let path, _), .custom(let path, _):
                return path
            case .notFound:
                return nil
            }
        }
        
        var version: String? {
            switch self {
            case .applications(_, let version), .downloads(_, let version), .custom(_, let version):
                return version
            case .notFound:
                return nil
            }
        }
        
        var displayName: String {
            switch self {
            case .applications(let path, let version):
                let name = URL(fileURLWithPath: path).lastPathComponent
                return "Applications: \(name)" + (version.map { " (v\($0))" } ?? "")
            case .downloads(let path, let version):
                let name = URL(fileURLWithPath: path).lastPathComponent
                return "Downloads: \(name)" + (version.map { " (v\($0))" } ?? "")
            case .custom(let path, let version):
                let name = URL(fileURLWithPath: path).lastPathComponent
                let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
                return "Custom: \(name) at \(parentPath)" + (version.map { " (v\($0))" } ?? "")
            case .notFound:
                return "Not Found"
            }
        }
    }

    private(set) var errorCapturer: ErrorCapturing?

    init(errorCapturer: ErrorCapturing?) {
        self.errorCapturer = errorCapturer
    }

    public func setErrorCapturer(_ capturer: ErrorCapturing) {
        guard self.errorCapturer == nil else { return }
        self.errorCapturer = capturer
    }

    // MARK: - Xcode Detection
    
    /// Checks if Xcode is present in the system (Applications, Downloads, including Xcode-beta, and xcode-select path)
    func checkXcodePresence() -> [XcodeLocation] {
        var locations: [XcodeLocation] = []
        
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        
        // Check Applications folder
        let applicationsPath = "/Applications"
        locations.append(contentsOf: findXcodeInstallations(in: applicationsPath, locationType: .applications))
        
        // Check Downloads folder
        let downloadsPath = homeDirectory.appendingPathComponent("Downloads").path
        locations.append(contentsOf: findXcodeInstallations(in: downloadsPath, locationType: .downloads))
        
        // Check xcode-select path for custom Xcode installations
        if let xcodeSelectPath = checkXcodeSelectPathSync() {
            let version = getXcodeVersion(at: xcodeSelectPath)
            
            // For custom locations, use the custom enum case
            locations.append(.custom(xcodeSelectPath, version: version))
            
            logger.info("Found Xcode via xcode-select at: \(xcodeSelectPath) (version: \(version ?? "unknown"))")
        }
        
        if locations.isEmpty {
            locations.append(.notFound)
            logger.warning("No Xcode installations found")
        }
        
        return locations
    }
    
    /// Finds all Xcode installations in a given directory
    private func findXcodeInstallations(in directory: String, locationType: LocationType) -> [XcodeLocation] {
        var installations: [XcodeLocation] = []
        let fileManager = FileManager.default
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: directory)
            
            for item in contents {
                let fullPath = "\(directory)/\(item)"
                
                // Check if it's an app bundle that contains "Xcode" in the name
                if item.lowercased().contains("xcode") && item.hasSuffix(".app") {
                    // Validate it's actually a valid Xcode installation
                    if isValidXcodeInstallation(at: fullPath) {
                        let version = getXcodeVersion(at: fullPath)
                        
                        let location: XcodeLocation
                        switch locationType {
                        case .applications:
                            location = .applications(fullPath, version: version)
                        case .downloads:
                            location = .downloads(fullPath, version: version)
                        case .custom:
                            location = .custom(fullPath, version: version)
                        }
                        
                        installations.append(location)
                        logger.info("Found Xcode at: \(fullPath) (version: \(version ?? "unknown"))")
                    }
                }
            }
        } catch {
            errorCapturer?.capture(error: error)
            logger.error("Failed to scan directory \(directory): \(error.localizedDescription)")
        }
        
        return installations
    }
    
    /// Helper enum to specify location type for installation detection
    private enum LocationType {
        case applications
        case downloads
        case custom
    }
    
    /// Validates if a given path is a valid Xcode installation
    private func isValidXcodeInstallation(at path: String) -> Bool {
        let fileManager = FileManager.default
        
        // Check if the path exists and is a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue else {
            return false
        }
        
        // Check for Info.plist
        let infoPlistPath = "\(path)/Contents/Info.plist"
        guard fileManager.fileExists(atPath: infoPlistPath) else {
            return false
        }
        
        // Check bundle identifier to confirm it's actually Xcode
        guard let plistData = fileManager.contents(atPath: infoPlistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let bundleId = plist["CFBundleIdentifier"] as? String else {
            return false
        }
        
        // Validate bundle identifier is from Apple and is Xcode
        return bundleId == "com.apple.dt.Xcode"
    }
    
    /// Synchronously checks xcode-select path and returns the Xcode app path if valid
    private func checkXcodeSelectPathSync() -> String? {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            logger.info("🧪 Unit Testing detected. Skipping xcode-select synchronous check.")
            return nil
        }

        let task = Process()
        task.launchPath = "/usr/bin/xcode-select"
        task.arguments = ["-p"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard task.terminationStatus == 0, let developerPath = output, !developerPath.isEmpty else {
                return nil
            }
            
            // Convert developer path back to app path
            let xcodeAppPath = URL(fileURLWithPath: developerPath)
                .appendingPathComponent("../..")
                .standardized
                .path
            
            // Verify it's a valid Xcode installation
            if isValidXcodeInstallation(at: xcodeAppPath) {
                return xcodeAppPath
            } else {
                return nil
            }
            
        } catch {
            errorCapturer?.capture(error: error)
            logger.error("Failed to check xcode-select path: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Returns Xcode from xcode-select or, if none present, returns Xcode with the biggest version
    func getLatestOrInstalledXcode(completion: @escaping (XcodeLocation) -> Void) {
        // First, check what xcode-select points to
        checkXcodeSelectSetup { [weak self] (isSetup, currentPath, error) in
            guard let self = self else {
                completion(.notFound)
                return
            }
            
            if isSetup, let currentPath = currentPath {
                // Convert developer path back to app path
                let xcodeAppPath = URL(fileURLWithPath: currentPath)
                    .appendingPathComponent("../..")
                    .standardized
                    .path
                
                let version = self.getXcodeVersion(at: xcodeAppPath)
                
                // Determine if it's in Applications, Downloads, or custom location
                if xcodeAppPath.hasPrefix("/Applications") {
                    completion(.applications(xcodeAppPath, version: version))
                } else if xcodeAppPath.contains("/Downloads/") {
                    completion(.downloads(xcodeAppPath, version: version))
                } else {
                    // For custom locations
                    completion(.custom(xcodeAppPath, version: version))
                }
            } else {
                // No xcode-select setup, find latest by version
                completion(self.getLatestXcodeByVersion())
            }
        }
    }
    
    private func getLatestXcodeByVersion() -> XcodeLocation {
        let locations = checkXcodePresence()
        let validLocations = locations.compactMap { location -> XcodeLocation? in
            guard location.path != nil else { return nil }
            return location
        }
        
        if validLocations.isEmpty {
            return .notFound
        }
        
        // Sort by version, preferring Applications over Downloads for same version
        let sortedLocations = validLocations.sorted { lhs, rhs in
            let lhsVersion = lhs.version ?? "0.0"
            let rhsVersion = rhs.version ?? "0.0"
            
            let versionComparison = compareVersions(lhsVersion, rhsVersion)
            if versionComparison != .orderedSame {
                return versionComparison == .orderedDescending
            }
            
            // Same version, prefer Custom over Applications over Downloads
            switch (lhs, rhs) {
            case (.custom, .applications), (.custom, .downloads):
                return true
            case (.applications, .custom), (.downloads, .custom):
                return false
            case (.applications, .downloads):
                return true
            case (.downloads, .applications):
                return false
            default:
                return false
            }
        }
        
        return sortedLocations.first ?? .notFound
    }
    
    private func getXcodeVersion(at path: String) -> String? {
        let infoPlistPath = "\(path)/Contents/Info.plist"
        
        guard let plistData = FileManager.default.contents(atPath: infoPlistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String else {
            return nil
        }
        
        return version
    }
    
    private func compareVersions(_ version1: String, _ version2: String) -> ComparisonResult {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }
        
        let maxComponents = max(v1Components.count, v2Components.count)
        
        for i in 0..<maxComponents {
            let v1Component = i < v1Components.count ? v1Components[i] : 0
            let v2Component = i < v2Components.count ? v2Components[i] : 0
            
            if v1Component < v2Component {
                return .orderedAscending
            } else if v1Component > v2Component {
                return .orderedDescending
            }
        }
        
        return .orderedSame
    }
    
    // MARK: - Xcode-select Management
    
    /// Checks if xcode-select is set up correctly
    func checkXcodeSelectSetup(completion: @escaping (Bool, String?, String?) -> Void) {
        runShellCommand("/usr/bin/xcode-select", arguments: ["-p"]) { [weak self] result in
            guard let self = self else {
                completion(false, nil, "Service deallocated")
                return
            }
            
            guard result.exitCode == 0 else {
                logger.error("Failed to check xcode-select: \(result.error)")
                completion(false, nil, result.error)
                return
            }
            
            let currentPath = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Verify the path exists and points to a valid Xcode installation
            let fileManager = FileManager.default
            let xcodeAppPath = URL(fileURLWithPath: currentPath).appendingPathComponent("../..").standardized.path
            
            if fileManager.fileExists(atPath: xcodeAppPath) {
                // Additional check: verify this Xcode is in our detected installations
                let detectedInstallations = self.checkXcodePresence()
                let isValidInstallation = detectedInstallations.contains { location in
                    guard let path = location.path else { return false }
                    return path == xcodeAppPath
                }
                
                if isValidInstallation {
                    logger.info("xcode-select is correctly set to: \(currentPath)")
                    completion(true, currentPath, nil)
                } else {
                    logger.warning("xcode-select points to Xcode not in detected installations: \(currentPath)")
                    completion(false, currentPath, "xcode-select points to unrecognized Xcode installation")
                }
            } else {
                logger.warning("xcode-select path exists but doesn't point to valid Xcode: \(currentPath)")
                completion(false, currentPath, "Path doesn't point to valid Xcode installation")
            }
        }
    }
    
    /// Provides the correct xcode-select command for a given Xcode path
    func getXcodeSelectCommand(for xcodePath: String) -> String {
        return "/usr/bin/xcode-select -s \(xcodePath)"
    }
    
    /// Provides the correct xcode-select command for the recommended Xcode
    func getRecommendedXcodeSelectCommand(completion: @escaping (String?) -> Void) {
        getLatestOrInstalledXcode { xcode in
            guard let path = xcode.path else {
                completion(nil)
                return
            }
            completion("/usr/bin/xcode-select -s \(path)")
        }
    }
    
    // MARK: - Simulator Management
    
    struct SimulatorRuntime {
        let name: String
        let version: String
        let identifier: String
        let isAvailable: Bool
        let buildVersion: String?
    }
    
    /// Checks if simulators are installed via xcrun simctl runtime list
    func checkSimulatorRuntimes(completion: @escaping ([SimulatorRuntime], String?) -> Void) {
        runShellCommand("/usr/bin/xcrun", arguments: ["simctl", "runtime", "list", "-j"]) { [weak self] result in
            guard let self = self else {
                completion([], "Service deallocated")
                return
            }
            
            guard result.exitCode == 0 else {
                logger.error("Failed to check simulator runtimes: \(result.error)")
                completion([], result.error)
                return
            }
            
            guard let data = result.output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
            else {
                logger.error("Failed to parse simulator runtime list")
                completion([], "Failed to parse runtime list")
                return
            }
            
            let simulatorRuntimes = json.compactMap { (uuid, runtime) -> SimulatorRuntime? in
                guard let version = runtime["version"] as? String,
                      let runtimeIdentifier = runtime["runtimeIdentifier"] as? String,
                      let state = runtime["state"] as? String else {
                    return nil
                }
                
                // Filter to only include iOS runtimes
                let platformIdentifier = runtime["platformIdentifier"] as? String ?? ""
                let isIOSRuntime = runtimeIdentifier.contains("iOS") && 
                                 platformIdentifier == "com.apple.platform.iphonesimulator"
                
                // Explicitly exclude non-iOS platforms
                let isExcludedPlatform = platformIdentifier == "com.apple.platform.xrsimulator" ||
                                       platformIdentifier == "com.apple.platform.ipadossimulator" ||
                                       runtimeIdentifier.contains("xrOS") ||
                                       runtimeIdentifier.contains("iPadOS") ||
                                       runtimeIdentifier.contains("visionOS")
                
                guard isIOSRuntime && !isExcludedPlatform else {
                    return nil // Skip non-iOS runtimes (xrOS, iPadOS, visionOS, etc.)
                }
                
                let buildVersion = runtime["build"] as? String
                let isAvailable = state == "Ready"
                
                // Extract name from runtimeBundlePath or runtimeIdentifier
                let name: String
                if let runtimeBundlePath = runtime["runtimeBundlePath"] as? String {
                    name = URL(fileURLWithPath: runtimeBundlePath).lastPathComponent
                } else {
                    // Fallback to parsing runtimeIdentifier (e.g., "com.apple.CoreSimulator.SimRuntime.iOS-16-0" -> "iOS 16.0")
                    let components = runtimeIdentifier.components(separatedBy: ".")
                    if let lastComponent = components.last {
                        name = lastComponent.replacingOccurrences(of: "-", with: " ")
                    } else {
                        name = runtimeIdentifier
                    }
                }
                
                return SimulatorRuntime(
                    name: name,
                    version: version,
                    identifier: runtimeIdentifier,
                    isAvailable: isAvailable,
                    buildVersion: buildVersion
                )
            }
            
            logger.info("Found \(simulatorRuntimes.count) simulator runtimes")
            completion(simulatorRuntimes, nil)
        }
    }
    
    // MARK: - App Store Integration
    
    /// Opens App Store on the Xcode page
    func openXcodeInAppStore() {
        let xcodeAppStoreURL = "macappstore://apps.apple.com/app/xcode/id497799835"
        
        if let url = URL(string: xcodeAppStoreURL) {
            NSWorkspace.shared.open(url)
            logger.info("Opened Xcode in App Store")
        } else {
            logger.error("Failed to create App Store URL for Xcode")
        }
    }
    
    // MARK: - Administrative Commands
    
    /// Launches a command via AppleScript with admin privileges
    func runCommandWithAdminPrivileges(_ command: String, completion: @escaping (Bool, String?) -> Void) {
        // Escape quotes and backslashes for AppleScript
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        let appleScript = """
        do shell script "\(escapedCommand)" with administrator privileges
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", appleScript]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe
        
        task.terminationHandler = { [weak self] _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if task.terminationStatus == 0 {
                self?.logger.info("Successfully executed admin command: \(command)")
                completion(true, nil)
            } else {
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                self?.logger.error("Failed to execute admin command: \(errorMessage)")
                completion(false, errorMessage)
            }
        }
        
        do {
            try task.run()
        } catch {
            errorCapturer?.capture(error: error)
            logger.error("Failed to create admin command task: \(error.localizedDescription)")
            completion(false, error.localizedDescription)
        }
    }
    
    /// Sets up xcode-select with admin privileges
    func setupXcodeSelect(path: String, completion: @escaping (Bool, String?) -> Void) {
        let command = "/usr/bin/xcode-select -s \(path)"
        runCommandWithAdminPrivileges(command, completion: completion)
    }
    
    /// Checks if Xcode license has been accepted
    func checkXcodeLicense(completion: @escaping (Bool, String?) -> Void) {
        runShellCommand("/usr/bin/xcodebuild", arguments: ["-license", "check"]) { [weak self] result in
            guard let self = self else {
                completion(false, "Service deallocated")
                return
            }
            
            if result.exitCode == 0 {
                logger.info("Xcode license already accepted")
                completion(true, nil)
            } else {
                logger.info("Xcode license not accepted: \(result.error)")
                completion(false, result.error.isEmpty ? "License not accepted" : result.error)
            }
        }
    }
    
    /// Accepts Xcode license agreement automatically
    func acceptXcodeLicense(completion: @escaping (Bool, String?) -> Void) {
        // Use the accept flag to bypass interactive license agreement
        let command = "/usr/bin/xcodebuild -license accept"
        runCommandWithAdminPrivileges(command, completion: completion)
    }
    
    // MARK: - Simulator Runtime Download and Installation
    
    /// Downloads iOS simulator runtime
    func downloadSimulatorRuntime(platform: String = "iOS", buildVersion: String? = nil, progressCallback: @escaping (Double, String) -> Void = { _, _ in }, completion: @escaping (Bool, String?) -> Void) {
        var arguments = ["-downloadPlatform", platform]
        
        // Only add buildVersion if specified, otherwise download latest
        if let buildVersion = buildVersion {
            arguments.append(contentsOf: ["-buildVersion", buildVersion])
        }
        
        runShellCommandWithProgress("/usr/bin/xcodebuild", arguments: arguments, progressCallback: progressCallback) { [weak self] result in
            guard let self = self else {
                completion(false, "Service deallocated")
                return
            }
            
            if result.exitCode == 0 {
                let versionInfo = buildVersion.map { " \($0)" } ?? " (latest)"
                logger.info("Successfully downloaded \(platform) runtime\(versionInfo)")
                completion(true, nil)
            } else {
                logger.error("Failed to download runtime: \(result.error)")
                completion(false, result.error)
            }
        }
    }
    
    private func executeCommandsSequentially(_ commands: [String], index: Int, completion: @escaping (Bool, String?) -> Void) {
        guard index < commands.count else {
            completion(true, nil)
            return
        }
        
        let command = commands[index]
        runCommandWithAdminPrivileges(command) { [weak self] success, error in
            guard let self = self else {
                completion(false, "Service deallocated")
                return
            }
            
            if success {
                executeCommandsSequentially(commands, index: index + 1, completion: completion)
            } else {
                logger.error("Failed to execute command: \(command)")
                completion(false, error)
            }
        }
    }
    
    // MARK: - Utility Methods
    
    private struct ShellResult {
        let output: String
        let error: String
        let exitCode: Int32
    }
    
    private func runShellCommand(_ command: String, arguments: [String] = [], completion: @escaping (ShellResult) -> Void) {
        let task = Process()
        task.launchPath = command
        task.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        task.terminationHandler = { _ in
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            let result = ShellResult(
                output: output,
                error: error,
                exitCode: task.terminationStatus
            )
            
            DispatchQueue.main.async {
                completion(result)
            }
        }
        
        do {
            try task.run()
        } catch {
            errorCapturer?.capture(error: error)
            DispatchQueue.main.async {
                completion(ShellResult(
                    output: "",
                    error: error.localizedDescription,
                    exitCode: -1
                ))
            }
        }
    }
    
    private func runShellCommandWithProgress(_ command: String, arguments: [String] = [], progressCallback: @escaping (Double, String) -> Void, completion: @escaping (ShellResult) -> Void) {
        let task = Process()
        task.launchPath = command
        task.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        var outputData = Data()
        var errorData = Data()
        
        // Read output continuously to capture progress
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                outputData.append(data)
                if let line = String(data: data, encoding: .utf8) {
                    self.parseProgressLine(line, progressCallback: progressCallback)
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                errorData.append(data)
                if let line = String(data: data, encoding: .utf8) {
                    self.parseProgressLine(line, progressCallback: progressCallback)
                }
            }
        }
        
        task.terminationHandler = { _ in
            // Close handlers
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            let result = ShellResult(
                output: output,
                error: error,
                exitCode: task.terminationStatus
            )
            
            DispatchQueue.main.async {
                completion(result)
            }
        }
        
        do {
            try task.run()
        } catch {
            errorCapturer?.capture(error: error)
            DispatchQueue.main.async {
                completion(ShellResult(
                    output: "",
                    error: error.localizedDescription,
                    exitCode: -1
                ))
            }
        }
    }
    
    nonisolated private func parseProgressLine(_ line: String, progressCallback: @escaping (Double, String) -> Void) {
        // Parse lines like: "Downloading iOS 26.0 Universal Simulator (23A5260l) (universal): 2.4% (246.5 MB of 10.07 GB)"
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Look for percentage pattern
        let percentageRegex = try? NSRegularExpression(pattern: #"(\d+\.?\d*)%"#, options: [])
        if let percentageMatch = percentageRegex?.firstMatch(in: trimmedLine, options: [], range: NSRange(location: 0, length: trimmedLine.count)) {
            let percentageRange = Range(percentageMatch.range(at: 1), in: trimmedLine)
            if let percentageRange = percentageRange,
               let percentage = Double(String(trimmedLine[percentageRange])) {
                
                // Look for size information in parentheses
                let sizeRegex = try? NSRegularExpression(pattern: #"\(([^)]+)\)(?:[^(]*$)"#, options: [])
                var sizeInfo = ""
                
                if let sizeMatch = sizeRegex?.firstMatch(in: trimmedLine, options: [], range: NSRange(location: 0, length: trimmedLine.count)) {
                    let sizeRange = Range(sizeMatch.range(at: 1), in: trimmedLine)
                    if let sizeRange = sizeRange {
                        sizeInfo = String(trimmedLine[sizeRange])
                    }
                }
                
                DispatchQueue.main.async {
                    progressCallback(percentage / 100.0, sizeInfo)
                }
            }
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Performs a complete Xcode setup check in sequence
    func performCompleteCheck(completion: @escaping (XcodeSetupStatus) -> Void) {
        // Step 1: Check if Xcode is installed
        let xcodeLocations = checkXcodePresence()
        
        // If no Xcode installations found, skip remaining checks
        guard xcodeLocations.contains(where: { $0.path != nil }) else {
            let status = XcodeSetupStatus(
                xcodeInstallations: xcodeLocations,
                xcodeSelectSetup: (false, nil, "Xcode not installed"),
                licenseAccepted: (false, "Xcode not installed - cannot check license"),
                simulatorRuntimes: [],
                runtimeError: "Xcode not installed - cannot check simulator runtimes"
            )
            completion(status)
            return
        }
        
        // Step 2: Check xcode-select setup
        checkXcodeSelectSetup { [weak self] isSetup, currentPath, selectError in
            guard let self = self else {
                completion(XcodeSetupStatus(
                    xcodeInstallations: xcodeLocations,
                    xcodeSelectSetup: (false, nil, "Service deallocated"),
                    licenseAccepted: (false, "Service deallocated"),
                    simulatorRuntimes: [],
                    runtimeError: "Service deallocated"
                ))
                return
            }
            
            let selectSetup = (isSetup, currentPath, selectError)
            
            // If xcode-select is not properly set up, skip license and simulator runtime checks
            guard isSetup else {
                let status = XcodeSetupStatus(
                    xcodeInstallations: xcodeLocations,
                    xcodeSelectSetup: selectSetup,
                    licenseAccepted: (false, "xcode-select not properly configured - cannot check license"),
                    simulatorRuntimes: [],
                    runtimeError: "xcode-select not properly configured - cannot check simulator runtimes"
                )
                completion(status)
                return
            }
            
            // Step 3: Check Xcode license
            self.checkXcodeLicense { licenseAccepted, licenseError in
                let licenseSetup = (licenseAccepted, licenseError)
                
                // If license is not accepted, skip simulator runtime check
                guard licenseAccepted else {
                    let status = XcodeSetupStatus(
                        xcodeInstallations: xcodeLocations,
                        xcodeSelectSetup: selectSetup,
                        licenseAccepted: licenseSetup,
                        simulatorRuntimes: [],
                        runtimeError: "Xcode license not accepted - cannot check simulator runtimes"
                    )
                    completion(status)
                    return
                }
                
                // Step 4: Check simulator runtimes
                self.checkSimulatorRuntimes { runtimes, runtimeError in
                    let status = XcodeSetupStatus(
                        xcodeInstallations: xcodeLocations,
                        xcodeSelectSetup: selectSetup,
                        licenseAccepted: licenseSetup,
                        simulatorRuntimes: runtimes,
                        runtimeError: runtimeError
                    )
                    
                    completion(status)
                }
            }
        }
    }
}

// MARK: - Status Structure

struct XcodeSetupStatus {
    let xcodeInstallations: [XcodeDetector.XcodeLocation]
    let xcodeSelectSetup: (isSetup: Bool, currentPath: String?, error: String?)
    let licenseAccepted: (accepted: Bool, error: String?)
    let simulatorRuntimes: [XcodeDetector.SimulatorRuntime]
    let runtimeError: String?
    
    var hasXcode: Bool {
        xcodeInstallations.contains { $0.path != nil }
    }
    
    var isXcodeSelectSetup: Bool {
        xcodeSelectSetup.isSetup
    }
    
    var isLicenseAccepted: Bool {
        licenseAccepted.accepted
    }
    
    var hasSimulatorRuntimes: Bool {
        !simulatorRuntimes.isEmpty && simulatorRuntimes.contains { $0.isAvailable }
    }
    
    var isFullySetup: Bool {
        hasXcode && isXcodeSelectSetup && isLicenseAccepted && hasSimulatorRuntimes
    }
}

