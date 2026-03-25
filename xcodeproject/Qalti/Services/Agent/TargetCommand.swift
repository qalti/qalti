//
//  CommandDecoder.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 15.09.2025.
//
import Foundation
import Logging
@preconcurrency import OpenAI

/// Specific errors for command decoding that provide helpful guidance to the agent
///
/// Examples of error handling:
///
/// 1. Missing required argument:
///    Agent sends: {"direction": "right"} for move_finger function (missing element_name)
///    Response: "Function 'move_finger' is missing required argument 'element_name'. Correct example: {"element_name": "slider", "direction": "right", "amount": 100}"
///
/// 2. Invalid argument value:
///    Agent sends: {"element_name": "button", "direction": "upward", "amount": 50} for move_finger
///    Response: "Function 'move_finger' has invalid value 'upward' for argument 'direction'. Allowed values: up, down, left, right"
///
/// 3. Unknown function:
///    Agent sends: unknown_function_call
///    Response: "Unknown function 'unknown_function_call' called. Available functions: open_app, tap, move_finger, input, ..."
enum CommandDecodingError: Swift.Error, LocalizedError {
    case missingRequiredArgument(functionName: String, missingArgument: String, providedArguments: String, example: String, additionalInfo: String? = nil)
    case invalidArgumentValue(functionName: String, argumentName: String, providedValue: String, allowedValues: [String], providedArguments: String)
    case invalidArguments(functionName: String, providedArguments: String, message: String)
    case unknownFunction(functionName: String, providedArguments: String, availableFunctions: [String])

    var errorDescription: String? {
        switch self {
        case .missingRequiredArgument(let functionName, let missingArgument, let providedArguments, let example, let additionalInfo):
            var message = """
            Function '\(functionName)' is missing required argument '\(missingArgument)'.
            Provided arguments: \(providedArguments)
            Correct example: \(example)
            """
            if let info = additionalInfo {
                message += "\n\nNote: \(info)"
            }
            return message

        case .invalidArgumentValue(let functionName, let argumentName, let providedValue, let allowedValues, let providedArguments):
            return """
            Function '\(functionName)' has invalid value '\(providedValue)' for argument '\(argumentName)'.
            Provided arguments: \(providedArguments)
            Allowed values for '\(argumentName)': \(allowedValues.joined(separator: ", "))
            Please use one of the allowed values.
            """

        case .invalidArguments(let functionName, let providedArguments, let message):
            return """
            Function '\(functionName)' has invalid arguments format.
            Provided arguments: \(providedArguments)
            Error: \(message)
            Please ensure arguments are in valid JSON format.
            """

        case .unknownFunction(let functionName, let providedArguments, let availableFunctions):
            return """
            Unknown function '\(functionName)' called.
            Provided arguments: \(providedArguments)
            Available functions: \(availableFunctions.joined(separator: ", "))
            Please use one of the available functions.
            """
        }
    }

    // MARK: - Static Factory Methods

    static func appNameMissing(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "app_name",
            providedArguments: call.arguments,
            example: #"{"app_name": "Settings"}"#
        )
    }

    static func elementNameMissing(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "element_name",
            providedArguments: call.arguments,
            example: #"{"element_name": "Login button"}"#,
            additionalInfo: "Use 'element_name' to specify the UI element to tap."
        )
    }

    static func elementNameMissingForMoveFinger(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "element_name",
            providedArguments: call.arguments,
            example: #"{"element_name": "slider", "direction": "right", "amount": 100, "post_action_delay": 0.3}"#,
            additionalInfo: "Use 'element_name' to specify the UI element to move from."
        )
    }

    static func directionMissing(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "direction",
            providedArguments: call.arguments,
            example: #"{"element_name": "slider", "direction": "right", "amount": 100, "post_action_delay": 0.3}"#,
            additionalInfo: "Direction must be one of: 'up', 'down', 'left', 'right'"
        )
    }

    static func invalidDirection(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall, providedValue: String) -> CommandDecodingError {
        return .invalidArgumentValue(
            functionName: call.name,
            argumentName: "direction",
            providedValue: providedValue,
            allowedValues: ["up", "down", "left", "right"],
            providedArguments: call.arguments
        )
    }

    static func amountMissing(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "amount",
            providedArguments: call.arguments,
            example: #"{"element_name": "slider", "direction": "right", "amount": 100, "post_action_delay": 0.3}"#,
            additionalInfo: "Amount should be a number (pixels if > 1.0, or percentage if <= 1.0)"
        )
    }

    static func textMissing(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "text",
            providedArguments: call.arguments,
            example: #"{"text": "Hello World"}"#
        )
    }

    static func urlMissing(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "url",
            providedArguments: call.arguments,
            example: #"{"url": "https://example.com"}"#
        )
    }

    static func buttonMissing(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "button",
            providedArguments: call.arguments,
            example: #"{"button": "home", "count": 1}"#,
            additionalInfo: "Common buttons: 'home', 'volumeUp', 'volumeDown', 'power'"
        )
    }

    static func postActionDelayMissing(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "post_action_delay",
            providedArguments: call.arguments,
            example: #"{"element_name": "Login button", "post_action_delay": 0.5}"#,
            additionalInfo: "post_action_delay should be in seconds: 0.1 for quick actions, 0.5 for standard UI transitions, 1.5 for screen changes, 3.0 for loading, 5.0 for heavy operations"
        )
    }

    static func postActionDelayMissingForOpenUrl(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "post_action_delay",
            providedArguments: call.arguments,
            example: #"{"url": "https://example.com", "post_action_delay": 3.0}"#,
            additionalInfo: "post_action_delay should be in seconds: 0.3 for quick URL handling, 1.5 for standard app launches, 3.0 for network requests, 5.0 for heavy operations"
        )
    }

    static func durationMissing(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "duration",
            providedArguments: call.arguments,
            example: #"{"duration": 1.0}"#,
            additionalInfo: "Duration should be in seconds"
        )
    }

    static func scaleMissing(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "scale",
            providedArguments: call.arguments,
            example: #"{"element_name": "map view", "scale": 2.0, "velocity": 1.0, "post_action_delay": 0.5}"#,
            additionalInfo: "Scale > 1 zooms in, Scale < 1 zooms out."
        )
    }

    static func velocityMissing(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "velocity",
            providedArguments: call.arguments,
            example: #"{"element_name": "map view", "scale": 2.0, "velocity": 1.0, "post_action_delay": 0.5}"#,
            additionalInfo: "Velocity is the speed of the gesture in scale factor per second."
        )
     }

    static func scriptMissing(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .missingRequiredArgument(
            functionName: call.name,
            missingArgument: "script",
            providedArguments: call.arguments,
            example: #"{"script": "set -e\nnpm install"}"#,
            additionalInfo: "Provide the full script content. If you need to execute an existing file, construct a script that calls it (e.g., bash ./setup.sh)."
        )
    }

    static func invalidArguments(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall, message: String) -> CommandDecodingError {
        return .invalidArguments(
            functionName: call.name,
            providedArguments: call.arguments,
            message: message
        )
    }

    static func unknownFunction(_ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) -> CommandDecodingError {
        return .unknownFunction(
            functionName: call.name,
            providedArguments: call.arguments,
            availableFunctions: ["open_app", "tap", "zoom", "move_finger", "input", "clear_input_field", "shake", "screenshot", "wait", "open_url", "press_button", "run_script"]
        )
    }
}

/// Represents exactly one of the iOS‑tool actions returned by the model.
enum TargetCommand {
    private static let logger = AppLogging.logger("TargetCommand")
    case open_url(urlString: String, postActionDelay: Float)
    case openApp(name: String, launchArguments: [String]?, launchEnvironment: [String: String]?)
    case tap(elementName: String, postActionDelay: Float, isLongTap: Bool)
    case zoom(elementName: String, scale: Double, velocity: Double, postActionDelay: Float)
    case move_finger(elementName: String, direction: Direction, amount: Double, postActionDelay: Float)
    case input(text: String)
    case clearInputField
    case shake
    case screenshot
    case wait(duration: Float)
    case press(button: String, amount: Int)
    case runScript(script: String)

    enum Direction: String, Codable { case up, down, left, right }

    func toString() -> String {
        switch self {
        case .open_url(urlString: let urlString, let postActionDelay):
            return #"open_url(url="\#(urlString)", post_action_delay=\#(postActionDelay))"#
        case .openApp(name: let name, launchArguments: let launchArguments, launchEnvironment: let launchEnvironment):
            var parts: [String] = [#"app_name="\#(name)""#]
            if let launchArguments, !launchArguments.isEmpty {
                let args = launchArguments.map { #""\#($0)""# }.joined(separator: ", ")
                parts.append("launch_arguments=[\(args)]")
            }
            if let launchEnvironment, !launchEnvironment.isEmpty {
                let kv = launchEnvironment.map { #""\#($0.key)":"\#($0.value)""# }.joined(separator: ", ")
                parts.append("launch_environment={\(kv)}")
            }
            return "open_app(\(parts.joined(separator: ", ")))"
        case .tap(elementName: let elementName, postActionDelay: let postActionDelay, isLongTap: let isLongTap):
            var parts: [String] = [#"element_name="\#(elementName)""#, "post_action_delay=\(postActionDelay)"]
            if isLongTap { parts.append("long_tap=true") }
            return "tap(\(parts.joined(separator: ", ")))"
        case .zoom(elementName: let elementName, scale: let scale, velocity: let velocity, postActionDelay: let postActionDelay):
            return #"zoom(element_name="\#(elementName)", scale=\#(scale), velocity=\#(velocity), post_action_delay=\#(postActionDelay))"#
        case .move_finger(elementName: let elementName, direction: let direction, amount: let amount, postActionDelay: let postActionDelay):
            let amountDisplay: String = amount > 1.0 ? String(Int(amount)) : String(amount)
            return #"move_finger(element_name="\#(elementName)", direction="\#(direction.rawValue)", amount=\#(amountDisplay), post_action_delay=\#(postActionDelay))"#
        case .input(text: let text):
            return #"input(text="\#(text)")"#
        case .clearInputField:
            return "clear_input_field()"
        case .shake:
            return "shake()"
        case .screenshot:
            return "screenshot()"
        case .wait(duration: let duration):
            return "wait(duration=\(duration))"
        case .press(button: let button, amount: let amount):
            if amount == 1 {
                return #"press(button="\#(button)")"#
            } else {
                return #"press(button="\#(button)", count=\#(amount))"#
            }
        case .runScript(script: let script):
            // Show actual script content in logs
            // Escape any embedded double quotes for a stable display
            let escaped = script.replacingOccurrences(of: "\"", with: "\\\"")
            return #"run_script(script="\#(escaped)")"#
        }
    }

    init(from call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall) throws {
        struct Raw: Decodable {
            let appName: String?
            let launchArguments: [String]?
            let launchEnvironment: [String: String]?
            let elementName: String?
            let direction: String?
            let amount: Double?
            let text: String?
            let reason: String?
            let onboarding: Bool?
            let unboxing: Bool?
            let url: String?
            let duration: Float?
            let button: String?
            let count: Int?
            let postActionDelay: Float?
            let longTap: Bool?
            let scale: Double?
            let velocity: Double?
            let script: String?

            enum CodingKeys: String, CodingKey {
                case appName = "app_name"
                case launchArguments = "launch_arguments"
                case launchEnvironment = "launch_environment"
                case elementName = "element_name"
                case direction
                case amount
                case text
                case reason
                case onboarding
                case unboxing
                case url
                case duration
                case button
                case count
                case postActionDelay = "post_action_delay"
                case longTap = "long_tap"
                case scale
                case velocity
                case script
            }
        }

        let raw: Raw

        if call.arguments.trimmingCharacters(in: .whitespacesAndNewlines).count == 0 {
            raw = Raw(
                appName: nil,
                launchArguments: nil,
                launchEnvironment: nil,
                elementName: nil,
                direction: nil,
                amount: nil,
                text: nil,
                reason: nil,
                onboarding: nil,
                unboxing: nil,
                url: nil,
                duration: nil,
                button: nil,
                count: nil,
                postActionDelay: nil,
                longTap: nil,
                scale: nil,
                velocity: nil,
                script: nil
            )
        } else if let argsData = call.arguments.data(using: .utf8),
                  let parsedRaw = try? JSONDecoder().decode(Raw.self, from: argsData)
        {
            raw = parsedRaw
        } else {
            Self.logger.error("Failed to decode arguments: \(call.arguments)")
            throw CommandDecodingError.invalidArguments(call, message: "Unable to parse JSON arguments. Please ensure arguments are valid JSON format.")
        }

        switch call.name {
        case "open_app":
            guard let appName = raw.appName else {
                throw CommandDecodingError.appNameMissing(call)
            }
            let normalizedArguments = (raw.launchArguments?.isEmpty == true) ? nil : raw.launchArguments
            let normalizedEnvironment = (raw.launchEnvironment?.isEmpty == true) ? nil : raw.launchEnvironment
            self = .openApp(name: appName, launchArguments: normalizedArguments, launchEnvironment: normalizedEnvironment)

        case "tap":
            guard let element = raw.elementName else {
                throw CommandDecodingError.elementNameMissing(call)
            }
            guard let postActionDelay = raw.postActionDelay else {
                throw CommandDecodingError.postActionDelayMissing(call)
            }
            let isLongTap = raw.longTap ?? false
            self = .tap(elementName: element, postActionDelay: postActionDelay, isLongTap: isLongTap)

        case "zoom":
            guard let element = raw.elementName else {
                throw CommandDecodingError.elementNameMissing(call)
            }
            guard let scale = raw.scale else {
                throw CommandDecodingError.scaleMissing(call)
            }
            guard let velocity = raw.velocity else {
                throw CommandDecodingError.velocityMissing(call)
            }
            guard let postActionDelay = raw.postActionDelay else {
                throw CommandDecodingError.postActionDelayMissing(call)
            }
            self = .zoom(elementName: element, scale: scale, velocity: velocity, postActionDelay: postActionDelay)

        case "move_finger":
            guard let element = raw.elementName else {
                throw CommandDecodingError.elementNameMissingForMoveFinger(call)
            }
            guard let direction = raw.direction else {
                throw CommandDecodingError.directionMissing(call)
            }
            guard let directionEnum = TargetCommand.Direction(rawValue: direction) else {
                throw CommandDecodingError.invalidDirection(call, providedValue: direction)
            }
            guard let amount = raw.amount else {
                throw CommandDecodingError.amountMissing(call)
            }
            guard let postActionDelay = raw.postActionDelay else {
                throw CommandDecodingError.postActionDelayMissing(call)
            }
            self = .move_finger(elementName: element, direction: directionEnum, amount: amount, postActionDelay: postActionDelay)

        case "input":
            guard let text = raw.text else {
                throw CommandDecodingError.textMissing(call)
            }
            self = .input(text: text)

        case "clear_input_field":
            self = .clearInputField

        case "shake":
            self = .shake

        case "screenshot":
            self = .screenshot

        case "wait":
            guard let duration = raw.duration else {
                throw CommandDecodingError.durationMissing(call)
            }
            self = .wait(duration: duration)

        case "open_url":
            guard let url = raw.url else {
                throw CommandDecodingError.urlMissing(call)
            }
            guard let postActionDelay = raw.postActionDelay else {
                throw CommandDecodingError.postActionDelayMissingForOpenUrl(call)
            }
            self = .open_url(urlString: url, postActionDelay: postActionDelay)

        case "press_button":
            guard let button = raw.button else {
                throw CommandDecodingError.buttonMissing(call)
            }
            let count = raw.count ?? 1
            self = .press(button: button, amount: count)

        case "run_script":
            guard let script = raw.script?.trimmingCharacters(in: .whitespacesAndNewlines), !script.isEmpty else {
                throw CommandDecodingError.scriptMissing(call)
            }
            self = .runScript(script: script)

        default:
            throw CommandDecodingError.unknownFunction(call)
        }
    }
}
