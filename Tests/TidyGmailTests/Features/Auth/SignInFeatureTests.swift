import Foundation
import XCTest
@testable import TidyGmailCore

// Feature: Sign in with Google
//
// Scenarios covered:
//   - Successful sign-in stores tokens in Keychain and marks state as signed-in
//   - Sign-in failure surfaces an error and leaves the user signed-out
//   - Sign-out removes all tokens from Keychain
//   - Restoring an existing Keychain session marks state as signed-in without a network round-trip
//   - No existing session leaves the user on the sign-in screen

@MainActor
final class SignInFeatureTests: XCTestCase {
    private var mockOAuth: MockOAuthManager!
    private var mockKeychain: MockKeychainService!
    private var authState: AuthState!
    private var coordinator: AuthCoordinator!

    override func setUp() {
        super.setUp()
        mockOAuth = MockOAuthManager()
        mockKeychain = MockKeychainService()
        authState = AuthState()
        coordinator = AuthCoordinator(
            oauthManager: mockOAuth,
            keychain: mockKeychain,
            configuration: OAuthConfiguration(
                clientID: "test-client-id",
                redirectURI: URL(string: "http://127.0.0.1")!
            )
        )
    }

    // MARK: - Scenario: successful sign-in

    func test_givenSuccessfulOAuth_whenSignIn_thenIsSignedInAndTokensStoredInKeychain() async {
        // Given
        mockOAuth.signInResult = .success(OAuthTokens(accessToken: "acc-123", refreshToken: "ref-456"))

        // When
        await coordinator.signIn(state: authState)

        // Then
        XCTAssertTrue(authState.isSignedIn)
        XCTAssertNil(authState.error)
        XCTAssertEqual(try mockKeychain.retrieve(forKey: OAuthConfiguration.KeychainKey.accessToken), "acc-123")
        XCTAssertEqual(try mockKeychain.retrieve(forKey: OAuthConfiguration.KeychainKey.refreshToken), "ref-456")
    }

    func test_givenSuccessfulOAuth_whenSignIn_thenLoadingStateIsCorrect() async {
        mockOAuth.signInResult = .success(OAuthTokens(accessToken: "a", refreshToken: "r"))
        await coordinator.signIn(state: authState)
        // isLoading must be false after completion (the defer in coordinator ensures this)
        XCTAssertFalse(authState.isLoading)
    }

    // MARK: - Scenario: sign-in failure

    func test_givenOAuthFailure_whenSignIn_thenIsNotSignedInAndErrorIsSet() async {
        // Given
        mockOAuth.signInResult = .failure(OAuthError.missingTokens)

        // When
        await coordinator.signIn(state: authState)

        // Then
        XCTAssertFalse(authState.isSignedIn)
        XCTAssertNotNil(authState.error)
        XCTAssertNil(try mockKeychain.retrieve(forKey: OAuthConfiguration.KeychainKey.accessToken))
    }

    // MARK: - Scenario: sign-out

    func test_givenSignedInUser_whenSignOut_thenAllTokensRemovedFromKeychain() throws {
        // Given — pre-seed tokens as if a previous sign-in succeeded.
        try mockKeychain.store("acc-token", forKey: OAuthConfiguration.KeychainKey.accessToken)
        try mockKeychain.store("ref-token", forKey: OAuthConfiguration.KeychainKey.refreshToken)
        authState.isSignedIn = true

        // When
        coordinator.signOut(state: authState)

        // Then
        XCTAssertFalse(authState.isSignedIn)
        XCTAssertNil(try mockKeychain.retrieve(forKey: OAuthConfiguration.KeychainKey.accessToken))
        XCTAssertNil(try mockKeychain.retrieve(forKey: OAuthConfiguration.KeychainKey.refreshToken))
    }

    func test_givenSignedInUser_whenSignOut_thenUserEmailIsCleared() throws {
        authState.isSignedIn = true
        authState.userEmail = "user@example.com"
        coordinator.signOut(state: authState)
        XCTAssertNil(authState.userEmail)
    }

    // MARK: - Scenario: restoring an existing session

    func test_givenAccessTokenInKeychain_whenRestoreSession_thenIsSignedIn() throws {
        // Given
        try mockKeychain.store("existing-token", forKey: OAuthConfiguration.KeychainKey.accessToken)

        // When
        coordinator.restoreSession(state: authState)

        // Then
        XCTAssertTrue(authState.isSignedIn)
    }

    func test_givenNoTokenInKeychain_whenRestoreSession_thenIsNotSignedIn() {
        // Given — keychain is empty.

        // When
        coordinator.restoreSession(state: authState)

        // Then
        XCTAssertFalse(authState.isSignedIn)
    }
}
