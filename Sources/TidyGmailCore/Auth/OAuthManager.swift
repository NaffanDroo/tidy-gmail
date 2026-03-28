import AppKit
@preconcurrency import AppAuth

// MARK: - Protocol

/// Abstracts the OAuth flow so it can be replaced with a mock in tests.
public protocol OAuthManager: Sendable {
    func signIn(configuration: OAuthConfiguration) async throws -> OAuthTokens
    func signOut(configuration: OAuthConfiguration, keychain: any KeychainService) throws
}

// MARK: - Browser user agent

/// Minimal OIDExternalUserAgent that opens the authorization URL in the default browser.
/// The redirect is caught by OIDRedirectHTTPHandler's local HTTP listener — no
/// ASWebAuthenticationSession or custom URL scheme required.
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

// MARK: - Live implementation (AppAuth / PKCE)

public final class AppAuthOAuthManager: OAuthManager {
    // Held strongly to keep the in-flight session and HTTP listener alive.
    private nonisolated(unsafe) var currentSession: (any OIDExternalUserAgentSession)?
    private nonisolated(unsafe) var redirectHandler: OIDRedirectHTTPHandler?

    public init() {}

    public func signIn(configuration: OAuthConfiguration) async throws -> OAuthTokens {
        let serviceConfig = OIDServiceConfiguration(
            authorizationEndpoint: OAuthConfiguration.authorizationEndpoint,
            tokenEndpoint: OAuthConfiguration.tokenEndpoint
        )

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                // OIDRedirectHTTPHandler starts a local HTTP server on a random high port
                // and returns http://localhost:PORT/ as the redirect URI.
                // Google allows any http://localhost redirect for Desktop app OAuth clients
                // without requiring explicit registration in the Cloud Console.
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
                    guard
                        let authState,
                        let accessToken = authState.lastTokenResponse?.accessToken,
                        let refreshToken = authState.lastTokenResponse?.refreshToken
                    else {
                        continuation.resume(throwing: OAuthError.missingTokens)
                        return
                    }
                    continuation.resume(returning: OAuthTokens(
                        accessToken: accessToken,
                        refreshToken: refreshToken
                    ))
                }
                // Connect the HTTP listener to the active session so it can
                // resume the flow when the browser hits the redirect URI.
                handler.currentAuthorizationFlow = self.currentSession
                self.redirectHandler = handler
            }
        }
    }

    public func signOut(configuration: OAuthConfiguration, keychain: any KeychainService) throws {
        currentSession?.cancel()
        currentSession = nil
        redirectHandler = nil
        try keychain.delete(forKey: OAuthConfiguration.KeychainKey.accessToken)
        try keychain.delete(forKey: OAuthConfiguration.KeychainKey.refreshToken)
        try keychain.delete(forKey: OAuthConfiguration.KeychainKey.userEmail)
    }
}

// MARK: - Auth coordinator

/// Bridges OAuthManager → AuthState. This is what Views interact with.
@MainActor
public final class AuthCoordinator {
    private let oauthManager: any OAuthManager
    private let keychain: any KeychainService
    private let configuration: OAuthConfiguration

    public init(
        oauthManager: any OAuthManager = AppAuthOAuthManager(),
        keychain: any KeychainService = LiveKeychainService(),
        configuration: OAuthConfiguration
    ) {
        self.oauthManager = oauthManager
        self.keychain = keychain
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
            let tokens = try await oauthManager.signIn(configuration: configuration)
            try keychain.store(tokens.accessToken, forKey: OAuthConfiguration.KeychainKey.accessToken)
            try keychain.store(tokens.refreshToken, forKey: OAuthConfiguration.KeychainKey.refreshToken)
            state.isSignedIn = true
        } catch let error as OAuthError where isUserCancellation(error) {
            state.error = .signInCancelled
        } catch {
            state.error = .signInFailed(underlying: error)
        }
    }

    public func signOut(state: AuthState) {
        do {
            try oauthManager.signOut(configuration: configuration, keychain: keychain)
        } catch {
            // Keychain deletion failure is non-fatal — clear state regardless.
        }
        state.isSignedIn = false
        state.userEmail = nil
    }

    public func restoreSession(state: AuthState) {
        do {
            let token = try keychain.retrieve(forKey: OAuthConfiguration.KeychainKey.accessToken)
            state.isSignedIn = token != nil
            state.userEmail = try keychain.retrieve(forKey: OAuthConfiguration.KeychainKey.userEmail)
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
