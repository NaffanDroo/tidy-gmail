import SwiftUI

@MainActor
public struct SignInView: View {
    @Environment(AuthState.self) private var authState

    // Coordinator is @State so it can be rebuilt once the user saves their client ID.
    @State private var coordinator: AuthCoordinator = .makeDefault()

    // Client ID setup form
    @State private var showSetup: Bool = false
    @State private var hasStoredClientID: Bool = false  // set once in .task, never re-read in body
    @State private var clientIDInput: String = ""
    @State private var clientSecretInput: String = ""
    @State private var clientIDSaveError: String?

    public init() {}

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

            if showSetup {
                clientIDSetupForm
            } else {
                signInSection
            }

            Spacer()
            Spacer()
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 400)
        .task { checkSetupRequired() }
    }

    // MARK: - Sign-in section

    private var signInSection: some View {
        VStack(spacing: 16) {
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
                    if authState.isLoading { ProgressView().controlSize(.small) }
                    Text(authState.isLoading ? "Signing in…" : "Sign in with Google")
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(authState.isLoading)
            .accessibilityLabel(authState.isLoading ? "Signing in, please wait" : "Sign in with Google")

            Button("Change OAuth Client ID") { showSetup = true }
                .buttonStyle(.borderless)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - First-run / client ID setup form

    private var clientIDSetupForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("OAuth Client ID required", systemImage: "key.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Create a **Desktop app** OAuth 2.0 client in Google Cloud Console (APIs & Services → Credentials), then paste the Client ID below. It is stored only in app preferences.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Client ID  (e.g. 123456789-abc…apps.googleusercontent.com)", text: $clientIDInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel("Google OAuth Client ID")

            SecureField("Client Secret", text: $clientSecretInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel("Google OAuth Client Secret")

            if let saveError = clientIDSaveError {
                Text(saveError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Save & Continue") { saveClientID() }
                    .buttonStyle(.borderedProminent)
                    .disabled(clientIDInput.trimmingCharacters(in: .whitespaces).isEmpty ||
                              clientSecretInput.trimmingCharacters(in: .whitespaces).isEmpty)

                if hasStoredClientID {
                    Button("Cancel") { showSetup = false }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Private helpers

    private func checkSetupRequired() {
        let storedID     = AppPreferences.clientID
        let storedSecret = AppPreferences.clientSecret
        hasStoredClientID = storedID?.isEmpty == false && storedSecret?.isEmpty == false
        if !hasStoredClientID {
            showSetup = true
        } else {
            coordinator.restoreSession(state: authState)
        }
    }

    private func saveClientID() {
        let trimmedID     = clientIDInput.trimmingCharacters(in: .whitespaces)
        let trimmedSecret = clientSecretInput.trimmingCharacters(in: .whitespaces)
        guard !trimmedID.isEmpty, !trimmedSecret.isEmpty else { return }

        AppPreferences.setClientID(trimmedID)
        AppPreferences.setClientSecret(trimmedSecret)
        hasStoredClientID = true

        // Rebuild coordinator with the new credentials.
        coordinator = AuthCoordinator(
            configuration: OAuthConfiguration(clientID: trimmedID, clientSecret: trimmedSecret)
        )
        clientIDSaveError = nil
        showSetup = false
        authState.error = nil
    }
}

// MARK: - Default factory

extension AuthCoordinator {
    /// Reads client_id from app preferences. If absent the coordinator is still valid;
    /// signIn() will surface .clientIDNotConfigured rather than hitting Google.
    @MainActor
    public static func makeDefault() -> AuthCoordinator {
        let clientID     = AppPreferences.clientID ?? ""
        let clientSecret = AppPreferences.clientSecret
        return AuthCoordinator(
            configuration: OAuthConfiguration(clientID: clientID, clientSecret: clientSecret)
        )
    }
}
