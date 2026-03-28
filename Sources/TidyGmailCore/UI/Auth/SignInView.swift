import SwiftUI

@MainActor
public struct SignInView: View {
    @Environment(AuthState.self) private var authState
    private let coordinator: AuthCoordinator

    public init(coordinator: AuthCoordinator = .makeDefault()) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Tidy Gmail")
                    .font(.largeTitle.bold())

                Text("Sign in to bulk-manage your inbox.\nYour credentials never leave this device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let error = authState.error {
                Text(error.localizedDescription)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityLabel("Sign-in error: \(error.localizedDescription)")
            }

            Button {
                Task { await coordinator.signIn(state: authState) }
            } label: {
                HStack {
                    if authState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(authState.isLoading ? "Signing in…" : "Sign in with Google")
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(authState.isLoading)
            .accessibilityLabel(authState.isLoading ? "Signing in, please wait" : "Sign in with Google")

            Spacer()
            Spacer()
        }
        .padding(40)
        .frame(minWidth: 420, minHeight: 360)
        .task { coordinator.restoreSession(state: authState) }
    }
}

// MARK: - Default factory

extension AuthCoordinator {
    /// Production coordinator. Reads client_id from Keychain at start-up.
    @MainActor
    public static func makeDefault() -> AuthCoordinator {
        let keychain = LiveKeychainService()
        let clientID = (try? keychain.retrieve(forKey: OAuthConfiguration.KeychainKey.clientID)) ?? ""
        let redirectURI = URL(string: "http://127.0.0.1")! // AppAuth picks a free port at runtime.
        return AuthCoordinator(
            configuration: OAuthConfiguration(clientID: clientID, redirectURI: redirectURI)
        )
    }
}
