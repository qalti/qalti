import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    private let service = "com.aiqa.qalti.auth"

    // MARK: - Generic Keychain Operations
    
    private func save(_ data: Data, for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func load(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        return status == errSecSuccess ? result as? Data : nil
    }
    
    private func delete(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - OpenRouter Key Management

    func saveOpenRouterKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        return save(data, for: "openRouterKey")
    }

    func loadOpenRouterKey() -> String? {
        guard let data = load(for: "openRouterKey") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteOpenRouterKey() -> Bool {
        return delete(for: "openRouterKey")
    }

    // MARK: - S3 Settings Management

    func saveS3Settings(_ settings: S3Settings) -> Bool {
        guard let data = try? JSONEncoder().encode(settings) else { return false }
        return save(data, for: "s3Settings")
    }

    func loadS3Settings() -> S3Settings? {
        guard let data = load(for: "s3Settings") else { return nil }
        return try? JSONDecoder().decode(S3Settings.self, from: data)
    }

    func deleteS3Settings() -> Bool {
        return delete(for: "s3Settings")
    }
}
