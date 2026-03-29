import SwiftUI

@MainActor
public struct RootView: View {
    @Environment(AuthState.self) private var authState

    public init() {}

    public var body: some View {
        if authState.isSignedIn {
            EmailListView()
        } else {
            SignInView()
        }
    }
}
