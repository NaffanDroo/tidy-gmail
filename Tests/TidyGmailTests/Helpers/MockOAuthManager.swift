import Foundation
@testable import TidyGmailCore

final class MockOAuthManager: OAuthManager, @unchecked Sendable {
    var signInResult: Result<Void, Error> = .success(())
    var signInCallCount = 0
    var signOutCallCount = 0
    var restoreSessionResult = false
    var freshAccessTokenResult: Result<String, Error> = .success("test-access-token")

    func signIn(configuration: OAuthConfiguration) async throws {
        signInCallCount += 1
        try signInResult.get()
    }

    func signOut() throws {
        signOutCallCount += 1
    }

    func restoreSession() throws -> Bool {
        restoreSessionResult
    }

    func freshAccessToken() async throws -> String {
        try freshAccessTokenResult.get()
    }
}
