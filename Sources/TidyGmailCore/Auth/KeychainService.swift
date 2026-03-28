import Foundation
import Security

// MARK: - Protocol

public protocol KeychainService: Sendable {
    func store(_ value: String, forKey key: String) throws
    func retrieve(forKey key: String) throws -> String?
    func delete(forKey key: String) throws
}

// MARK: - Errors

public enum KeychainError: Error, Equatable {
    case storageFailed(status: OSStatus)
    case retrievalFailed(status: OSStatus)
    case deletionFailed(status: OSStatus)
    case invalidData
}

// MARK: - Live implementation

public final class LiveKeychainService: KeychainService {
    private let serviceName: String

    public init(serviceName: String = "com.tidygmail.oauth") {
        self.serviceName = serviceName
    }

    public func store(_ value: String, forKey key: String) throws {
        let data = Data(value.utf8)
        // Always delete first to avoid duplicate item errors.
        try? delete(forKey: key)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storageFailed(status: status)
        }
    }

    public func retrieve(forKey key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.retrievalFailed(status: status)
        }
    }

    public func delete(forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deletionFailed(status: status)
        }
    }
}
