import Foundation
import Logging

/// A class that manages an iOS runtime (either a real device or a simulator).
class IOSRuntime: Equatable, Loggable {

    typealias Response = IOSRuntimeResponse

    // MARK: - Properties

    let deviceId: String
    let isRealDevice: Bool

    // this flag is not used here anywhere, it's just a proxy for the TargetInfo
    // if we need to store something else from the TargetInfo, we should rething the strategy, and just save it directly
    let isIpad: Bool

    private(set) var serverAddress: String
    let controlServerPort: Int
    let screenshotServerPort: Int
    private var iphoneIP: String?

    private let errorCapturer: ErrorCapturing
    private let runtimeUtils: IOSRuntimeUtils
    private let appBundleResolver: AppBundleResolver
    private let idbManager: IdbManaging

    private lazy var deviceAdministration = DeviceAdministration(
        deviceId: deviceId,
        idbManager: idbManager,
        appBundleResolver: appBundleResolver,
        runtimeUtils: runtimeUtils,
        errorCapturer: errorCapturer
    )
    
    lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil

        let session = URLSession(configuration: configuration)

        URLSession.shared.configuration.urlCache = nil
        URLSession.shared.configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        return session
    }()

    private lazy var requestBuilder = IOSRuntimeRequestBuilder(serverAddress: serverAddress, controlServerPort: controlServerPort)

    lazy var runner: RunnerManager = {
        return RunnerManager(deviceID: deviceId, isRealDevice: isRealDevice, idbManager: idbManager, errorCapturer: errorCapturer)
    }()

    private let uniqueToken = UUID()

    // MARK: - Factory Methods

    /// Creates and configures an IOSRuntime for a real device, handling IP address resolution.
    static func makeForRealDevice(
        deviceID: String,
        controlServerPort: Int = AppConstants.defaultControlPort,
        screenshotServerPort: Int = AppConstants.defaultScreenshotPort,
        idbManager: IdbManaging,
        errorCapturer: ErrorCapturing,
        isIpad: Bool = false
    ) throws -> IOSRuntime {
        let runtimeUtils = IOSRuntimeUtils(errorCapturer: errorCapturer)
        let appBundleResolver = AppBundleResolver(deviceId: deviceID, idbManager: idbManager, errorCapturer: errorCapturer)

        switch runtimeUtils.getIphoneIP(for: deviceID) {
        case .success(let iphoneIP):
            return IOSRuntime(
                deviceID: deviceID,
                isRealDevice: true,
                isIpad: isIpad,
                serverAddress: iphoneIP,
                controlServerPort: controlServerPort,
                screenshotServerPort: screenshotServerPort,
                errorCapturer: errorCapturer,
                runtimeUtils: runtimeUtils,
                idbManager: idbManager,
                appBundleResolver: appBundleResolver
            )
        case .failure(let error):
            throw error
        }
    }

    // MARK: - Initializer

    /// Initializes a runtime for a simulator.
    required init(
        simulatorID: String,
        controlServerPort: Int = AppConstants.defaultControlPort,
        screenshotServerPort: Int = AppConstants.defaultScreenshotPort,
        idbManager: IdbManaging,
        errorCapturer: ErrorCapturing,
        isIpad: Bool = false
    ) {
        self.deviceId = simulatorID
        self.isRealDevice = false
        self.isIpad = isIpad
        self.serverAddress = "localhost"
        self.iphoneIP = nil
        self.controlServerPort = controlServerPort
        self.screenshotServerPort = screenshotServerPort
        self.errorCapturer = errorCapturer
        self.runtimeUtils = IOSRuntimeUtils(errorCapturer: errorCapturer)
        self.idbManager = idbManager
        self.appBundleResolver = AppBundleResolver(deviceId: deviceId, idbManager: idbManager, errorCapturer: errorCapturer)
    }

    /// **Internal initializer for real devices.** Use the `makeForRealDevice` factory method for public creation.
    /// This initializer is simple and assign-only, making it perfect for testing.
    required internal init(
        deviceID: String,
        isRealDevice: Bool,
        isIpad: Bool,
        serverAddress: String,
        controlServerPort: Int,
        screenshotServerPort: Int,
        errorCapturer: ErrorCapturing,
        runtimeUtils: IOSRuntimeUtils,
        idbManager: IdbManaging,
        appBundleResolver: AppBundleResolver
    ) {
        self.deviceId = deviceID
        self.isRealDevice = isRealDevice
        self.isIpad = isIpad
        self.serverAddress = serverAddress
        self.iphoneIP = serverAddress
        self.controlServerPort = controlServerPort
        self.screenshotServerPort = screenshotServerPort
        self.errorCapturer = errorCapturer
        self.runtimeUtils = runtimeUtils
        self.idbManager = idbManager
        self.appBundleResolver = appBundleResolver
    }

    /// Unified initializer from full TargetInfo.
    convenience init(
        target: TargetInfo,
        controlServerPort: Int = AppConstants.defaultControlPort,
        screenshotServerPort: Int = AppConstants.defaultScreenshotPort,
        idbManager: IdbManaging,
        errorCapturer: ErrorCapturing
    ) throws {
        let ipad = target.isIPad()
        if target.targetType == .simulator {
            self.init(
                simulatorID: target.udid,
                controlServerPort: controlServerPort,
                screenshotServerPort: screenshotServerPort,
                idbManager: idbManager,
                errorCapturer: errorCapturer,
                isIpad: ipad
            )
        } else {
            let runtime = try IOSRuntime.makeForRealDevice(
                deviceID: target.udid,
                controlServerPort: controlServerPort,
                screenshotServerPort: screenshotServerPort,
                idbManager: idbManager,
                errorCapturer: errorCapturer,
                isIpad: ipad
            )
            self.init(
                deviceID: runtime.deviceId,
                isRealDevice: runtime.isRealDevice,
                isIpad: runtime.isIpad,
                serverAddress: runtime.serverAddress,
                controlServerPort: runtime.controlServerPort,
                screenshotServerPort: runtime.screenshotServerPort,
                errorCapturer: runtime.errorCapturer,
                runtimeUtils: runtime.runtimeUtils,
                idbManager: runtime.idbManager,
                appBundleResolver: runtime.appBundleResolver
            )
        }
    }

    // MARK: - Helper Methods

    static func == (lhs: IOSRuntime, rhs: IOSRuntime) -> Bool {
        return lhs.deviceId == rhs.deviceId && lhs.uniqueToken == rhs.uniqueToken
    }

    private func shouldRetryDueToConnectivity(error: Error?, response _: URLResponse?) -> Bool {
        guard isRealDevice else { return false }
        guard let urlError = error as? URLError else { return false }

        switch urlError.code {
        case .notConnectedToInternet,
                .cannotFindHost,
                .cannotConnectToHost,
                .networkConnectionLost,
                .dnsLookupFailed,
                .timedOut:
            return true
        default:
            return false
        }
    }

    private func refreshServerAddress(previousAddress: String) -> String? {
        guard isRealDevice else { return nil }

        Thread.sleep(forTimeInterval: 0.5)

        switch runtimeUtils.getIphoneIP(for: deviceId) {
        case .success(let refreshedAddress):
            if refreshedAddress != previousAddress {
                logger.info("Device IP changed from \(previousAddress) to \(refreshedAddress)")
            } else {
                logger.debug("Device IP remains \(refreshedAddress), retrying connection...")
            }
            iphoneIP = refreshedAddress
            serverAddress = refreshedAddress
            return refreshedAddress
        case .failure(let error):
            errorCapturer.capture(error: error)
            return nil
        }
    }

    // MARK: - Instance Methods

    /// Fetches screen scale from runner's control server with retry logic
    func fetchScreenScale(attemptsLeft: Int = 30, completion: @escaping (CGFloat?) -> Void) {
        guard attemptsLeft >= 0, let request = requestBuilder.buildRequest(for: .getScreenInfo, waitForCompletion: true) else {
            completion(nil)
            return
        }

        session.uncachedTask(with: request) { [weak self] data, response, error in
            guard let self else { completion(nil); return }

            // Retry on connectivity for real devices
            if shouldRetryDueToConnectivity(error: error, response: response), attemptsLeft > 0 {
                let previousAddress = serverAddress
                if refreshServerAddress(previousAddress: previousAddress) != nil {
                    fetchScreenScale(attemptsLeft: attemptsLeft - 1, completion: completion)
                    return
                }
            }

            var parsedScale: CGFloat? = nil
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let scale = json["scale"] as? NSNumber
            {
                parsedScale = CGFloat(truncating: scale)
            }

            if parsedScale == nil, attemptsLeft > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self else {
                        Self.logger.warning("Failed to fetch screen scale after one second retry")
                        return
                    }
                    fetchScreenScale(attemptsLeft: attemptsLeft - 1, completion: completion)
                }
                return
            }
            completion(parsedScale)
        }.resume()
    }

    /// Opens an app on the runtime and returns structured response
    func openApp(name: String, launchArguments: [String]? = nil, launchEnvironment: [String: String]? = nil, completion: @escaping (Response) -> Void) {
        let bundleID = appBundleResolver.resolveBundle(for: name)

        guard !bundleID.isEmpty else {
            completion(Response(error: "Could not resolve bundle ID for app: \(name)"))
            return
        }

        let command = RunnerCommand.openApp(
            bundleID: bundleID,
            launchArguments: launchArguments,
            launchEnvironment: launchEnvironment
        )

        guard let request = requestBuilder.buildRequest(for: command) else {
            completion(Response(error: "Failed to build request for openApp command"))
            return
        }

        sendRequest(request) { response in
            completion(response)
        }
    }

    /// Takes a screenshot. If outputPath is given, the screenshot is saved to disk.
    func takeScreenshot(completion: @escaping (PlatformImage?) -> Void) {
        performScreenshotRequest(shouldRetry: true, completion: completion)
    }

    private func performScreenshotRequest(shouldRetry: Bool, completion: @escaping (PlatformImage?) -> Void) {
        guard let url = URL(string: "http://\(serverAddress):\(screenshotServerPort)/") else {
            completion(nil)
            return
        }

        session.uncachedTask(with: url) { [weak self] data, response, error in
            guard let self = self else {
                completion(nil)
                return
            }

            if shouldRetry,
               shouldRetryDueToConnectivity(error: error, response: response)
            {
                let previousAddress = serverAddress
                if refreshServerAddress(previousAddress: previousAddress) != nil {
                    performScreenshotRequest(shouldRetry: false, completion: completion)
                    return
                }
            }

            if let error {
                errorCapturer.capture(error: error)
            }

            if let httpRes = response as? HTTPURLResponse {
                if httpRes.statusCode == 200, let data = data {
                    completion(PlatformImage(data: data))
                } else {
                    if (400...599).contains(httpRes.statusCode) {
                        let err = NSError(
                            domain: "IOSRuntime.HTTP",
                            code: httpRes.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "Screenshot request failed with status \(httpRes.statusCode) for \(url.absoluteString)"]
                        )
                        errorCapturer.capture(error: err)
                    }
                    logger.debug("Status code: \(httpRes.statusCode)")
                    completion(nil)
                }
            } else {
                completion(nil)
            }
        }.resume()
    }

    /// Sends an HTTP request and returns structured response including parsed JSON and body text.
    func sendRequest(_ request: URLRequest, shouldRetry: Bool = true, completion: @escaping (Response) -> Void) {
        session.uncachedTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                completion(Response(error: "Runtime unavailable"))
                return
            }

            if shouldRetry, shouldRetryDueToConnectivity(error: error, response: response) {
                let previousAddress = serverAddress
                if let newAddress = refreshServerAddress(previousAddress: previousAddress),
                   let updatedRequest = request.replacing(host: previousAddress, with: newAddress) {
                    sendRequest(updatedRequest, shouldRetry: false, completion: completion)
                    return
                }
            }

            var statusCode: Int?
            var contentType: String? = nil

            if let httpRes = response as? HTTPURLResponse {
                statusCode = httpRes.statusCode
                if let ct = httpRes.allHeaderFields["Content-Type"] as? String {
                    contentType = ct
                }
            }
            let bodyString = data.flatMap { String(data: $0, encoding: .utf8) }

            if let error = error {
                errorCapturer.capture(error: error)
            }

            var shouldParseJSON = false
            if let ct = contentType?.lowercased(), ct.contains("application/json") {
                shouldParseJSON = true
            }

            var errorString: String? = nil
            if shouldParseJSON, let data = data {
                do {
                    if let obj = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if let serverErr = obj["error"] as? String, !serverErr.isEmpty {
                            errorString = serverErr
                        }
                    } else {
                        errorString = "Failed to parse JSON: root is not an object"
                    }
                } catch {
                    errorString = "Failed to parse JSON: \(error.localizedDescription)"
                }
                if let jsonErr = errorString, jsonErr.hasPrefix("Failed to parse JSON") {
                    let parseErr = NSError(
                        domain: "IOSRuntime.JSON",
                        code: statusCode ?? -1,
                        userInfo: [
                            NSLocalizedDescriptionKey: jsonErr,
                            "response_body": bodyString ?? ""
                        ]
                    )
                    errorCapturer.capture(error: parseErr)
                }
            }

            if let code = statusCode, (400...599).contains(code) {
                let err = NSError(
                    domain: "IOSRuntime.HTTP",
                    code: code,
                    userInfo: [
                        NSLocalizedDescriptionKey: "HTTP error \(code) for \(request.url?.absoluteString ?? "unknown url")",
                        "response_body": bodyString ?? ""
                    ]
                )
                errorCapturer.capture(error: err)
                if errorString == nil {
                    errorString = (bodyString?.isEmpty == false) ? bodyString : "HTTP error \(code)"
                }
            } else if let error { // This handles non-HTTP errors (e.g. network connection lost)
                if errorString == nil {
                    errorString = error.localizedDescription
                }
            }

            let result = Response(error: errorString)
            completion(result)
        }.resume()
    }

    /// Simulates a tap at the given (x, y) location.
    func tapScreen(location: (Int, Int), longPress: Bool = false, completion: @escaping (Response) -> Void) {
        let (x, y) = location
        if let request = requestBuilder.buildRequest(for: .tap(x: x, y: y, isLong: longPress)) {
            sendRequest(request, completion: completion)
        } else {
            completion(Response(error: "Invalid tap request"))
        }
    }

    /// Simulates a zoom (pinch) gesture at the given (x, y) location.
    func zoom(location: (Int, Int), scale: Double, velocity: Double, completion: @escaping (Response) -> Void) {
        let (x, y) = location
        if let request = requestBuilder.buildRequest(for: .zoom(x: x, y: y, scale: scale, velocity: velocity)) {
            sendRequest(request, completion: completion)
        } else {
            completion(Response(error: "Invalid zoom request"))
        }
    }

    func openURL(urlString: String, completion: @escaping (Response) -> Void) {
        if let request = requestBuilder.buildRequest(for: .openURL(urlString: urlString)) {
            sendRequest(request, completion: completion)
        } else {
            completion(Response(error: "Invalid URL"))
        }
    }

    func shake(completion: @escaping (Response) -> Void) {
        if let request = requestBuilder.buildRequest(for: .shake) {
            sendRequest(request, completion: completion)
        } else {
            completion(Response(error: "Invalid shake URL"))
        }
    }

    /// Simulates a pan ("creep") at the given (x, y) location.
    func creep(location: (Int, Int), direction: String, amount: Int, completion: @escaping (Response) -> Void) {
        let (x, y) = location
        if let request = requestBuilder.buildRequest(for: .creep(x: x, y: y, direction: direction, amount: amount)) {
            sendRequest(request, completion: completion)
        } else {
            completion(Response(error: "Invalid creep request"))
        }
    }

    /// Simulates text input into an active text field.
    func input(text: String, completion: @escaping (Response) -> Void) {
        if let request = requestBuilder.buildRequest(for: .input(text: text)) {
            sendRequest(request, completion: completion)
        } else {
            completion(Response(error: "Invalid input request"))
        }
    }

    /// Clears the input field.
    func clearInputField(completion: @escaping (Response) -> Void) {
        if let request = requestBuilder.buildRequest(for: .clearInputField) {
            sendRequest(request, completion: completion)
        } else {
            completion(Response(error: "Invalid clear_input_field request"))
        }
    }

    /// Presses a hardware button on the device.
    func press(button: String, amount: Int = 1) {
        let buttonType = ButtonType(from: button) ?? .home

        do {
            for i in 0..<amount {
                // Send button down event
                try idbManager.pressButton(udid: deviceId, buttonType: buttonType, up: false)

                // Wait 50ms
                usleep(50_000)

                // Send button up event
                try idbManager.pressButton(udid: deviceId, buttonType: buttonType, up: true)

                // Wait 100ms between cycles (except for the last one)
                if i <= amount - 1 {
                    usleep(100_000)
                }
            }
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Failed to press button \(button): \(error.localizedDescription)")
        }
    }

    /// Checks if the keyboard is present on the screen.
    func hasKeyboard(completion: @escaping (Bool?) -> Void) {
        guard let request = requestBuilder.buildRequest(for: .hasKeyboard, waitForCompletion: true) else {
            completion(nil)
            return
        }
        session.uncachedTask(with: request) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let hasKeyboard = json["has_keyboard"] as? Bool {
                completion(hasKeyboard)
            } else {
                completion(nil)
            }
        }.resume()
    }

    /// Gets the UI hierarchy.
    func getHierarchy(completion: @escaping (String?) -> Void) {
        guard let request = requestBuilder.buildRequest(for: .getHierarchy, waitForCompletion: true) else {
            completion(nil)
            return
        }
        session.uncachedTask(with: request) { data, _, _ in
            if let data = data, let text = String(data: data, encoding: .utf8) {
                completion(text)
            } else {
                completion(nil)
            }
        }.resume()
    }

    func runCommand(_ commandName: String, commandArgs: [Any], completion: @escaping (Response) -> Void) {
        if commandName == "creep" {
            guard commandArgs.count == 4 else { return completion(Response(error: "creep requires 4 arguments: x, y, direction, amount")) }
            guard let x = commandArgs[0] as? Int else { return completion(Response(error: "creep: invalid x")) }
            guard let y = commandArgs[1] as? Int else { return completion(Response(error: "creep: invalid y")) }
            guard let direction = commandArgs[2] as? String else { return completion(Response(error: "creep: invalid direction")) }
            guard let distance = commandArgs[3] as? Int else { return completion(Response(error: "creep: invalid amount")) }
            creep(location: (x, y), direction: direction, amount: distance, completion: completion)
        } else if commandName == "tap" {
            guard (2...3).contains(commandArgs.count) else {
                return completion(Response(error: "tap requires 2 arguments: x, y and optional long flag"))
            }
            guard let x = commandArgs[0] as? Int else { return completion(Response(error: "tap: invalid x")) }
            guard let y = commandArgs[1] as? Int else { return completion(Response(error: "tap: invalid y")) }
            let longPress = (commandArgs.count == 3) ? (commandArgs[2] as? Bool ?? false) : false
            tapScreen(location: (x, y), longPress: longPress, completion: completion)
        } else if commandName == "zoom" {
            guard commandArgs.count == 4 else { return completion(Response(error: "zoom requires 4 arguments: x, y, scale, velocity")) }
            guard let x = commandArgs[0] as? Int else { return completion(Response(error: "zoom: invalid x")) }
            guard let y = commandArgs[1] as? Int else { return completion(Response(error: "zoom: invalid y")) }
            guard let scale = commandArgs[2] as? Double else { return completion(Response(error: "zoom: invalid scale")) }
            guard let velocity = commandArgs[3] as? Double else { return completion(Response(error: "zoom: invalid velocity")) }
            zoom(location: (x, y), scale: scale, velocity: velocity, completion: completion)
        } else if commandName == "input" {
            guard let inputString = commandArgs.first as? String else { return completion(Response(error: "input requires 1 argument: text")) }
            input(text: inputString, completion: completion)
        } else if commandName == "open_app" {
            guard let appName = commandArgs.first as? String else {
                return completion(Response(error: "open_app requires the app name as the first argument"))
            }

            var launchArguments: [String]? = nil
            var launchEnvironment: [String: String]? = nil

            for rawArg in commandArgs.dropFirst() {
                if rawArg is NSNull { continue }

                var handled = false

                if launchArguments == nil {
                    if let stringArray = rawArg as? [String] {
                        launchArguments = stringArray
                        handled = true
                    } else if let anyArray = rawArg as? [Any] {
                        let casted = anyArray.compactMap { $0 as? String }
                        if casted.count == anyArray.count {
                            launchArguments = casted
                            handled = true
                        } else {
                            return completion(Response(error: "open_app: launch arguments must all be strings"))
                        }
                    } else if let jsonString = rawArg as? String,
                              let data = jsonString.data(using: .utf8),
                              let decoded = try? JSONSerialization.jsonObject(with: data, options: []) as? [String]
                    {
                        launchArguments = decoded
                        handled = true
                    }
                }

                if handled {
                    continue
                }

                if launchEnvironment == nil {
                    if let stringDict = rawArg as? [String: String] {
                        launchEnvironment = stringDict
                        continue
                    } else if let anyDict = rawArg as? [String: Any] {
                        var casted: [String: String] = [:]
                        var success = true
                        for (key, value) in anyDict {
                            if let stringValue = value as? String {
                                casted[key] = stringValue
                            } else {
                                success = false
                                break
                            }
                        }
                        if success {
                            launchEnvironment = casted
                            continue
                        } else {
                            return completion(Response(error: "open_app: launch environment values must all be strings"))
                        }
                    } else if let jsonString = rawArg as? String,
                              let data = jsonString.data(using: .utf8),
                              let decoded = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String]
                    {
                        launchEnvironment = decoded
                        continue
                    }
                }

                if rawArg is String {
                    if launchArguments == nil {
                        return completion(Response(error: "open_app: invalid launch arguments"))
                    } else if launchEnvironment == nil {
                        return completion(Response(error: "open_app: invalid launch environment"))
                    }
                }

                return completion(Response(error: "open_app: unexpected argument format"))
            }

            if launchArguments?.isEmpty == true {
                launchArguments = nil
            }

            if launchEnvironment?.isEmpty == true {
                launchEnvironment = nil
            }

            openApp(name: appName, launchArguments: launchArguments, launchEnvironment: launchEnvironment, completion: completion)
        } else if commandName == "shake" {
            shake(completion: completion)
        } else if commandName == "clear_input_field" {
            clearInputField(completion: completion)
        } else if commandName == "grant_permission" {
            guard commandArgs.count == 2 else { return completion(Response(error: "grant_permission requires: permission, app")) }
            guard let permissionName = commandArgs[0] as? String, let permission = Permission(rawValue: permissionName) else { return completion(Response(error: "grant_permission: invalid permission")) }
            guard let appName = commandArgs[1] as? String else { return completion(Response(error: "grant_permission: invalid app name")) }
            deviceAdministration.grantPermission(permission, forApp: appName)
            completion(Response())
        } else if commandName == "reset_permissions" {
            guard let appName = commandArgs.first as? String else { return completion(Response(error: "reset_permissions requires: app")) }
            deviceAdministration.resetPermissions(forApp: appName)
            completion(Response())
        } else if commandName == "open_url" {
            guard let urlString = commandArgs.first as? String else { return completion(Response(error: "open_url requires: url")) }
            openURL(urlString: urlString, completion: completion)
        } else if commandName == "press" {
            guard let buttonName = commandArgs.first as? String else { return completion(Response(error: "press requires: button[, count]")) }
            let amount = commandArgs.count > 1 ? (commandArgs[1] as? Int ?? 1) : 1
            press(button: buttonName, amount: amount)
            completion(Response())
        } else if commandName == "set_time" {
            if let timeString = commandArgs.first as? String {
                deviceAdministration.setSystemTime(to: timeString)
            } else {
                deviceAdministration.setNetworkTimeToAuto()
            }
            completion(Response())
        } else if commandName == "user_defaults_set" {
            guard commandArgs.count >= 3,
                  let app = commandArgs[0] as? String else {
                return completion(.init(error: "user_defaults_set requires: app, path..., value"))
            }
            let pathSlice = commandArgs[1..<(commandArgs.count - 1)]
            let path = pathSlice.compactMap { $0 as? String }

            guard path.count == pathSlice.count else {
                return completion(.init(error: "user_defaults_set: all path elements must be strings"))
            }

            deviceAdministration.updateUserDefaults(forApp: app, path: path, value: commandArgs.last!)
            completion(Response())
        } else if commandName == "user_defaults_delete" {
            guard commandArgs.count >= 2,
                  let app = commandArgs[0] as? String else {
                return completion(.init(error: "user_defaults_delete requires: app, path..."))
            }

            let pathSlice = commandArgs[1...]
            let path = pathSlice.compactMap { $0 as? String }

            guard path.count == pathSlice.count else {
                return completion(.init(error: "user_defaults_delete: all path elements must be strings"))
            }

            deviceAdministration.updateUserDefaults(forApp: app, path: path, value: nil) // Pass nil to delete
            completion(Response())
        } else {
            completion(Response(error: "Unknown command: \(commandName)"))
        }
    }
}
