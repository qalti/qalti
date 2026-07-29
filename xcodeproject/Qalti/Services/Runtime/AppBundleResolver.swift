import Foundation
import Logging

/// Handles resolving app display names to bundle identifiers.
class AppBundleResolver: Loggable {

    /// Outcome of an app lookup.
    ///
    /// Callers that can surface an error to the user should prefer `resolve(_:)` over
    /// `resolveBundle(for:)`: an unresolved name passed downstream as if it were a bundle ID
    /// turns "this app is not installed" into an opaque request timeout minutes later.
    enum Resolution {
        case resolved(bundleID: String)
        case notInstalled(requested: String, available: [String])
        case listUnavailable(requested: String)

        /// A message explaining the failure, including what *is* installed. `nil` when resolved.
        var failureMessage: String? {
            switch self {
            case .resolved:
                return nil
            case .notInstalled(let requested, let available):
                let list = available.isEmpty ? "none reported" : available.joined(separator: ", ")
                return "App '\(requested)' is not installed on this device. Installed apps: \(list)"
            case .listUnavailable(let requested):
                return "Could not resolve '\(requested)': the list of installed apps is unavailable "
                     + "(the device may be disconnected or idb may not be responding)"
            }
        }
    }

    /// The installed-app list, indexed for lookup by either display name or bundle ID.
    private struct Catalog {
        /// normalized display name -> bundle ID
        let byName: [String: String]
        /// lowercased bundle ID -> bundle ID as reported
        let byBundleID: [String: String]
        /// display names, for error messages
        let displayNames: [String]
    }

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

    /// System apps that idb may not report. Note this list is a fallback, not a source of truth:
    /// an entry here does not mean the app is actually installed (Notes, for instance, ships in the
    /// runtime image but is not registered on iOS 26.x simulators and cannot be launched).
    private static let systemApps: [String: String] = [
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

    /// Lists the available apps on the device or simulator.
    func listApps() -> [String: String]? {
        return loadCatalog()?.byName
    }

    private func loadCatalog() -> Catalog? {
        do {
            // Use unified IdbManager approach for both real devices and simulators
            let apps = try idbManager.listApps(udid: deviceId)

            var byName: [String: String] = [:]
            var byBundleID: [String: String] = [:]
            var displayNames: [String] = []

            for app in apps {
                byName[normalizeAppKey(app.name)] = app.bundleID
                // Indexed separately: normalizeAppKey strips a trailing "app", which would corrupt
                // bundle IDs such as com.apple.DocumentsApp.
                byBundleID[app.bundleID.lowercased()] = app.bundleID
                displayNames.append(app.name)
            }

            // Add system apps to be sure (they might not be returned by IDB)
            for (key, value) in Self.systemApps {
                if byName[normalizeAppKey(key)] == nil {
                    displayNames.append(key)
                }
                byName[normalizeAppKey(key)] = value
                byBundleID[value.lowercased()] = value
            }

            return Catalog(
                byName: byName,
                byBundleID: byBundleID,
                displayNames: displayNames.sorted()
            )
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Failed to list apps using IdbManager: \(error.localizedDescription)")
            return nil
        }
    }

    /// Resolves an app name *or* bundle ID, reporting explicitly when it cannot be found.
    func resolve(_ app: String) -> Resolution {
        guard let catalog = loadCatalog() else {
            return .listUnavailable(requested: app)
        }

        if let id = catalog.byName[normalizeAppKey(app)] {
            return .resolved(bundleID: id)
        }
        // Callers (and LLM tool calls) frequently pass a bundle ID rather than a display name.
        if let id = catalog.byBundleID[app.lowercased()] {
            return .resolved(bundleID: id)
        }

        logger.error("Could not resolve app '\(app)'. Installed: \(catalog.displayNames.joined(separator: ", "))")
        return .notInstalled(requested: app, available: catalog.displayNames)
    }

    /// Resolves an app name to its bundle identifier, returning the input if no match is found.
    ///
    /// Prefer `resolve(_:)` where the failure can be surfaced — this fallback hands an unresolved
    /// string to the caller as though it were a valid bundle ID.
    func resolveBundle(for app: String) -> String {
        if case .resolved(let bundleID) = resolve(app) {
            return bundleID
        }
        return app
    }
}
