//
//  OpenRouterPointOutService.swift
//  Qalti
//
//  Created by OpenAI on 16.01.2026.
//

@preconcurrency import OpenAI
import Foundation
import Logging

/// Client-side Point Out implementation via OpenRouter.
final class OpenRouterPointOutService: Loggable {
    private enum Constants {
        static let model: String = "anthropic/claude-sonnet-4"
        static let maxCompletionTokens: Int = 60
        static let temperature: Double = 0.0
        static let maxParseAttempts: Int = 3
        static let timeoutSeconds: TimeInterval = 90

        // Keep this prompt byte-for-byte aligned with backend ANTHROPIC_SYSTEM_PROMPT.
        static let systemPrompt =
        "You are an AI that returns precise coordinates. Respond ONLY with valid JSON in this exact format: {\"x\": int, \"y\": int}. No prose. Return {\"x\": null, \"y\": null} if there is no such object."
    }

    private final class ErrorDecodingMiddleware: OpenAIMiddleware, @unchecked Sendable {
        private let stateQueue = DispatchQueue(label: "io.qalti.openrouter.pointout.error.state")
        private var _insufficientBalance: Bool = false
        private var _authenticationFailed: Bool = false
        private var _timeout: Bool = false

        var insufficientBalance: Bool { stateQueue.sync { _insufficientBalance } }
        var authenticationFailed: Bool { stateQueue.sync { _authenticationFailed } }
        var timeout: Bool { stateQueue.sync { _timeout } }

        func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) {
            guard let response = response as? HTTPURLResponse else { return (response, data) }
            switch response.statusCode {
            case 504:
                stateQueue.sync { _timeout = true }
                return (response, nil)
            case 402:
                stateQueue.sync { _insufficientBalance = true }
                return (response, nil)
            case 401:
                stateQueue.sync { _authenticationFailed = true }
                return (response, nil)
            default:
                return (response, data)
            }
        }
    }

    private let credentialsService: CredentialsService

    init(credentialsService: CredentialsService) {
        self.credentialsService = credentialsService
    }

    func pointOut(
        imageURL: URL,
        imageWidth: Int,
        imageHeight: Int,
        objectDescription: String,
        relative: Bool,
        completion: @escaping (Result<UIElementLocator.PointOutResponse, UIElementLocator.Error>) -> Void
    ) {
        guard let openRouterKey = credentialsService.openRouterKey, !openRouterKey.isEmpty else {
            credentialsService.triggerCredentialsRequired()
            completion(.failure(.credentialsRequired))
            return
        }

        let sanitizedDescription = Self.sanitizeObjectDescription(objectDescription)
        let userPrompt = "Point out \(sanitizedDescription)"

        let contentParts: [ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.ContentPart] = [
            .text(.init(text: userPrompt)),
            .image(.init(imageUrl: .init(url: imageURL.absoluteString, detail: .auto)))
        ]

        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .system(.init(content: .textContent(Constants.systemPrompt))),
            .user(.init(content: .contentParts(contentParts)))
        ]

        let query = ChatQuery(
            messages: messages,
            model: Constants.model,
            maxCompletionTokens: Constants.maxCompletionTokens,
            temperature: Constants.temperature
        )

        let configuration = OpenAI.Configuration(
            token: openRouterKey,
            host: "openrouter.ai",
            port: 443,
            scheme: "https",
            basePath: "/api/v1",
            timeoutInterval: Constants.timeoutSeconds
        )

        let errorMiddleware = ErrorDecodingMiddleware()
        let openAI = OpenAI(configuration: configuration, middlewares: [errorMiddleware])

        func handleResult(_ result: Result<ChatResult, Swift.Error>, attempt: Int) {
            switch result {
            case .success(let response):
                guard let content = response.choices.first?.message.content else {
                    return completion(.failure(.invalidResponseFormat))
                }

                switch Self.parsePoint(from: content) {
                case .found(let coordinates):
                    let adjusted = Self.applyRelativeIfNeeded(
                        coordinates: coordinates,
                        width: imageWidth,
                        height: imageHeight,
                        relative: relative
                    )
                    let payload = UIElementLocator.PointOutResponse(
                        isFound: true,
                        coordinates: .init(x: adjusted.x, y: adjusted.y),
                        objectDescription: objectDescription,
                        relative: relative
                    )
                    completion(.success(payload))

                case .notFound:
                    let payload = UIElementLocator.PointOutResponse(
                        isFound: false,
                        coordinates: nil,
                        objectDescription: objectDescription,
                        relative: relative
                    )
                    completion(.success(payload))

                case .invalidJSON:
                    if attempt < Constants.maxParseAttempts {
                        openAI.chats(query: query) { retryResult in
                            handleResult(retryResult, attempt: attempt + 1)
                        }
                    } else {
                        completion(.failure(.invalidResponseFormat))
                    }
                }

            case .failure(let error):
                if errorMiddleware.authenticationFailed {
                    credentialsService.triggerCredentialsRequired()
                    return completion(.failure(.credentialsRequired))
                }
                if errorMiddleware.insufficientBalance {
                    credentialsService.triggerInsufficientBalance()
                    return completion(.failure(.insufficientBalance))
                }
                if errorMiddleware.timeout {
                    return completion(.failure(.connectionError(URLError(.timedOut))))
                }
                completion(.failure(.connectionError(error)))
            }
        }

        openAI.chats(query: query) { result in
            handleResult(result, attempt: 1)
        }
    }

    private static func sanitizeObjectDescription(_ description: String) -> String {
        var cleaned = description
        for character in ["'", "\"", "&"] {
            cleaned = cleaned.replacingOccurrences(of: character, with: " ")
        }
        return cleaned
    }

    private enum ParseOutcome {
        case found((x: Int, y: Int))
        case notFound
        case invalidJSON
    }

    private static func parsePoint(from content: String) -> ParseOutcome {
        guard let data = content.data(using: .utf8) else { return .invalidJSON }
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else { return .invalidJSON }
        guard let json = jsonObject as? [String: Any] else { return .notFound }

        func intValue(_ value: Any?) -> Int? {
            switch value {
            case let number as NSNumber:
                return number.intValue
            case let string as String:
                return Int(string)
            default:
                return nil
            }
        }

        guard let x = intValue(json["x"]), let y = intValue(json["y"]) else { return .notFound }
        return .found((x, y))
    }

    private static func applyRelativeIfNeeded(
        coordinates: (x: Int, y: Int),
        width: Int,
        height: Int,
        relative: Bool
    ) -> (x: Double, y: Double) {
        if !relative {
            return (Double(coordinates.x), Double(coordinates.y))
        }
        return (Double(coordinates.x) / Double(width), Double(coordinates.y) / Double(height))
    }
}
