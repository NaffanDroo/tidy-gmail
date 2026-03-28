import Foundation

public struct OAuthConfiguration: Sendable {
    // Keychain key names — never change these once tokens are in production Keychain entries.
    public enum KeychainKey {
        public static let clientID = "client_id"
        public static let accessToken = "access_token"
        public static let refreshToken = "refresh_token"
        public static let userEmail = "user_email"
    }

    // Google OAuth endpoints.
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    // Scopes. Start with read-only; upgrade to modify when delete story is built.
    public static let readOnlyScopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/userinfo.email",
        "openid",
    ]

    public static let modifyScopes = [
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/userinfo.email",
        "openid",
    ]

    public let clientID: String
    public let redirectURI: URL
    public let scopes: [String]

    public init(clientID: String, redirectURI: URL, scopes: [String] = OAuthConfiguration.readOnlyScopes) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
    }
}

// MARK: - Tokens

public struct OAuthTokens: Sendable {
    public let accessToken: String
    public let refreshToken: String

    public init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

// MARK: - Errors

public enum OAuthError: Error {
    case clientIDNotFound
    case authorizationFailed(Error)
    case missingTokens
    case refreshFailed(Error)
    case noWindowAvailable
}
