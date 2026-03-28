import Foundation
@testable import TidyGmailCore

/// In-memory Keychain replacement for use in tests. Thread-safe via a simple dictionary.
final class MockKeychainService: KeychainService, @unchecked Sendable {
    private var storage: [String: String] = [:]
    var storeCallCount = 0
    var deleteCallCount = 0
    var shouldThrowOnStore = false
    var shouldThrowOnRetrieve = false

    func store(_ value: String, forKey key: String) throws {
        storeCallCount += 1
        if shouldThrowOnStore { throw KeychainError.storageFailed(status: -1) }
        storage[key] = value
    }

    func retrieve(forKey key: String) throws -> String? {
        if shouldThrowOnRetrieve { throw KeychainError.retrievalFailed(status: -1) }
        return storage[key]
    }

    func delete(forKey key: String) throws {
        deleteCallCount += 1
        storage.removeValue(forKey: key)
    }

    func reset() {
        storage = [:]
        storeCallCount = 0
        deleteCallCount = 0
        shouldThrowOnStore = false
        shouldThrowOnRetrieve = false
    }
}
