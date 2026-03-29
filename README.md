# Tidy Gmail

Tidy Gmail is a native macOS app to bulk-manage and securely export Gmail messages.

Key goals:

- Fast, native macOS experience (Swift + SwiftUI).
- Secure OAuth via PKCE; tokens stored in macOS Keychain.
- Bulk search, delete, and export emails to an encrypted DMG containing standard MBOX files.

**Requirements**

- macOS 12+ (developed and tested on macOS).
- Xcode (for building from source) or use the provided prebuilt app in `TidyGmail.app`.

**Quick Start (build & run)**

1. Clone the repo:

	git clone <repo-url>

2. From the repository root, build a debug bundle:

	bash build.sh --debug

	Or for a release build:

	bash build.sh

3. Run the app (after building):

	open TidyGmail.app

Notes:

- The project uses an Xcode toolchain and Swift packages declared in `Package.swift`.
- If you prefer Xcode, open the workspace in Xcode and run the `TidyGmail` scheme.

**OAuth / Credentials**

- OAuth `client_id` and `client_secret` are expected to be kept out of the repo. See `scripts/setup-google-oauth.sh` for local setup instructions.
- Tokens and passphrases are stored only in the macOS Keychain by default. Do not commit any `credentials.json` or token files.

**Features**

- Sign in with Google (PKCE/AppAuth).
- Search Gmail using native Gmail search syntax.
- Bulk actions: move to Trash, permanent delete (with confirmation).
- Export selected messages (headers, bodies, attachments) to an AES-256 encrypted `.dmg` containing `.mbox` files and a `manifest.json`.
- Optional 1Password CLI integration for storing archive passphrases.

**Security & Privacy**

- OAuth tokens are saved to the macOS Keychain.
- Exports use macOS-built `hdiutil` AES-256 encrypted DMG format.
- No credentials or OAuth secrets should be committed to the repository—see `CLAUDE.md` security guidance.

**Testing**

- Unit and feature tests are in `Tests/TidyGmailTests`. Run the test helper:

  bash test.sh

- Tests mock network interactions; CI should run on macOS runners.

**Directory overview**

- `Sources/TidyGmail` — App entry & SwiftUI views
- `Sources/TidyGmailCore` — Core logic: `Auth/`, `Gmail/`, `Export/`, `PasswordManager/`, `UI/`
- `Tests/` — Unit, integration, and BDD feature tests
- `scripts/` — helper scripts (OAuth setup, icon generation, CI helpers)

**Contributing**

- Follow TDD/BDD: add failing tests before implementing features.
- PRs must pass the test suite and linting.
- Use the issue templates under `.github/ISSUE_TEMPLATE/` and label PRs appropriately (bug, enhancement, story, chore).

**Developer notes**

- Use `scripts/setup-google-oauth.sh` to configure local OAuth credentials in a secure location (Keychain / gitignored xcconfig) for development.
- When changing code that affects exported formats or encryption, update `Export/ManifestWriter.swift` and corresponding tests in `Tests/TidyGmailTests/Unit/Export`.

**License & Attribution**

This project is licensed under the terms in `LICENSE`.

**Need help or found an issue?**

Open an issue using the bug template or start a discussion in the repository.

--
Generated README: keep this updated when user-visible behavior, install, or security guidance changes.
