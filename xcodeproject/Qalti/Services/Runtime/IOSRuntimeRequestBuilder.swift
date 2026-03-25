//
//  IOSRuntimeRequestBuilder.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 05.11.25.
//

import Foundation
import Logging

// MARK: - Runner Command Model
enum RunnerCommand {
    case tap(x: Int, y: Int, isLong: Bool)
    case zoom(x: Int, y: Int, scale: Double, velocity: Double)
    case creep(x: Int, y: Int, direction: String, amount: Int)
    case input(text: String)
    case openURL(urlString: String)
    case openApp(bundleID: String, launchArguments: [String]?, launchEnvironment: [String: String]?)
    case shake
    case clearInputField
    case getHierarchy
    case hasKeyboard
    case getScreenInfo
}


// MARK: - Request Builder
struct IOSRuntimeRequestBuilder: Loggable {
    private let serverAddress: String
    private let controlServerPort: Int

    init(serverAddress: String, controlServerPort: Int) {
        self.serverAddress = serverAddress
        self.controlServerPort = controlServerPort
    }

    func buildRequest(for command: RunnerCommand, waitForCompletion: Bool = false) -> URLRequest? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = serverAddress
        components.port = controlServerPort
        // URLComponents expects absolute paths so we keep the leading slash here.
        components.path = path(for: command)

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = httpMethod(for: command)
        // Wait flag applies to all commands (even GET) so we pass it via a dedicated header.
        request.setValue(waitForCompletion ? "true" : "false", forHTTPHeaderField: "X-Qalti-Wait")

        if let bodyData = body(for: command) {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func path(for command: RunnerCommand) -> String {
        // Endpoints intentionally use dash-separated names because underscores break some HTTP tooling.
        switch command {
        case .tap:                  return "/tap"
        case .zoom:                 return "/zoom"
        case .creep:                return "/creep"
        case .input:                return "/input"
        case .openURL:              return "/open-url"
        case .openApp:              return "/open-app"
        case .shake:                return "/shake"
        case .clearInputField:      return "/clear-input-field"
        case .getHierarchy:         return "/hierarchy"
        case .hasKeyboard:          return "/has-keyboard"
        case .getScreenInfo:        return "/screen-info"
        }
    }

    private func httpMethod(for command: RunnerCommand) -> String {
        switch command {
        case .getHierarchy, .hasKeyboard, .getScreenInfo:
            return "GET"
        default:
            return "POST"
        }
    }

    private func body(for command: RunnerCommand) -> Data? {
        func jsonData(_ payload: [String: Any]) -> Data? {
            guard JSONSerialization.isValidJSONObject(payload) else {
                logger.warning("Attempted to encode invalid JSON payload: \(payload)")
                return nil
            }
            do {
                return try JSONSerialization.data(withJSONObject: payload, options: [])
            } catch {
                logger.error("Failed to serialize JSON payload: \(error.localizedDescription)")
                return nil
            }
        }
        
        switch command {
        case .tap(let x, let y, let isLong):
            return jsonData([
                "x": x,
                "y": y,
                "is_long": isLong
            ])
        case .zoom(let x, let y, let scale, let velocity):
            return jsonData([
                "x": x,
                "y": y,
                "scale": scale,
                "velocity": velocity
            ])
        case .creep(let x, let y, let direction, let amount):
            return jsonData([
                "x": x,
                "y": y,
                "direction": direction,
                "amount": amount
            ])
        case .input(let text):
            return jsonData([
                "text": text
            ])
        case .openURL(let urlString):
            return jsonData([
                "url": urlString
            ])
        case .openApp(let bundleID, let launchArguments, let launchEnvironment):
            var payload: [String: Any] = [
                "bundle_id": bundleID
            ]
            if let launchArguments {
                payload["launch_arguments"] = launchArguments
            }
            if let launchEnvironment {
                payload["launch_environment"] = launchEnvironment
            }
            return jsonData(payload)
        case .shake, .clearInputField, .getHierarchy, .hasKeyboard, .getScreenInfo:
            return nil
        }
    }
}
