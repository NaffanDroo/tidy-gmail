import Foundation
import Security

// MARK: - Keychain manager

public enum KeychainManager {
    private static let service = "com.tidygmail.export"

    /// Save an export passphrase to the macOS Keychain.
    public static func savePassphrase(_ passphrase: String, forExport exportName: String) throws {
        let passphraseData = Data(passphrase.utf8)

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: exportName
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: exportName,
            kSecValueData as String: passphraseData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    /// Retrieve an export passphrase from the macOS Keychain.
    public static func retrievePassphrase(forExport exportName: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: exportName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.retrieveFailed(status: status)
        }
    }

    /// Delete an export passphrase from the macOS Keychain.
    public static func deletePassphrase(forExport exportName: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: exportName
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }
}

// MARK: - Errors

public enum KeychainError: Error, Equatable {
    case saveFailed(status: OSStatus)
    case retrieveFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)

    public var userMessage: String {
        switch self {
        case .saveFailed(let status):
            return "Failed to save passphrase to Keychain (error \(status))."
        case .retrieveFailed(let status):
            return "Failed to retrieve passphrase from Keychain (error \(status))."
        case .deleteFailed(let status):
            return "Failed to delete passphrase from Keychain (error \(status))."
        }
    }
}
