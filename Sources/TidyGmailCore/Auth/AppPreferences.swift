import Foundation

/// Stores non-secret app preferences.
///
/// The OAuth `client_id` is NOT a secret when using PKCE (RFC 8252 §8.4) —
/// it identifies the app, not a user. Keychain is reserved for tokens only.
@MainActor
public enum AppPreferences {
    private static let clientIDKey     = "com.tidygmail.clientID"
    private static let clientSecretKey = "com.tidygmail.clientSecret"

    /// The OAuth client ID. Priority order:
    ///   1. Bundled in Info.plist at build time (production / CI builds via `build.sh`).
    ///   2. UserDefaults — written by the in-app setup form or `setup-google-oauth.sh`.
    public static var clientID: String? {
        if let bundled = Bundle.main.infoDictionary?["TidyGmailClientID"] as? String,
           !bundled.isEmpty {
            return bundled
        }
        return UserDefaults.standard.string(forKey: clientIDKey)
    }

    /// The OAuth client secret. Google Desktop app clients issue one and require it
    /// in the token exchange even though it is not truly confidential for native apps.
    /// Priority order mirrors clientID (Info.plist → UserDefaults).
    public static var clientSecret: String? {
        if let bundled = Bundle.main.infoDictionary?["TidyGmailClientSecret"] as? String,
           !bundled.isEmpty {
            return bundled
        }
        return UserDefaults.standard.string(forKey: clientSecretKey)
    }

    public static func setClientID(_ value: String) {
        UserDefaults.standard.set(value, forKey: clientIDKey)
    }

    public static func setClientSecret(_ value: String) {
        UserDefaults.standard.set(value, forKey: clientSecretKey)
    }
}
