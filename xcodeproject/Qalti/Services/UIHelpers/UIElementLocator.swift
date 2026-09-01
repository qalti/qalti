//
//  RemoteCommandExplainer.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 04.03.2025.
//

import Foundation
import Logging

/// A class that explains remote commands by converting pixel coordinates to semantic UI element descriptions.
class UIElementLocator: Loggable {
    // MARK: - Types
    
    /// Input types for point out operations
    enum PointOutInput {
        case image(PlatformImage)
        case url(URL, width: Int, height: Int)
    }
    
    /// Error types that can occur during remote command explanation
    enum Error: Swift.Error, LocalizedError {
        case invalidArguments(command: String)
        case screenshotConversionFailed
        case noDataReceived
        case connectionError(Swift.Error)
        case invalidResponseFormat
        case invalidBaseURL
        case elementNotFound(String)
        case credentialsRequired
        case insufficientBalance
        case s3ConfigurationMissing
        
        var errorDescription: String? {
            switch self {
            case .invalidArguments(let command):
                return "Invalid command arguments: \(command)"
            case .screenshotConversionFailed:
                return "Failed to process screenshot"
            case .noDataReceived:
                return "No response received from server"
            case .connectionError(let error):
                return "Connection error: \(error.localizedDescription)"
            case .invalidResponseFormat:
                return "Invalid response format from server"
            case .invalidBaseURL:
                return "Invalid server configuration"
            case .elementNotFound(let description):
                return "Element not found: \(description)"
            case .credentialsRequired:
                return "OpenRouter API key is missing. Please add it in Settings."
            case .insufficientBalance:
                return "Insufficient account balance. Please add funds to continue."
            case .s3ConfigurationMissing:
                return "S3 configuration is missing. Add AWS credentials in Settings."
            }
        }
    }

    struct PointOutResponse: Codable {
        let isFound: Bool
        let coordinates: Coordinates?
        let objectDescription: String
        let relative: Bool
        
        struct Coordinates: Codable {
            let x: Double
            let y: Double
        }
        
        enum CodingKeys: String, CodingKey {
            case isFound = "is_found"
            case coordinates
            case objectDescription = "object_description"
            case relative
        }
    }
    
    struct AssertResponse: Codable {
        let success: Bool
        let message: String
        let contentIsLoading: Bool
        
        enum CodingKeys: String, CodingKey {
            case success
            case message
            case contentIsLoading = "content_is_loading"
        }
    }

    // MARK: - Properties

    private let credentialsService: any CredentialsServicing
    private let errorCapturer: ErrorCapturing
    private let pointOutService: OpenRouterPointOutService
    private let defaultRelative: Bool

    // MARK: - Initialization
    
    init(
        credentialsService: any CredentialsServicing,
        errorCapturer: ErrorCapturing,
        defaultRelative: Bool
    ) {
        self.credentialsService = credentialsService
        self.errorCapturer = errorCapturer
        self.pointOutService = OpenRouterPointOutService(credentialsService: credentialsService)
        self.defaultRelative = defaultRelative
    }
    
    // MARK: - Public Methods
    
    /// Point out object using either screenshot image or S3 image URL
    func pointOutObject(
        input: PointOutInput,
        objectDescription: String,
        relative: Bool? = nil,
        completion: @escaping (Result<PointOutResponse, Swift.Error>) -> Void
    ) {
        let errorCapturer = errorCapturer
        let resolvedRelative = relative ?? defaultRelative
        
        switch input {
        case .image:
            completion(.failure(Error.screenshotConversionFailed))

        case .url(let imageURL, let width, let height):
            pointOutService.pointOut(
                imageURL: imageURL,
                imageWidth: width,
                imageHeight: height,
                objectDescription: objectDescription,
                relative: resolvedRelative
            ) { [weak self] result in
                switch result {
                case .success(let response):
                    if !response.isFound {
                        self?.logger.debug("Element not found by OpenRouter: '\(objectDescription)'")
                        completion(.failure(Error.elementNotFound(objectDescription)))
                    } else {
                        completion(.success(response))
                    }
                case .failure(let error):
                    if case Error.invalidResponseFormat = error {
                        errorCapturer.capture(error: error)
                    }
                    self?.logger.debug("OpenRouter point out error: \(error)")
                    completion(.failure(error))
                }
            }
        }
    }
    
    @available(*, deprecated, message: "This method is deprecated and is not supported by the backend.")
    func assertContent(
        screenshot: PlatformImage,
        assertion: String,
        completion: @escaping (Result<AssertResponse, Swift.Error>) -> Void
    ) {
        // Deprecated method - return failure to avoid refactoring existing code
        let deprecatedResponse = AssertResponse(
            success: false,
            message: "Assert method is deprecated and no longer supported",
            contentIsLoading: false
        )
        completion(.success(deprecatedResponse))
    }
    
    @available(*, deprecated, message: "This method is deprecated and is not supported by the backend. To be removed.")
    func assertManyContent(
        screenshots: [PlatformImage],
        assertion: String,
        completion: @escaping (Result<AssertResponse, Swift.Error>) -> Void
    ) {
        // Deprecated method - return failure to avoid refactoring existing code
        let deprecatedResponse = AssertResponse(
            success: false,
            message: "Assert many method is deprecated and no longer supported",
            contentIsLoading: false
        )
        completion(.success(deprecatedResponse))
    }
}
