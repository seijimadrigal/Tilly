import Foundation
import Security
import TillyCore

public final class KeychainService: KeychainReadable, @unchecked Sendable {
    private let serviceName: String

    public init(serviceName: String = "com.tilly.apikeys") {
        self.serviceName = serviceName
    }

    public func setAPIKey(_ key: String, for provider: ProviderID) throws {
        let account = provider.rawValue
        guard let data = key.data(using: .utf8) else {
            throw TillyError.encodingError("Failed to encode API key")
        }

        // Try to update existing item first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            // Item doesn't exist, add it
            var addQuery = query
            addQuery[kSecValueData as String] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw TillyError.encodingError("Keychain write failed: \(status)")
        }
    }

    public func getAPIKey(for provider: ProviderID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                return nil
            }
            return key
        case errSecItemNotFound:
            return nil
        case errSecAuthFailed:
            // App was re-signed or keychain ACL doesn't match — delete stale entry so user can re-enter
            try? deleteAPIKey(for: provider)
            return nil
        default:
            throw TillyError.encodingError("Keychain read failed: \(status)")
        }
    }

    public func deleteAPIKey(for provider: ProviderID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: provider.rawValue,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TillyError.encodingError("Keychain delete failed: \(status)")
        }
    }

    public func hasAPIKey(for provider: ProviderID) -> Bool {
        (try? getAPIKey(for: provider)) != nil
    }
}
