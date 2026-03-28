import Foundation
@testable import TidyGmailCore

final class MockOAuthManager: OAuthManager, @unchecked Sendable {
    var signInResult: Result<OAuthTokens, Error> = .success(
        OAuthTokens(accessToken: "test-access-token", refreshToken: "test-refresh-token")
    )
    var signInCallCount = 0
    var signOutCallCount = 0

    func signIn(configuration: OAuthConfiguration) async throws -> OAuthTokens {
        signInCallCount += 1
        return try signInResult.get()
    }

    func signOut(configuration: OAuthConfiguration, keychain: any KeychainService) throws {
        signOutCallCount += 1
        try keychain.delete(forKey: OAuthConfiguration.KeychainKey.accessToken)
        try keychain.delete(forKey: OAuthConfiguration.KeychainKey.refreshToken)
        try keychain.delete(forKey: OAuthConfiguration.KeychainKey.userEmail)
    }
}
