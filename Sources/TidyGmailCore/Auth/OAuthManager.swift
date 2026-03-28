import AppKit
@preconcurrency import AppAuth
import Observation

// MARK: - Token provider

/// Anything that can vend a fresh (auto-refreshed) access token.
public protocol TokenProvider: Sendable {
    func freshAccessToken() async throws -> String
}

// MARK: - OAuthManager protocol

public protocol OAuthManager: TokenProvider {
    func signIn(configuration: OAuthConfiguration) async throws
    func signOut() throws
    /// Loads a persisted session from storage. Returns true if a session was found.
    func restoreSession() throws -> Bool
}

// MARK: - Browser user agent

private final class BrowserUserAgent: NSObject, OIDExternalUserAgent {
    func present(_ request: any OIDExternalUserAgentRequest, session: any OIDExternalUserAgentSession) -> Bool {
        guard let url = request.externalUserAgentRequestURL() else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    func dismiss(animated: Bool, completion: @escaping () -> Void) {
        completion()
    }
}

// MARK: - Live implementation

@Observable
public final class AppAuthOAuthManager: OAuthManager, @unchecked Sendable {
    @ObservationIgnored nonisolated(unsafe) private var authState: OIDAuthState?
    @ObservationIgnored nonisolated(unsafe) private var currentSession: (any OIDExternalUserAgentSession)?
    @ObservationIgnored nonisolated(unsafe) private var redirectHandler: OIDRedirectHTTPHandler?

    public init() {}

    public func signIn(configuration: OAuthConfiguration) async throws {
        let serviceConfig = OIDServiceConfiguration(
            authorizationEndpoint: OAuthConfiguration.authorizationEndpoint,
            tokenEndpoint: OAuthConfiguration.tokenEndpoint
        )

        let newAuthState: OIDAuthState = try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let handler = OIDRedirectHTTPHandler(successURL: nil)
                let redirectURI = handler.startHTTPListener(nil)

                let request = OIDAuthorizationRequest(
                    configuration: serviceConfig,
                    clientId: configuration.clientID,
                    clientSecret: configuration.clientSecret,
                    scopes: configuration.scopes,
                    redirectURL: redirectURI,
                    responseType: OIDResponseTypeCode,
                    additionalParameters: nil
                )

                let userAgent = BrowserUserAgent()
                self.currentSession = OIDAuthState.authState(
                    byPresenting: request,
                    externalUserAgent: userAgent
                ) { authState, error in
                    if let error {
                        continuation.resume(throwing: OAuthError.authorizationFailed(error))
                        return
                    }
                    guard let authState else {
                        continuation.resume(throwing: OAuthError.missingTokens)
                        return
                    }
                    continuation.resume(returning: authState)
                }
                handler.currentAuthorizationFlow = self.currentSession
                self.redirectHandler = handler
            }
        }

        authState = newAuthState
    }

    public func signOut() throws {
        currentSession?.cancel()
        currentSession = nil
        redirectHandler = nil
        authState = nil
    }

    public func restoreSession() throws -> Bool {
        return false
    }

    public func freshAccessToken() async throws -> String {
        guard let authState else { throw OAuthError.notSignedIn }
        return try await withCheckedThrowingContinuation { continuation in
            authState.performAction { accessToken, _, error in
                if let error {
                    continuation.resume(throwing: OAuthError.refreshFailed(error))
                } else if let accessToken {
                    continuation.resume(returning: accessToken)
                } else {
                    continuation.resume(throwing: OAuthError.missingTokens)
                }
            }
        }
    }

}

// MARK: - Auth coordinator

/// Bridges OAuthManager → AuthState. This is what Views interact with.
@MainActor
public final class AuthCoordinator {
    private let oauthManager: any OAuthManager
    private let configuration: OAuthConfiguration

    public init(
        oauthManager: any OAuthManager = AppAuthOAuthManager(),
        configuration: OAuthConfiguration
    ) {
        self.oauthManager = oauthManager
        self.configuration = configuration
    }

    public func signIn(state: AuthState) async {
        guard !configuration.clientID.isEmpty else {
            state.error = .clientIDNotConfigured
            return
        }

        state.isLoading = true
        state.error = nil
        defer { state.isLoading = false }

        do {
            try await oauthManager.signIn(configuration: configuration)
            state.isSignedIn = true
        } catch let error as OAuthError where isUserCancellation(error) {
            state.error = .signInCancelled
        } catch {
            state.error = .signInFailed(underlying: error)
        }
    }

    public func signOut(state: AuthState) {
        do {
            try oauthManager.signOut()
        } catch {
            // Sign-out failure is non-fatal — clear state regardless.
        }
        state.isSignedIn = false
        state.userEmail = nil
    }

    public func restoreSession(state: AuthState) {
        do {
            state.isSignedIn = try oauthManager.restoreSession()
        } catch {
            state.isSignedIn = false
        }
    }

    // MARK: - Private

    private func isUserCancellation(_ error: OAuthError) -> Bool {
        guard case .authorizationFailed(let underlying) = error else { return false }
        let nsError = underlying as NSError
        // OIDErrorCodeUserCanceledAuthorizationFlow = -3, OIDErrorCodeProgramCanceledAuthorizationFlow = -4
        return nsError.domain == OIDGeneralErrorDomain && (nsError.code == -3 || nsError.code == -4)
    }
}
