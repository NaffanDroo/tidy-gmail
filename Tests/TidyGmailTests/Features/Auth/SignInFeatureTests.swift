import Foundation
import XCTest
@testable import TidyGmailCore

// Feature: Sign in with Google
//
// Scenarios covered:
//   - Successful sign-in marks state as signed-in
//   - Sign-in failure surfaces an error and leaves the user signed-out
//   - Sign-out clears signed-in state and delegates to the OAuth manager
//   - Restoring a persisted session marks state as signed-in without a network round-trip
//   - No persisted session leaves the user on the sign-in screen

@MainActor
final class SignInFeatureTests: XCTestCase {
    private var mockOAuth: MockOAuthManager!
    private var authState: AuthState!
    private var coordinator: AuthCoordinator!

    override func setUp() {
        super.setUp()
        mockOAuth = MockOAuthManager()
        authState = AuthState()
        coordinator = AuthCoordinator(
            oauthManager: mockOAuth,
            configuration: OAuthConfiguration(clientID: "test-client-id")
        )
    }

    // MARK: - Scenario: successful sign-in

    func test_givenSuccessfulOAuth_whenSignIn_thenIsSignedIn() async {
        mockOAuth.signInResult = .success(())
        await coordinator.signIn(state: authState)
        XCTAssertTrue(authState.isSignedIn)
        XCTAssertNil(authState.error)
        XCTAssertEqual(mockOAuth.signInCallCount, 1)
    }

    func test_givenSuccessfulOAuth_whenSignIn_thenLoadingStateIsCorrect() async {
        mockOAuth.signInResult = .success(())
        await coordinator.signIn(state: authState)
        XCTAssertFalse(authState.isLoading)
    }

    // MARK: - Scenario: sign-in failure

    func test_givenOAuthFailure_whenSignIn_thenIsNotSignedInAndErrorIsSet() async {
        mockOAuth.signInResult = .failure(OAuthError.missingTokens)
        await coordinator.signIn(state: authState)
        XCTAssertFalse(authState.isSignedIn)
        XCTAssertNotNil(authState.error)
    }

    // MARK: - Scenario: missing client ID

    func test_givenEmptyClientID_whenSignIn_thenClientIDNotConfiguredErrorIsSet() async {
        coordinator = AuthCoordinator(
            oauthManager: mockOAuth,
            configuration: OAuthConfiguration(clientID: "")
        )
        await coordinator.signIn(state: authState)
        XCTAssertEqual(mockOAuth.signInCallCount, 0)
        XCTAssertFalse(authState.isSignedIn)
        if case .clientIDNotConfigured = authState.error { } else {
            XCTFail("Expected .clientIDNotConfigured, got \(String(describing: authState.error))")
        }
    }

    // MARK: - Scenario: sign-out

    func test_givenSignedInUser_whenSignOut_thenIsNotSignedIn() {
        authState.isSignedIn = true
        coordinator.signOut(state: authState)
        XCTAssertFalse(authState.isSignedIn)
        XCTAssertEqual(mockOAuth.signOutCallCount, 1)
    }

    func test_givenSignedInUser_whenSignOut_thenUserEmailIsCleared() {
        authState.isSignedIn = true
        authState.userEmail = "user@example.com"
        coordinator.signOut(state: authState)
        XCTAssertNil(authState.userEmail)
    }

    // MARK: - Scenario: restoring an existing session

    func test_givenPersistedSession_whenRestoreSession_thenIsSignedIn() {
        mockOAuth.restoreSessionResult = true
        coordinator.restoreSession(state: authState)
        XCTAssertTrue(authState.isSignedIn)
    }

    func test_givenNoPersistedSession_whenRestoreSession_thenIsNotSignedIn() {
        mockOAuth.restoreSessionResult = false
        coordinator.restoreSession(state: authState)
        XCTAssertFalse(authState.isSignedIn)
    }
}
