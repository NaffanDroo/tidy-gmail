import AppKit
import TidyGmailCore

// Ensure a Dock icon and menu bar appear when the binary is run directly
// (e.g. `swift run`). When launched via `open TidyGmail.app` this is a no-op.
NSApplication.shared.setActivationPolicy(.regular)

TidyGmailApp.main()
