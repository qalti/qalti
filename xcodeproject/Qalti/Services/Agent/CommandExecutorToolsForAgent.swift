import Foundation
import AppKit

/// Tool response structure that mirrors the Python CommandExecutorToolsForLLM responses
struct ToolResponse: Codable {
    let success: Bool
    let message: String?
    let error: String?
    let imageJpegData: Data?
    let imageJpegURL: URL?
    
    // Command-specific fields
    let elementName: String?
    let text: String?
    let url: String?
    let appName: String?
    let direction: String?
    let amount: Double?
    let postActionDelay: Float?
    let coordinates: [String: Double]?
    let button: String?
    let count: Int?
    let longTap: Bool?
    let scale: Double?
    let velocity: Double?
    let launchArguments: [String]?
    let launchEnvironment: [String: String]?
    
    // CodingKeys to map Swift camelCase properties to JSON snake_case keys
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case error
        case imageJpegData = "image_jpeg_data"
        case imageJpegURL = "image_jpeg_url"
        case elementName = "element_name"
        case text
        case url
        case appName = "app_name"
        case direction
        case amount
        case postActionDelay = "post_action_delay"
        case coordinates
        case button
        case count
        case longTap = "long_tap"
        case scale
        case velocity
        case launchArguments = "launch_arguments"
        case launchEnvironment = "launch_environment"
    }
    
    // Computed property for base64 when needed for JSON serialization
    var image_base64: String? {
        guard let jpegData = imageJpegData else { return nil }
        return jpegData.base64EncodedString()
    }
    
    init(
        success: Bool,
        message: String? = nil,
        error: String? = nil,
        imageJpegData: Data? = nil,
        imageJpegURL: URL? = nil,
        elementName: String? = nil,
        text: String? = nil,
        url: String? = nil,
        appName: String? = nil,
        direction: String? = nil,
        amount: Double? = nil,
        postActionDelay: Float? = nil,
        coordinates: [String: Double]? = nil,
        button: String? = nil,
        count: Int? = nil,
        longTap: Bool? = nil,
        scale: Double? = nil,
        velocity: Double? = nil,
        launchArguments: [String]? = nil,
        launchEnvironment: [String: String]? = nil,
    ) {
        self.success = success
        self.message = message
        self.error = error
        self.imageJpegData = imageJpegData
        self.imageJpegURL = imageJpegURL
        self.elementName = elementName
        self.text = text
        self.url = url
        self.appName = appName
        self.direction = direction
        self.amount = amount
        self.postActionDelay = postActionDelay
        self.coordinates = coordinates
        self.button = button
        self.count = count
        self.longTap = longTap
        self.scale = scale
        self.velocity = velocity
        self.launchArguments = launchArguments
        self.launchEnvironment = launchEnvironment
    }
    
    /// Extract and remove image data, similar to Python's pop() method
    /// Returns a tuple of (extracted_jpeg_data, response_without_image)
    func popImage() -> (Data?, ToolResponse) {
        let extractedJpegData = self.imageJpegData
        let responseWithoutImage = ToolResponse(
            success: self.success,
            message: self.message,
            error: self.error,
            imageJpegData: nil, // Remove jpeg data
            elementName: self.elementName,
            text: self.text,
            url: self.url,
            appName: self.appName,
            direction: self.direction,
            amount: self.amount,
            postActionDelay: self.postActionDelay,
            coordinates: self.coordinates,
            button: self.button,
            count: self.count,
            longTap: self.longTap,
            scale: self.scale,
            velocity: self.velocity,
            launchArguments: self.launchArguments,
            launchEnvironment: self.launchEnvironment,
        )
        return (extractedJpegData, responseWithoutImage)
    }
    
    // MARK: - Static Factory Methods
    
    /// Create a success response with processed image data
    static func success(
        imageJpegData: Data?,
        imageJpegURL: URL?,
        elementName: String? = nil,
        text: String? = nil,
        url: String? = nil,
        appName: String? = nil,
        direction: String? = nil,
        amount: Double? = nil,
        postActionDelay: Float? = nil,
        coordinates: [String: Double]? = nil,
        button: String? = nil,
        count: Int? = nil,
        longTap: Bool? = nil,
        scale: Double? = nil,
        velocity: Double? = nil,
        launchArguments: [String]? = nil,
        launchEnvironment: [String: String]? = nil,
    ) -> ToolResponse {
        return ToolResponse(
            success: true,
            message: "No errors during the action. Verify the result",
            imageJpegData: imageJpegData,
            imageJpegURL: imageJpegURL,
            elementName: elementName,
            text: text,
            url: url,
            appName: appName,
            direction: direction,
            amount: amount,
            postActionDelay: postActionDelay,
            coordinates: coordinates,
            button: button,
            count: count,
            longTap: longTap,
            scale: scale,
            velocity: velocity,
            launchArguments: launchArguments,
            launchEnvironment: launchEnvironment,
        )
    }
    
    /// Create an error response with processed image data
    static func error(
        action: String,
        elementName: String,
        lastError: Error?,
        imageJpegData: Data?,
        imageJpegURL: URL?,
        direction: String? = nil,
        amount: Double? = nil,
        postActionDelay: Float? = nil,
        longTap: Bool? = nil,
        scale: Double? = nil,
        velocity: Double? = nil,
    ) -> ToolResponse {
        // Generate appropriate error message based on the type of failure
        let errorMessage: String
        if let error = lastError, let explainerError = error as? UIElementLocator.Error {
            switch explainerError {
            case .elementNotFound:
                errorMessage = Prompts.generateUIElementNotFoundError(action: action, elementName: elementName)
            case .connectionError, .noDataReceived, .invalidResponseFormat:
                errorMessage = Prompts.generateBackendConnectionError(action: action, elementName: elementName)
            default:
                errorMessage = Prompts.generateUnknownError(action: action, elementName: elementName)
            }
        } else {
            // No error or unknown error type - default to element not found
            errorMessage = Prompts.generateUnknownError(action: action, elementName: elementName)
        }
        
        return ToolResponse(
            success: false,
            error: errorMessage,
            imageJpegData: imageJpegData,
            imageJpegURL: imageJpegURL,
            elementName: elementName,
            direction: direction,
            amount: amount,
            postActionDelay: postActionDelay,
            longTap: longTap,
            scale: scale,
            velocity: velocity,
        )
    }

    /// Convenience initializer to build a response from runtime error string and image data
    init(
        runtimeError: String?,
        imageJpegData: Data?,
        imageJpegURL: URL?,
        elementName: String? = nil,
        text: String? = nil,
        url: String? = nil,
        appName: String? = nil,
        direction: String? = nil,
        amount: Double? = nil,
        postActionDelay: Float? = nil,
        coordinates: [String: Double]? = nil,
        button: String? = nil,
        count: Int? = nil,
        longTap: Bool? = nil,
        scale: Double? = nil,
        velocity: Double? = nil,
        launchArguments: [String]? = nil,
        launchEnvironment: [String: String]? = nil,
    ) {
        if let err = runtimeError, !err.isEmpty {
            self = ToolResponse(
                success: false,
                message: nil,
                error: err,
                imageJpegData: imageJpegData,
                imageJpegURL: imageJpegURL,
                elementName: elementName,
                text: text,
                url: url,
                appName: appName,
                direction: direction,
                amount: amount,
                postActionDelay: postActionDelay,
                coordinates: coordinates,
                button: button,
                count: count,
                longTap: longTap,
                scale: scale,
                velocity: velocity,
                launchArguments: launchArguments,
                launchEnvironment: launchEnvironment,
            )
        } else {
            self = ToolResponse.success(
                imageJpegData: imageJpegData,
                imageJpegURL: imageJpegURL,
                elementName: elementName,
                text: text,
                url: url,
                appName: appName,
                direction: direction,
                amount: amount,
                postActionDelay: postActionDelay,
                coordinates: coordinates,
                button: button,
                count: count,
                longTap: longTap,
                scale: scale,
                velocity: velocity,
                launchArguments: launchArguments,
                launchEnvironment: launchEnvironment,
            )
        }
    }
}

/// Swift equivalent of Python's CommandExecutorToolsForLLM
/// Provides a controlled interface for LLMs to interact with iOS automation
class CommandExecutorToolsForAgent {
    private let runtime: IOSRuntime
    private let elementLocator: UIElementLocator
    private let screenshotUploader: ScreenshotUploader
    private let agentImageSize: Int
    private let pointOutImageSize: Int
    private let workingDirectoryForBash: URL
    private let actionQueue = DispatchQueue(label: "CommandExecutorToolsForAgent.actionQueue", qos: .userInitiated)

    init(
        runtime: IOSRuntime,
        elementLocator: UIElementLocator,
        screenshotUploader: ScreenshotUploader,
        agentImageSize: Int,
        pointOutImageSize: Int,
        workingDirectoryForBash: URL
    ) {
        self.runtime = runtime
        self.elementLocator = elementLocator
        self.screenshotUploader = screenshotUploader
        self.agentImageSize = agentImageSize
        self.pointOutImageSize = pointOutImageSize
        self.workingDirectoryForBash = workingDirectoryForBash
    }

    // Centralized response builder replaced by ToolResponse convenience init

    private func takeScreenshot(customSize: Int? = nil, completion: @escaping (IOSRuntime.Response) -> Void) {
        runtime.takeScreenshot { [weak self] (image: PlatformImage?) in
            guard let self, let image else { return completion(IOSRuntime.Response(error: "Failed to take screenshot")) }
            let resizedImage = image.resized(toHeight: customSize ?? agentImageSize)
            screenshotUploader.uploadScreenshot(image: resizedImage) { uploadResult in
                switch uploadResult {
                case .success(let imageURL):
                    // Return the original image so we can convert normalized point-out coordinates
                    // back into original pixels for tap/zoom/move_finger.
                    completion(IOSRuntime.Response(image: image, imageURL: imageURL))
                case .failure:
                    completion(IOSRuntime.Response(image: image, imageURL: nil))
                }
            }
        }
    }

    private func resizedDimensions(for image: PlatformImage, targetHeight: Int) -> (width: Int, height: Int) {
        let originalWidth = max(1.0, Double(image.size.width))
        let originalHeight = max(1.0, Double(image.size.height))
        let scale = Double(targetHeight) / originalHeight
        let resizedWidth = max(1, Int(round(originalWidth * scale)))
        return (width: resizedWidth, height: max(1, targetHeight))
    }

    static func pixelCoordinates(
        relativeCoordinates: UIElementLocator.PointOutResponse.Coordinates?,
        originalSize: CGSize
    ) -> (x: Int, y: Int)? {
        guard let coords = relativeCoordinates,
              coords.x.isFinite,
              coords.y.isFinite,
              originalSize.width > 0,
              originalSize.height > 0 else {
            return nil
        }

        let x = Int(coords.x * Double(originalSize.width))
        let y = Int(coords.y * Double(originalSize.height))
        return (x, y)
    }

    /// Common pattern for executing action with screenshot and completion
    private func executeActionWithScreenshot(
        action: @escaping (@escaping (IOSRuntime.Response) -> Void) -> Void,
        postActionDelay: Float,
        completion: @escaping (IOSRuntime.Response) -> Void
    ) {
        actionQueue.async { [weak self] in
            guard let self else { return }
            action { [weak self] runtimeResponse in
                guard let self else { return }
                // If runtime returned an error, short-circuit without waiting or taking a screenshot
                // see how elementLocator.pointOutObject( is used at CommandExecutorToolsForAgent.swift
                if let err = runtimeResponse.error, !err.isEmpty {
                    completion(runtimeResponse)
                    return
                }

                let effectiveDelaySeconds = TimeInterval(postActionDelay)
                actionQueue.asyncAfter(deadline: .now() + effectiveDelaySeconds) { [weak self] in
                    guard let self else { return completion(runtimeResponse) }
                    self.takeScreenshot { screenshotResponse in
                        completion(runtimeResponse.withScreenshot(image: screenshotResponse.image, imageURL: screenshotResponse.imageURL))
                    }
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Take a screenshot of the iOS simulator
    func screenshot(completion: @escaping (ToolResponse) -> Void) {
        takeScreenshot { runtimeResponse in
            let response = ToolResponse.success(
                imageJpegData: runtimeResponse.imageJpegData,
                imageJpegURL: runtimeResponse.imageURL
            )
            completion(response)
        }
    }
    
    /// Tap on the specified element in the iOS simulator
    func tap(elementName: String, postActionDelay: Float, longTap: Bool, completion: @escaping (ToolResponse) -> Void) {
        takeScreenshot(customSize: pointOutImageSize) { [weak self] (screenshotResponse: IOSRuntime.Response) in
            let tapError: (Error?) -> ToolResponse = { lastError in
                return ToolResponse.error(
                    action: "tap",
                    elementName: elementName,
                    lastError: lastError,
                    imageJpegData: screenshotResponse.imageJpegData,
                    imageJpegURL: screenshotResponse.imageURL,
                    longTap: longTap
                )
            }
                
            guard let self, let image = screenshotResponse.image, let imageURL = screenshotResponse.imageURL else {
                return completion(tapError(nil))
            }
            let resized = resizedDimensions(for: image, targetHeight: pointOutImageSize)

            // Use unified pointout method with image URL
            elementLocator.pointOutObject(
                input: .url(imageURL, width: resized.width, height: resized.height),
                objectDescription: elementName
            ) { [weak self] result in
                guard let self else { return }
                
                switch result {
                case .success(let content):
                    if let coords = Self.pixelCoordinates(relativeCoordinates: content.coordinates, originalSize: image.size) {
                        let coordinates = ["x": Double(coords.x), "y": Double(coords.y)]
                        executeActionWithScreenshot(
                            action: { [runtime] actionCompletion in
                                runtime.tapScreen(
                                    location: (coords.x, coords.y),
                                    longPress: longTap,
                                    completion: actionCompletion
                                )
                            },
                            postActionDelay: postActionDelay
                        ) { runtimeResponse in
                            let response = ToolResponse(
                                runtimeError: runtimeResponse.error,
                                imageJpegData: runtimeResponse.imageJpegData,
                                imageJpegURL: runtimeResponse.imageURL,
                                elementName: elementName,
                                coordinates: coordinates,
                                longTap: longTap
                            )
                            completion(response)
                        }
                    } else {
                        completion(tapError(nil))
                    }
                case .failure(let error):
                    completion(tapError(error))
                }
            }
        }
    }

    /// Perform a zoom (pinch) gesture on the specified element.
    func zoom(elementName: String, scale: Double, velocity: Double, postActionDelay: Float, completion: @escaping (ToolResponse) -> Void) {
        // Take a screenshot to locate the element.
        takeScreenshot(customSize: pointOutImageSize) { [weak self] (screenshotResponse: IOSRuntime.Response) in
            let zoomError: (Error?) -> ToolResponse = { lastError in
                return ToolResponse.error(
                    action: "zoom",
                    elementName: elementName,
                    lastError: lastError,
                    imageJpegData: screenshotResponse.imageJpegData,
                    imageJpegURL: screenshotResponse.imageURL,
                    scale: scale,
                    velocity: velocity
                )
            }
            
            guard let self, let image = screenshotResponse.image, let imageURL = screenshotResponse.imageURL else {
                return completion(zoomError(nil))
            }
            let resized = resizedDimensions(for: image, targetHeight: pointOutImageSize)

            // Use the screenshot to find the coordinates of the element.
            elementLocator.pointOutObject(
                input: .url(imageURL, width: resized.width, height: resized.height),
                objectDescription: elementName
            ) { [weak self] result in
                guard let self else { return }
                
                switch result {
                case .success(let content):
                    if let coords = Self.pixelCoordinates(relativeCoordinates: content.coordinates, originalSize: image.size) {
                        let coordinates = ["x": Double(coords.x), "y": Double(coords.y)]
                        
                        // Execute the action and get the screenshot *after* the action is complete.
                        executeActionWithScreenshot(
                            action: { [runtime] actionCompletion in
                                runtime.zoom(
                                    location: (coords.x, coords.y),
                                    scale: scale,
                                    velocity: velocity,
                                    completion: actionCompletion
                                )
                            },
                            postActionDelay: postActionDelay
                        ) { runtimeResponse in
                            // Construct the response using the raw, unmodified "after" screenshot.
                            // The special marker for the logs will be drawn later by the logging logic.
                            let response = ToolResponse(
                                runtimeError: runtimeResponse.error,
                                imageJpegData: runtimeResponse.imageJpegData,
                                imageJpegURL: runtimeResponse.imageURL,
                                elementName: elementName,
                                coordinates: coordinates,
                                scale: scale,
                                velocity: velocity
                            )
                            completion(response)
                        }
                    } else {
                        completion(zoomError(nil))
                    }
                case .failure(let error):
                    completion(zoomError(error))
                }
            }
        }
    }
    
    /// Input text into the active text field
    func input(text: String, completion: @escaping (ToolResponse) -> Void) {
        executeActionWithScreenshot(
            action: { [weak self] actionCompletion in 
                self?.runtime.input(text: text, completion: actionCompletion)
            },
            postActionDelay: 0.3
        ) { runtimeResponse in
            let response = ToolResponse(
                runtimeError: runtimeResponse.error,
                imageJpegData: runtimeResponse.imageJpegData,
                imageJpegURL: runtimeResponse.imageURL,
                text: text
            )
            completion(response)
        }
    }
    
    /// Open a URL in the iOS
    func open_url(url: String, postActionDelay: Float, completion: @escaping (ToolResponse) -> Void) {
        executeActionWithScreenshot(
            action: { [weak self] actionCompletion in 
                self?.runtime.openURL(urlString: url, completion: actionCompletion)
            },
            postActionDelay: postActionDelay
        ) { runtimeResponse in
            let response = ToolResponse(
                runtimeError: runtimeResponse.error,
                imageJpegData: runtimeResponse.imageJpegData,
                imageJpegURL: runtimeResponse.imageURL,
                url: url
            )
            completion(response)
        }
    }
    
    /// Perform a move finger gesture from the specified element
    func move_finger(elementName: String, direction: String, amount: Double, postActionDelay: Float, completion: @escaping (ToolResponse) -> Void) {
        takeScreenshot(customSize: pointOutImageSize) { [weak self] (screenshotResponse: IOSRuntime.Response) in
            let moveFingerError: (Error?) -> ToolResponse = { lastError in
                return ToolResponse.error(
                    action: "move_finger",
                    elementName: elementName,
                    lastError: lastError,
                    imageJpegData: screenshotResponse.imageJpegData,
                    imageJpegURL: screenshotResponse.imageURL,
                    direction: direction,
                    amount: amount
                )
            }
                
            guard let self, let image = screenshotResponse.image, let imageURL = screenshotResponse.imageURL else {
                return completion(moveFingerError(nil))
            }
            let resized = resizedDimensions(for: image, targetHeight: pointOutImageSize)

            // Use unified pointout method with image URL
            elementLocator.pointOutObject(
                input: .url(imageURL, width: resized.width, height: resized.height),
                objectDescription: elementName
            ) { [weak self] result in
                guard let self else { return }
                
                switch result {
                case .success(let content):
                    if let coords = Self.pixelCoordinates(relativeCoordinates: content.coordinates, originalSize: image.size) {
                        let coordinates = ["x": Double(coords.x), "y": Double(coords.y)]
                        let moveAmount = amount < 2.0 ? Int(amount * image.size.height) : Int(amount)

                        executeActionWithScreenshot(
                            action: { [runtime] actionCompletion in
                                runtime.creep(location: (coords.x, coords.y), direction: direction, amount: moveAmount, completion: actionCompletion)
                            },
                            postActionDelay: postActionDelay
                        ) { runtimeResponse in
                            let response = ToolResponse(
                                runtimeError: runtimeResponse.error,
                                imageJpegData: runtimeResponse.imageJpegData,
                                imageJpegURL: runtimeResponse.imageURL,
                                elementName: elementName,
                                direction: direction,
                                amount: amount,
                                coordinates: coordinates
                            )
                            completion(response)
                        }
                    } else {
                        completion(moveFingerError(nil))
                    }
                case .failure(let error):
                    completion(moveFingerError(error))
                }
            }
        }
    }
    
    /// Switch to the specified app
    func open_app(name: String, launchArguments: [String]?, launchEnvironment: [String: String]?, completion: @escaping (ToolResponse) -> Void) {
        executeActionWithScreenshot(
            action: { [weak self] actionCompletion in 
                self?.runtime.openApp(name: name, launchArguments: launchArguments, launchEnvironment: launchEnvironment, completion: actionCompletion)
            },
            postActionDelay: 5.0
        ) { runtimeResponse in
            let response = ToolResponse(
                runtimeError: runtimeResponse.error,
                imageJpegData: runtimeResponse.imageJpegData,
                imageJpegURL: runtimeResponse.imageURL,
                appName: name,
                launchArguments: launchArguments,
                launchEnvironment: launchEnvironment
            )
            completion(response)
        }
    }
    
    /// Clear the currently active input field
    func clear_input_field(completion: @escaping (ToolResponse) -> Void) {
        executeActionWithScreenshot(
            action: { [weak self] actionCompletion in 
                self?.runtime.clearInputField(completion: actionCompletion)
            },
            postActionDelay: 0.5
        ) { runtimeResponse in
            let response = ToolResponse(
                runtimeError: runtimeResponse.error,
                imageJpegData: runtimeResponse.imageJpegData,
                imageJpegURL: runtimeResponse.imageURL
            )
            completion(response)
        }
    }
    
    /// Shake the iOS device/simulator
    func shake(completion: @escaping (ToolResponse) -> Void) {
        executeActionWithScreenshot(
            action: { [weak self] actionCompletion in 
                self?.runtime.shake(completion: actionCompletion)
            },
            postActionDelay: 1.0
        ) { runtimeResponse in
            let response = ToolResponse(
                runtimeError: runtimeResponse.error,
                imageJpegData: runtimeResponse.imageJpegData,
                imageJpegURL: runtimeResponse.imageURL
            )
            completion(response)
        }
    }
    
    /// Wait for a specified duration
    func wait(duration: Float, completion: @escaping (ToolResponse) -> Void) {
        actionQueue.asyncAfter(deadline: .now() + .milliseconds(Int(duration * 1000))) { [weak self] in
            self?.takeScreenshot { runtimeResponse in
                let response = ToolResponse.success(
                    imageJpegData: runtimeResponse.imageJpegData,
                    imageJpegURL: runtimeResponse.imageURL,
                    postActionDelay: duration
                )
                completion(response)
            }
        }
    }
    
    /// Press a hardware button
    func press(button: String, count: Int, completion: @escaping (ToolResponse) -> Void) {
        executeActionWithScreenshot(
            action: { [weak self] actionCompletion in 
                self?.runtime.press(button: button, amount: count)
                // Provide a synthesized success response for local actions
                actionCompletion(IOSRuntime.Response())
            },
            postActionDelay: 1.0
        ) { runtimeResponse in
            let response = ToolResponse(
                runtimeError: runtimeResponse.error,
                imageJpegData: runtimeResponse.imageJpegData,
                imageJpegURL: runtimeResponse.imageURL,
                button: button,
                count: count
            )
            completion(response)
        }
    }

    /// Run a bash script (provided inline) from the test directory
    func run_script(script: String, errorCapturer: ErrorCapturing, completion: @escaping (ToolResponse) -> Void) {
        actionQueue.async { [weak self] in
            guard let self else { return }

            let workingDirectory = self.workingDirectoryForBash

            let scriptContent = script.trimmingCharacters(in: .whitespacesAndNewlines)
            guard scriptContent.isEmpty == false else {
                self.takeScreenshot { runtimeResponse in
                    let response = ToolResponse(
                        success: false,
                        message: nil,
                        error: "run_script command requires non-empty script content",
                        imageJpegData: runtimeResponse.imageJpegData,
                        imageJpegURL: runtimeResponse.imageURL
                    )
                    completion(response)
                }
                return
            }

            let executionResult: IOSRuntimeUtils.BashScriptResult
            let runtimeUtils = IOSRuntimeUtils(errorCapturer: errorCapturer)
            do {
                executionResult = try runtimeUtils.runBashScript(
                    scriptContent,
                    workingDirectory: workingDirectory,
                    environment: ProcessInfo.processInfo.environment
                )
            } catch {
                self.takeScreenshot { runtimeResponse in
                    let response = ToolResponse(
                        success: false,
                        message: nil,
                        error: "Failed to start script: \(error.localizedDescription)",
                        imageJpegData: runtimeResponse.imageJpegData,
                        imageJpegURL: runtimeResponse.imageURL
                    )
                    completion(response)
                }
                return
            }

            self.takeScreenshot { runtimeResponse in
                var combinedMessage: String? = executionResult.stdout.isEmpty ? nil : executionResult.stdout
                if executionResult.exitCode == 0, !executionResult.stderr.isEmpty {
                    if let message = combinedMessage, !message.isEmpty {
                        combinedMessage = message + "\n" + executionResult.stderr
                    } else {
                        combinedMessage = executionResult.stderr
                    }
                }

                var errorText: String? = nil
                if executionResult.exitCode != 0 {
                    if !executionResult.stderr.isEmpty {
                        errorText = executionResult.stderr + "\nScript exited with code \(executionResult.exitCode)"
                    } else {
                        errorText = "Script exited with code \(executionResult.exitCode)"
                    }
                } else if !executionResult.stderr.isEmpty, combinedMessage == nil {
                    combinedMessage = executionResult.stderr
                }

                let baseMessage: String = {
                    if let combinedMessage, !combinedMessage.isEmpty {
                        return combinedMessage
                    }
                    if executionResult.exitCode == 0 {
                        return "Script executed successfully."
                    }
                    return "Script execution completed with no output."
                }()

                let response = ToolResponse(
                    success: executionResult.exitCode == 0,
                    message: baseMessage,
                    error: errorText,
                    imageJpegData: runtimeResponse.imageJpegData,
                    imageJpegURL: runtimeResponse.imageURL
                )
                completion(response)
            }
        }
    }
    
    /// Execute a command and return JSON response
    func executeCommand(_ command: TargetCommand, errorCapturer: ErrorCapturing, completion: @escaping (ToolResponse) -> Void) {
        switch command {
        case .open_url(let urlString, let postActionDelay):
            open_url(url: urlString, postActionDelay: postActionDelay) { completion($0) }
        case .openApp(let name, let launchArguments, let launchEnvironment):
            open_app(name: name, launchArguments: launchArguments, launchEnvironment: launchEnvironment) { completion($0) }
        case .tap(let elementName, let postActionDelay, let longTap):
            tap(elementName: elementName, postActionDelay: postActionDelay, longTap: longTap) { completion($0) }
        case .zoom(let elementName, let scale, let velocity, let postActionDelay):
            zoom(elementName: elementName, scale: scale, velocity: velocity, postActionDelay: postActionDelay) { completion($0) }
        case .move_finger(let elementName, let direction, let amount, let postActionDelay):
            move_finger(elementName: elementName, direction: direction.rawValue, amount: amount, postActionDelay: postActionDelay) { completion($0) }
        case .input(let text):
            input(text: text) { completion($0) }
        case .clearInputField:
            clear_input_field() { completion($0) }
        case .shake:
            shake() { completion($0) }
        case .screenshot:
            screenshot() { completion($0) }
        case .wait(let duration):
            wait(duration: duration) { completion($0) }
        case .press(let button, let amount):
            press(button: button, count: amount) { completion($0) }
        case .runScript(let script):
            run_script(script: script, errorCapturer: errorCapturer) { completion($0) }
        }
    }
}
