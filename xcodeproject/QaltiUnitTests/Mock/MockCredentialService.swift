//
//  MockCredentialService.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 06.03.26.
//

import Foundation
import Combine
@testable import Qalti

final class MockCredentialsService: CredentialsServicing, ObservableObject {

    // MARK: - Published Properties

    @Published var hasCredentials: Bool = false
    @Published var openRouterKey: String?
    @Published var s3Settings: S3Settings?

    // MARK: - Other Properties

    private var apiKey: String?
    private var credentialsChangedCallbacks: [CallbackToken: () -> Void] = [:]
    private var credentialsRequiredCallbacks: [CallbackToken: () -> Void] = [:]

    var bearer: String? {
        if let key = apiKey, !key.isEmpty { return key }
        if let key = openRouterKey, !key.isEmpty { return key }
        return nil
    }

    // MARK: - Tracking Properties for Testing

    private(set) var setOpenRouterKeyCalled = false
    private(set) var removeOpenRouterKeyCalled = false
    private(set) var getFreshTokenCalled = false
    private(set) var triggerCredentialsRequiredCalled = false
    private(set) var triggerInsufficientBalanceCalled = false

    // MARK: - Initialization

    init() {
        // Start with default test values
        self.openRouterKey = "test-api-key"
        self.hasCredentials = true
    }

    // MARK: - API Key Management

    func setApiKeyForCLI(_ key: String) {
        self.apiKey = key.isEmpty ? nil : key
        updateCredentialsState()
    }

    func setOpenRouterKey(_ key: String) {
        setOpenRouterKeyCalled = true
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            openRouterKey = nil
        } else {
            openRouterKey = trimmed
        }
        updateCredentialsState()
        notifyCredentialsChanged()
    }

    func removeOpenRouterKey() {
        removeOpenRouterKeyCalled = true
        openRouterKey = nil
        updateCredentialsState()
        notifyCredentialsChanged()
    }

    // MARK: - S3 Settings Management

    func setS3Settings(_ settings: S3Settings) {
        s3Settings = settings
    }

    func removeS3Settings() {
        s3Settings = nil
    }

    // MARK: - Token Management

    func getFreshToken() async throws -> String {
        getFreshTokenCalled = true

        if let key = apiKey, !key.isEmpty { return key }
        guard let key = openRouterKey, !key.isEmpty else {
            throw CredentialsService.CredentialsError.missingCredentials
        }
        return key
    }

    // MARK: - Error Notifications

    func triggerCredentialsRequired() {
        triggerCredentialsRequiredCalled = true
        notifyCredentialsRequired()
    }

    func triggerInsufficientBalance() {
        triggerInsufficientBalanceCalled = true
        notifyCredentialsRequired()
    }

    // MARK: - Callback Management

    func addCredentialsChangedCallback(_ callback: @escaping () -> Void) -> CallbackToken {
        let token = CallbackToken()
        credentialsChangedCallbacks[token] = callback
        return token
    }

    func addCredentialsRequiredCallback(_ callback: @escaping () -> Void) -> CallbackToken {
        let token = CallbackToken()
        credentialsRequiredCallbacks[token] = callback
        return token
    }

    func removeCallback(_ token: CallbackToken) {
        credentialsChangedCallbacks.removeValue(forKey: token)
        credentialsRequiredCallbacks.removeValue(forKey: token)
    }

    // MARK: - Test Helper Methods

    func reset() {
        openRouterKey = "test-api-key"
        hasCredentials = true
        apiKey = nil
        s3Settings = nil

        // Reset call tracking
        setOpenRouterKeyCalled = false
        removeOpenRouterKeyCalled = false
        getFreshTokenCalled = false
        triggerCredentialsRequiredCalled = false
        triggerInsufficientBalanceCalled = false

        // Clear callbacks
        credentialsChangedCallbacks.removeAll()
        credentialsRequiredCallbacks.removeAll()
    }

    func setCredentialsAvailable(_ available: Bool) {
        if available {
            openRouterKey = "test-api-key"
            hasCredentials = true
        } else {
            openRouterKey = nil
            hasCredentials = false
        }
    }

    // MARK: - Private Helpers

    private func updateCredentialsState() {
        hasCredentials = (openRouterKey != nil && !openRouterKey!.isEmpty) ||
                        (apiKey != nil && !apiKey!.isEmpty)
    }

    private func notifyCredentialsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for callback in self.credentialsChangedCallbacks.values {
                callback()
            }
        }
    }

    private func notifyCredentialsRequired() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for callback in self.credentialsRequiredCallbacks.values {
                callback()
            }
        }
    }
}
