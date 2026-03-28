import SwiftUI

@MainActor
public struct TidyGmailApp: App {
    @State private var authState = AuthState()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authState)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 640)
    }
}
