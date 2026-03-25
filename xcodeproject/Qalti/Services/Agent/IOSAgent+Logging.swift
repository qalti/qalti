//
//  IOSAgent+Logging.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 15.09.2025.
//

import Foundation
import Logging
@preconcurrency import OpenAI

extension IOSAgent {
    func createLogDirectoryIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: logDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)
                logger.debug("Created log directory: \(logDirectory.path)")
            } catch {
                errorCapturer.capture(error: error)
                logger.error("Failed to create log directory: \(error)")
                throw Error.unableToCreateLogDirectory
            }
        }
    }

    func saveMessagesToLog(_ messages: [ChatQuery.ChatCompletionMessageParam]) throws {
        guard AppConstants.shouldLogAgentActions, AppConstants.isDebug else { return }
        try createLogDirectoryIfNeeded()

        apiCallCounter += 1
        let fileName = "agent-messages-\(apiCallCounter).json"
        let fileURL = logDirectory.appendingPathComponent(fileName)

        var screenshotCounter = 1
        let serializedMessages = messages.enumerated().compactMap { (index, message) -> [String: Any]? in
            var messageDict: [String: Any] = [:]
            messageDict["sequence"] = index + 1

            switch message {
            case .system(let systemParam):
                messageDict["role"] = "system"
                messageDict["content"] = String(describing: systemParam.content)
                if let name = systemParam.name {
                    messageDict["name"] = String(describing: name)
                }

            case .developer(let developerParam):
                messageDict["role"] = "developer"
                messageDict["content"] = String(describing: developerParam.content)
                if let name = developerParam.name {
                    messageDict["name"] = String(describing: name)
                }

            case .user(let userParam):
                messageDict["role"] = "user"
                if let name = userParam.name {
                    messageDict["name"] = String(describing: name)
                }

                switch userParam.content {
                case .string(let text):
                    messageDict["content"] = String(describing: text)
                    messageDict["content_type"] = "text"
                case .contentParts(let contentParts):
                    var contentArray: [[String: Any]] = []
                    for part in contentParts {
                        switch part {
                        case .text(let textParam):
                            contentArray.append([
                                "type": "text",
                                "text": String(describing: textParam.text)
                            ])
                        case .image(let imageParam):
                            let imageUrl = String(describing: imageParam.imageUrl.url)
                            let truncatedUrl = imageUrl.count > 100 ? String(imageUrl.prefix(100)) + "..." : imageUrl

                            var imageDict: [String: Any] = [
                                "type": "image_url",
                                "image_url": [
                                    "url": truncatedUrl,
                                    "detail": imageParam.imageUrl.detail?.rawValue ?? ""
                                ]
                            ]

                            let urlString = imageParam.imageUrl.url
                            let base64String = urlString.hasPrefix("data:image/")
                                ? urlString.components(separatedBy: ",").last ?? urlString
                                : urlString

                            saveDebugScreenshotWithMarkers(
                                base64String: base64String,
                                apiCallCounter: apiCallCounter,
                                screenshotCounter: &screenshotCounter,
                                messages: messages,
                                currentIndex: index,
                                imageDict: &imageDict
                            )

                            contentArray.append(imageDict)
                        case .audio, .file:
                            contentArray.append([
                                "type": "unknown",
                                "content": "Unknown content part type"
                            ])
                        @unknown default:
                            contentArray.append([
                                "type": "unknown",
                                "content": "Unknown content part type"
                            ])
                        }
                    }
                    messageDict["content"] = contentArray
                    messageDict["content_type"] = "vision"
                @unknown default:
                    messageDict["content"] = "Unknown content type"
                    messageDict["content_type"] = "unknown"
                }

            case .assistant(let assistantParam):
                messageDict["role"] = "assistant"
                if let content = assistantParam.content {
                    messageDict["content"] = String(describing: content)
                }
                if let name = assistantParam.name {
                    messageDict["name"] = String(describing: name)
                }
                if let toolCalls = assistantParam.toolCalls {
                    messageDict["tool_calls"] = toolCalls.map { toolCall in
                        [
                            "id": String(describing: toolCall.id),
                            "type": String(describing: toolCall.type),
                            "function": [
                                "name": String(describing: toolCall.function.name),
                                "arguments": String(describing: toolCall.function.arguments)
                            ]
                        ]
                    }
                    messageDict["has_tool_calls"] = true
                    messageDict["tool_calls_count"] = toolCalls.count
                } else {
                    messageDict["has_tool_calls"] = false
                    messageDict["tool_calls_count"] = 0
                }

            case .tool(let toolParam):
                messageDict["role"] = "tool"
                messageDict["content"] = String(describing: toolParam.content)
                messageDict["tool_call_id"] = String(describing: toolParam.toolCallId)
            }

            return messageDict
        }

        let systemMessagesCount = serializedMessages.filter { ($0["role"] as? String) == "system" }.count
        let userMessagesCount = serializedMessages.filter { ($0["role"] as? String) == "user" }.count
        let assistantMessagesCount = serializedMessages.filter { ($0["role"] as? String) == "assistant" }.count
        let toolMessagesCount = serializedMessages.filter { ($0["role"] as? String) == "tool" }.count
        let developerMessagesCount = serializedMessages.filter { ($0["role"] as? String) == "developer" }.count

        saveDebugConversationHistory(
            messages: messages,
            fileURL: fileURL,
            serializedMessages: serializedMessages,
            systemMessagesCount: systemMessagesCount,
            userMessagesCount: userMessagesCount,
            assistantMessagesCount: assistantMessagesCount,
            toolMessagesCount: toolMessagesCount,
            developerMessagesCount: developerMessagesCount
        )
    }

    func saveDebugConversationHistory(
        messages: [ChatQuery.ChatCompletionMessageParam],
        fileURL: URL,
        serializedMessages: [[String: Any]],
        systemMessagesCount: Int,
        userMessagesCount: Int,
        assistantMessagesCount: Int,
        toolMessagesCount: Int,
        developerMessagesCount: Int
    ) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "api_call_number": apiCallCounter,
                "total_messages_in_conversation": messages.count,
                "messages": serializedMessages,
                "conversation_summary": [
                    "system_messages": systemMessagesCount,
                    "user_messages": userMessagesCount,
                    "assistant_messages": assistantMessagesCount,
                    "tool_messages": toolMessagesCount,
                    "developer_messages": developerMessagesCount
                ]
            ], options: [.prettyPrinted, .sortedKeys])

            try jsonData.write(to: fileURL)
            logger.debug("Saved complete conversation history (\(messages.count) messages) to: \(fileURL.path)")
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Failed to save messages to log: \(error)")
        }
    }
    
    func parseCoordinatesFromToolResponse(_ content: String) -> (x: Int, y: Int)? {
        guard let response = _parseToolResponse(from: content),
              let coords = response.coordinates else {
            return nil
        }
        return (x: coords.x, y: coords.y)
    }
    
    func parseZoomParametersFromToolResponse(_ content: String) -> (x: Int, y: Int, scale: Double)? {
        guard let response = _parseToolResponse(from: content),
              let coords = response.coordinates,
              let scale = response.scale else {
            return nil
        }
        return (x: coords.x, y: coords.y, scale: scale)
    }

    func saveDebugScreenshotWithMarkers(
        base64String: String,
        apiCallCounter: Int,
        screenshotCounter: inout Int,
        messages: [ChatQuery.ChatCompletionMessageParam],
        currentIndex: Int,
        imageDict: inout [String: Any]
    ) {
        guard let imageData = Data(base64Encoded: base64String) else { return }

        let screenshotFileName = "agent-messages-\(apiCallCounter)-screenshot-\(screenshotCounter).jpeg"
        let screenshotURL = logDirectory.appendingPathComponent(screenshotFileName)

        var coordinatesToApply: [(x: Int, y: Int)] = []
        var zoomParametersToApply: (x: Int, y: Int, scale: Double)?

        for nextIndex in (currentIndex + 1)..<messages.count {
            let nextMessage = messages[nextIndex]

            if case .user(let userParam) = nextMessage,
               case .contentParts(let contentParts) = userParam.content {
                let hasImage = contentParts.contains { part in
                    if case .image = part { return true }
                    return false
                }
                if hasImage {
                    break
                }
            }

            if case .tool(let toolParam) = nextMessage {
                let contentString = String(describing: toolParam.content)
                if let coordinates = parseCoordinatesFromToolResponse(contentString) {
                    coordinatesToApply.append(coordinates)
                }
                if let zoomParameters = parseZoomParametersFromToolResponse(contentString) {
                    zoomParametersToApply = zoomParameters
                }
            }
        }
        
        if let zoom = zoomParametersToApply, let image = PlatformImage(data: imageData) {
            let markedImage = image.withZoomMarker(coordinate: (zoom.x, zoom.y), scale: zoom.scale)
            if let markedImageData = markedImage.jpegData() {
                try? markedImageData.write(to: screenshotURL)
            } else {
                try? imageData.write(to: screenshotURL)
            }
        } else {
            try? imageData.write(to: screenshotURL)
        }

        if zoomParametersToApply == nil, !coordinatesToApply.isEmpty, let image = PlatformImage(data: imageData) {
            let markedImage = image.withCoordinateMarkers(coordinatesToApply)
            if let markedImageData = markedImage.jpegData() {
                try? markedImageData.write(to: screenshotURL)
            } else {
                try? imageData.write(to: screenshotURL)
            }
        } else {
            try? imageData.write(to: screenshotURL)
        }

        imageDict["screenshot_file"] = screenshotFileName
        screenshotCounter += 1
    }
    
    private func _parseToolResponse(from content: String) -> ParsedToolResponse? {
        var jsonString = content
        
        // Clean the raw string from the `textContent("...")` wrapper.
        if content.hasPrefix("textContent(\"") && content.hasSuffix("\")") {
            let startIndex = content.index(content.startIndex, offsetBy: 13)
            let endIndex = content.index(content.endIndex, offsetBy: -2)
            jsonString = String(content[startIndex..<endIndex])
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }
        
        return try? JSONDecoder().decode(ParsedToolResponse.self, from: data)
    }
}

private struct ParsedToolResponse: Decodable {
    struct Coordinates: Decodable {
        let x: Int
        let y: Int
    }
    let coordinates: Coordinates?
    let scale: Double?
}
