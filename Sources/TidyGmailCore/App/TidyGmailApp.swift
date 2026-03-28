import SwiftUI

@MainActor
public struct TidyGmailApp: App {
    @State private var authState = AuthState()
    @State private var oauthManager = AppAuthOAuthManager()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authState)
                .environment(oauthManager)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 640)
    }
}
