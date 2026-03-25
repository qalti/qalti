//
//  DeviceAdministration.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import Foundation
import Logging

/// Manages administrative tasks on a device, such as setting permissions,
/// modifying user defaults, and changing the system time.
class DeviceAdministration {
    private let deviceId: String
    private let appBundleResolver: AppBundleResolver
    private let logger = Logger(label: "com.qalti.DeviceAdministration")

    private let commandRunner: ([String]) -> Void
    private let idbManager: IdbManaging
    private let appleScriptExecutor: AppleScriptExecuting
    private let errorCapturer: ErrorCapturing
    private let fileManager: FileSystemManaging

    init(
        deviceId: String,
        idbManager: IdbManaging,
        appBundleResolver: AppBundleResolver,
        runtimeUtils: IOSRuntimeUtilsProviding,
        appleScriptExecutor: AppleScriptExecuting = LiveAppleScriptExecutor(),
        errorCapturer: ErrorCapturing,
        fileManager: FileSystemManaging = FileManager.default
    ) {
        self.deviceId = deviceId
        self.idbManager = idbManager
        self.appBundleResolver = appBundleResolver
        self.appleScriptExecutor = appleScriptExecutor
        self.errorCapturer = errorCapturer
        self.fileManager = fileManager

        self.commandRunner = { command in
            _ = runtimeUtils.runConsoleCommand(command: command, timeout: nil)
        }
    }

    // MARK: - Permissions

    func resetPermissions(forApp appName: String) {
        let bundleID = appBundleResolver.resolveBundle(for: appName)
        guard !bundleID.isEmpty else { return }
        commandRunner(["xcrun", "simctl", "privacy", deviceId, "reset", "all", bundleID])
    }

    func grantPermission(_ permission: Permission, forApp appName: String) {
        let bundleID = appBundleResolver.resolveBundle(for: appName)
        guard !bundleID.isEmpty else { return }
        commandRunner(["xcrun", "simctl", "privacy", deviceId, "grant", permission.rawValue, bundleID])
    }

    // MARK: - System Time

    func setSystemTime(to time: String) {
        setSystemTimeViaAppleScript(time: time)
    }

    func setNetworkTimeToAuto() {
        setNetworkTimeViaAppleScript()
    }

    // MARK: - User Defaults

    /// A high-level method to set or delete a value in an app's UserDefaults.
    /// - Parameters:
    ///   - appName: The name or bundle ID of the app.
    ///   - path: An array of keys representing the path to the value.
    ///   - value: The value to set. If `nil`, the key at the path will be deleted.
    func updateUserDefaults(forApp appName: String, path: [String], value: Any?) {
        var userDefaults = loadUserDefaults(forApp: appName)
        userDefaults[path] = value
        saveUserDefaults(forApp: appName, preferences: userDefaults)
    }

    // MARK: - Private Implementations

    func loadUserDefaults(forApp appName: String) -> [String: Any] {
        let bundleID = appBundleResolver.resolveBundle(for: appName)
        guard !bundleID.isEmpty else { return [:] }

        let preferencesPath = "Library/Preferences/\(bundleID).plist"
        let tempDir = fileManager.temporaryDirectory
        let localPlistPath = tempDir.appendingPathComponent("\(bundleID).plist").path

        do {
            try idbManager.copyFromDevice(udid: deviceId, bundleID: bundleID, filepath: preferencesPath, destinationPath: tempDir.path())
            guard let plistData = fileManager.contents(atPath: localPlistPath),
                  let preferences = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
            else {
                logger.debug("Could not read preferences file for \(bundleID), returning empty dictionary.")
                return [:]
            }
            return preferences
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Error loading user defaults for \(bundleID): \(error.localizedDescription)")
            return [:]
        }
    }

    func saveUserDefaults(forApp appName: String, preferences: [String: Any]) {
        let bundleID = appBundleResolver.resolveBundle(for: appName)
        guard !bundleID.isEmpty else { return }

        let preferencesPath = "Library/Preferences/"
        let tempDir = fileManager.temporaryDirectory
        let localPlistURL = tempDir.appendingPathComponent("\(bundleID).plist")

        do {
            let plistData = try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0)
            try fileManager.write(plistData, to: localPlistURL)
            try idbManager.copyToDevice(udid: deviceId, filepath: localPlistURL.path, bundleID: bundleID, destinationPath: preferencesPath)
            logger.info("Successfully updated preferences for \(bundleID)")
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Error saving preferences for \(bundleID): \(error.localizedDescription)")
        }
    }

    private func setSystemTimeViaAppleScript(time: String) {
#if os(macOS)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM:dd:yyyy"
        let dateString = dateFormatter.string(from: Date())
        let appleScript = """
        do shell script "systemsetup -setusingnetworktime off" with administrator privileges
        do shell script "systemsetup -setdate '\(dateString)' -settime '\(time):00'" with administrator privileges
        """
        let result = appleScriptExecutor.execute(source: appleScript)
        if !result.success { logger.error("AppleScript Error: \(String(describing: result.error))") }
#endif
    }

    private func setNetworkTimeViaAppleScript() {
#if os(macOS)
        let appleScript = "do shell script \"systemsetup -setusingnetworktime on\" with administrator privileges"
        let result = appleScriptExecutor.execute(source: appleScript)
        if !result.success { logger.error("AppleScript Error: \(String(describing: result.error))") }
#endif
    }
}
