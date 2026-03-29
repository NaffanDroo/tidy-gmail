import Foundation
@testable import TidyGmailCore

final class MockDMGCreator: DMGCreator, @unchecked Sendable {
    var createCallCount = 0
    var lastSourceDirectory: URL?
    var lastDestination: URL?
    var lastVolumeName: String?
    var lastPassphrase: String?
    var createResult: Result<Void, Error> = .success(())

    var mountCallCount = 0
    var mountResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/Volumes/Test"))

    var unmountCallCount = 0

    func createEncryptedDMG(
        sourceDirectory: URL,
        destination: URL,
        volumeName: String,
        passphrase: String
    ) async throws {
        createCallCount += 1
        lastSourceDirectory = sourceDirectory
        lastDestination = destination
        lastVolumeName = volumeName
        lastPassphrase = passphrase
        try createResult.get()
    }

    func mountReadOnly(dmgPath: URL, passphrase: String) async throws -> URL {
        mountCallCount += 1
        return try mountResult.get()
    }

    func unmount(volumePath: URL) async throws {
        unmountCallCount += 1
    }
}
