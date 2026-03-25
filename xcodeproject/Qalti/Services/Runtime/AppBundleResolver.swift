import Foundation
import Logging

/// Handles resolving app display names to bundle identifiers.
class AppBundleResolver: Loggable {

    private let deviceId: String
    private let idbManager: IdbManaging
    private let errorCapturer: ErrorCapturing

    init(deviceId: String, idbManager: IdbManaging, errorCapturer: ErrorCapturing) {
        self.deviceId = deviceId
        self.idbManager = idbManager
        self.errorCapturer = errorCapturer
    }

    /// Normalize app display names for dictionary keys and lookup
    /// - Behavior: lowercase, remove spaces, strip trailing "app"
    private func normalizeAppKey(_ name: String) -> String {
        var key = name.lowercased().replacingOccurrences(of: " ", with: "")
        if key.hasSuffix("app") {
            key.removeLast(3)
        }
        return key
    }

    /// Lists the available apps on the device or simulator.
    func listApps() -> [String: String]? {
        var bundleDict: [String: String] = [:]

        do {
            // Use unified IdbManager approach for both real devices and simulators
            let apps = try idbManager.listApps(udid: deviceId)

            // Convert array of tuples to dictionary with normalized keys only
            for app in apps {
                bundleDict[normalizeAppKey(app.name)] = app.bundleID
            }

            // Add system apps to be sure (they might not be returned by IDB)
            let systemApps: [String: String] = [
                "Watch": "com.apple.Bridge",
                "Files": "com.apple.DocumentsApp",
                "Fitness": "com.apple.Fitness",
                "Health": "com.apple.Health",
                "Maps": "com.apple.Maps",
                "Contacts": "com.apple.MobileAddressBook",
                "Messages": "com.apple.MobileSMS",
                "Wallet": "com.apple.Passbook",
                "Passwords": "com.apple.Passwords",
                "Settings": "com.apple.Preferences",
                "Calendar": "com.apple.mobilecal",
                "Safari": "com.apple.mobilesafari",
                "Photos": "com.apple.mobileslideshow",
                "News": "com.apple.news",
                "Reminders": "com.apple.reminders",
                "Shortcuts": "com.apple.shortcuts"
            ]
            for (key, value) in systemApps {
                bundleDict[normalizeAppKey(key)] = value
            }

            return bundleDict
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Failed to list apps using IdbManager: \(error.localizedDescription)")
            return nil
        }
    }

    /// Resolves an app name to its bundle identifier, returning the input if no match is found.
    func resolveBundle(for app: String) -> String {
        guard let appsList = listApps() else { return app }
        let normalized = normalizeAppKey(app)
        if let id = appsList[normalized] {
            return id
        }
        return app
    }
}

