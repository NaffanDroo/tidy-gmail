import Foundation
import Observation

@MainActor
@Observable
public final class AuthState {
    public var isSignedIn: Bool = false
    public var userEmail: String?
    public var isLoading: Bool = false
    public var error: AuthError?

    public init() {}
}

public enum AuthError: Error, LocalizedError {
    case clientIDNotConfigured
    case signInCancelled
    case signInFailed(underlying: Error)
    case tokenRefreshFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .clientIDNotConfigured:
            return "OAuth client ID is not configured. See the setup guide in README.md."
        case .signInCancelled:
            return "Sign-in was cancelled."
        case .signInFailed(let underlying):
            return "Sign-in failed: \(underlying.localizedDescription)"
        case .tokenRefreshFailed(let underlying):
            return "Could not refresh your session: \(underlying.localizedDescription)"
        }
    }
}
