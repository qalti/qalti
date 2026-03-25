import Foundation
import Logging

// MARK: - Callback Token (now using shared CallbackToken from CallbackToken.swift)

public class CredentialsService: ObservableObject, Loggable {
    
    // MARK: - Errors
    
    enum CredentialsError: Error, LocalizedError {
        case missingCredentials

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Credentials required - OpenRouter API key missing"
            }
        }
    }

    // MARK: - Dependencies

    private let keychainManager = KeychainManager.shared
    private let errorCapturer: ErrorCapturing

    // MARK: - State

    @Published var hasCredentials: Bool = false
    // When present, use API key for backend access instead of user access token.
    private(set) var apiKey: String?
    @Published private(set) var openRouterKey: String?
    @Published private(set) var s3Settings: S3Settings?

    // MARK: - Token-based callback management

    private var tokenBasedCredentialsChangedCallbacks: [CallbackToken: () -> Void] = [:]
    private var tokenBasedCredentialsRequiredCallbacks: [CallbackToken: () -> Void] = [:]

    public init(errorCapturer: ErrorCapturing) {
        self.errorCapturer = errorCapturer

        // Load OpenRouter key and S3 settings from Keychain on init
        self.openRouterKey = keychainManager.loadOpenRouterKey()
        self.s3Settings = keychainManager.loadS3Settings()
        
        // Update credentials state based on OpenRouter key
        updateCredentialsState()
    }

    // MARK: - CLI Helper
    /// Inject an API key directly for headless CLI runs.
    /// Does not modify credentials state or persist in keychain.
    func setApiKeyForCLI(_ key: String) {
        self.apiKey = key
        self.hasCredentials = !key.isEmpty
    }

    /// Computed bearer value used by backend services. Returns API key if present, otherwise OpenRouter key.
    var bearer: String? {
        if let key = apiKey, !key.isEmpty { return key }
        if let key = openRouterKey, !key.isEmpty { return key }
        return nil
    }

    // MARK: - OpenRouter Key Management

    func setOpenRouterKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            removeOpenRouterKey()
            return
        }
        openRouterKey = trimmed
        _ = keychainManager.saveOpenRouterKey(trimmed)
        updateCredentialsState()
        notifyCredentialsChanged()
        logger.info("OpenRouter API key saved successfully")
    }

    func removeOpenRouterKey() {
        openRouterKey = nil
        _ = keychainManager.deleteOpenRouterKey()
        updateCredentialsState()
        notifyCredentialsChanged()
        logger.info("OpenRouter API key removed")
    }

    // MARK: - S3 Settings Management

    func setS3Settings(_ settings: S3Settings) {
        s3Settings = settings
        _ = keychainManager.saveS3Settings(settings)
        logger.info("S3 settings saved successfully")
    }

    func removeS3Settings() {
        s3Settings = nil
        _ = keychainManager.deleteS3Settings()
        logger.info("S3 settings removed")
    }

    // MARK: - Private Methods

    private func updateCredentialsState() {
        // Credentials are available if an OpenRouter key exists.
        self.hasCredentials = (openRouterKey != nil && !openRouterKey!.isEmpty)
    }

    private func notifyCredentialsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for callback in self.tokenBasedCredentialsChangedCallbacks.values {
                callback()
            }
        }
    }

    private func notifyCredentialsRequired() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for callback in self.tokenBasedCredentialsRequiredCallbacks.values {
                callback()
            }
        }
    }

    // MARK: - Token-based Callback Management

    func addCredentialsChangedCallback(_ callback: @escaping () -> Void) -> CallbackToken {
        let token = CallbackToken()
        tokenBasedCredentialsChangedCallbacks[token] = callback
        return token
    }

    func addCredentialsRequiredCallback(_ callback: @escaping () -> Void) -> CallbackToken {
        let token = CallbackToken()
        tokenBasedCredentialsRequiredCallbacks[token] = callback
        return token
    }

    func removeCallback(_ token: CallbackToken) {
        tokenBasedCredentialsChangedCallbacks.removeValue(forKey: token)
        tokenBasedCredentialsRequiredCallbacks.removeValue(forKey: token)
    }

    // MARK: - Token Provider Implementation

    func getFreshToken() async throws -> String {
        // Prefer CLI API key, then OpenRouter key
        if let key = apiKey, !key.isEmpty { return key }
        guard let key = openRouterKey, !key.isEmpty else {
            throw CredentialsError.missingCredentials
        }
        return key
    }

    // MARK: - Error Notifications

    func triggerCredentialsRequired() {
        logger.warning("Credentials required")
        notifyCredentialsRequired()
    }

    func triggerInsufficientBalance() {
        logger.warning("Insufficient balance - showing API key entry")
        // Show same API key entry as credentials required
        notifyCredentialsRequired()
    }
}
