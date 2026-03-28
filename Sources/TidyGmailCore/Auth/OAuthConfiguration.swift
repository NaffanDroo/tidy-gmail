import Foundation

public struct OAuthConfiguration: Sendable {
    // Google OAuth endpoints.
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    // Scopes. Start with read-only; upgrade to modify when delete story is built.
    public static let readOnlyScopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/userinfo.email",
        "openid"
    ]

    public static let modifyScopes = [
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/userinfo.email",
        "openid"
    ]

    public let clientID: String
    /// Google Desktop app clients issue a client_secret and require it in the token
    /// exchange, even though it is not truly confidential for native apps (RFC 8252 §8.5).
    public let clientSecret: String?
    public let scopes: [String]

    public init(clientID: String, clientSecret: String? = nil, scopes: [String] = OAuthConfiguration.readOnlyScopes) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.scopes = scopes
    }
}

// MARK: - Errors

public enum OAuthError: Error, LocalizedError {
    case clientIDNotFound
    case authorizationFailed(Error)
    case missingTokens
    case refreshFailed(Error)
    case noWindowAvailable
    case redirectServerFailed
    case notSignedIn

    public var errorDescription: String? {
        switch self {
        case .clientIDNotFound:
            return "OAuth client ID not found."
        case .authorizationFailed(let underlying):
            return underlying.localizedDescription
        case .missingTokens:
            return "Authorization succeeded but no tokens were returned."
        case .refreshFailed(let underlying):
            return "Token refresh failed: \(underlying.localizedDescription)"
        case .noWindowAvailable:
            return "No window available to present sign-in."
        case .redirectServerFailed:
            return "Could not start the local redirect server."
        case .notSignedIn:
            return "Not signed in."
        }
    }
}
