# CLAUDE.md — Tidy Gmail

This file is the authoritative guide for Claude Code when working in this repository. Read it before making any changes.

---

## Project Overview

**Tidy Gmail** is a native macOS desktop application that lets users authenticate to their Gmail account via OAuth and bulk-manage their inbox — searching, deleting, and exporting emails to a secure local archive.

All credentials are managed through the OS Keychain or 1Password. Nothing sensitive is ever committed to the repository.

---

## Repository Hygiene

- Never commit secrets, tokens, `.env` files, `client_secret*.json`, or any OAuth credentials.
- Keep `client_id` and `client_secret` in the OS Keychain / 1Password only.
- `.gitignore` must cover: `*.p12`, `*.pem`, `token.json`, `credentials.json`, `*.dmg` (built artefacts), `DerivedData/`, `.DS_Store`.
- All PRs require a passing test suite before merge.

---

## Issue & PR Workflow

Templates live in `.github/ISSUE_TEMPLATE/`. Use the right one:

| Template | When to use |
|---|---|
| 🐛 Bug Report | Something is broken |
| 💡 Feature Request | An idea to discuss |
| 🧩 User Story | A well-understood feature ready to build |
| 🔧 Chore | Maintenance, refactoring, CI |

Label convention: `bug`, `enhancement`, `story`, `chore`, `security`, `blocked`.

---

## Development Philosophy

- **TDD / BDD first** — write the test or scenario before the implementation.
- Red → Green → Refactor. No production code without a failing test.
- BDD scenarios are written in Gherkin (`Feature` / `Scenario` / `Given` / `When` / `Then`) and live in `features/` or `Tests/Features/`.
- Unit tests cover pure logic. Integration tests cover Gmail API calls (mocked). UI tests cover user flows end-to-end.
- No feature flags, no backwards-compat shims. Change the code directly.

---

## Architecture Decision Record (ADR-001): Technology Stack

### Context

We need a **local, secure, native macOS GUI app** that:
- Authenticates to Gmail via OAuth 2.0
- Bulk-manages emails (search, delete, export)
- Integrates with macOS Keychain and optionally 1Password CLI
- Produces an encrypted local archive of exported emails
- Must never store credentials in the repository

Three options were evaluated across language, UI framework, testing story, and security posture.

---

### Option A — Swift + SwiftUI ✅ RECOMMENDED

**Stack:** Swift 6, SwiftUI, AppKit bridge where needed, XCTest + Quick/Nimble for BDD, `GoogleAPIClientForREST` or raw `URLSession` + `AppAuth` for OAuth.

**Pros:**
- First-class macOS citizen: Keychain, Sandbox, Hardened Runtime, Notarisation, App Store — all just work.
- SwiftUI declarative UI is fast to build and easy to test at the View layer.
- `Security.framework` exposes AES-256 / Keychain APIs natively; no third-party crypto dependency required.
- Encrypted DMG creation via `hdiutil` or `DiskArbitration` framework is built into the OS.
- `AppAuth-iOS` (also supports macOS) is the gold-standard OAuth PKCE library for Apple platforms.
- Apple Silicon native from day one; binary size ~5–20 MB.
- Quick + Nimble provide full BDD (`describe` / `context` / `it`) within XCTest infrastructure.
- Structured concurrency (`async/await`, `Actor`) makes safe Gmail API pagination trivial.

**Cons:**
- macOS-only (acceptable for this project).
- Requires Xcode; CI needs a macOS runner.
- `GoogleAPIClientForREST` is Objective-C heritage (works fine, just verbose).

**BDD tooling:** Quick 7 + Nimble 13. Scenarios written in Swift DSL; Gherkin-style feature files can be driven via `CucumberSwift` if plain Gherkin output is required.

**Security story:**
- OAuth tokens stored in Keychain (`kSecClassGenericPassword`), never on disk in plaintext.
- Encrypted DMG (`hdiutil create -encryption AES-256`): native, password-protected, mountable on any Mac.
- 1Password CLI (`op`) invocable via `Process` for storing/retrieving the archive passphrase.
- App sandbox prevents filesystem access beyond declared entitlements.

---

### Option B — Python + PyQt6 / PySide6

**Stack:** Python 3.12, PySide6 (Qt 6), `google-auth-oauthlib`, `pytest-bdd` + `behave`, `keyring` for Keychain access.

**Pros:**
- Fastest prototyping; `google-api-python-client` is the reference Gmail SDK.
- `pytest-bdd` supports plain Gherkin `.feature` files natively — excellent BDD story.
- `keyring` library wraps macOS Keychain transparently.
- Larger talent pool; easier to hand off.

**Cons:**
- Qt widgets are not native macOS controls; the app feels foreign (title bar, menus, dialogs all look slightly off).
- Distribution is painful: must bundle Python runtime (~80–150 MB via PyInstaller or Briefcase) or require users to install Python.
- No Hardened Runtime / Notarisation without significant effort; Gatekeeper warnings are common.
- Memory footprint is higher; startup is noticeably slower than native.
- Encrypted DMG requires shelling out to `hdiutil` rather than native SDK calls.

**BDD tooling:** `behave` + plain Gherkin `.feature` files, or `pytest-bdd`. Both are mature and expressive.

**Verdict:** Best BDD story of the three options, but the non-native UX and distribution pain are significant penalties for a polished macOS app.

---

### Option C — Rust + Tauri 2

**Stack:** Rust 1.78+, Tauri 2, TypeScript + React (frontend), `oauth2` crate, `keychain-services` crate, `specta` for type-safe IPC.

**Pros:**
- Binary is tiny (~8–15 MB); uses macOS WebKit (WKWebView) rather than bundling Chromium.
- Memory safety without GC — no data races by definition.
- Tauri 2 supports macOS Keychain via `keychain-services` crate.
- Very strong security model: capabilities-based IPC, allowlist per command.
- `cucumber-rust` provides Gherkin-driven BDD.

**Cons:**
- Steep learning curve for both Rust and Tauri simultaneously.
- Gmail API has no official Rust client; must hand-roll HTTP calls or use community crates.
- UI is a WebView, not native AppKit/SwiftUI — menus, sheets, and drag-and-drop feel slightly off.
- macOS Keychain integration is less battle-tested than `Security.framework` in Swift.
- Longer build times in CI.

**BDD tooling:** `cucumber-rust` with Gherkin `.feature` files.

**Verdict:** Compelling for a security-first, cross-platform product. For a macOS-first app with Keychain and native UX requirements, the ecosystem gaps outweigh the benefits.

---

### Decision

**Option A (Swift + SwiftUI)** is selected.

Rationale:
1. Native macOS UX is a core product value; SwiftUI delivers this with the least friction.
2. `Security.framework` and `hdiutil` give us AES-256 encrypted DMG export with zero external dependencies.
3. Hardened Runtime + Notarisation + Sandbox gives users confidence the app is safe to run.
4. Quick/Nimble BDD is expressive and integrates seamlessly with Xcode CI.
5. `AppAuth` is the recommended PKCE library for Google OAuth on Apple platforms.

---

## Secure Export Format Decision (ADR-002)

### Candidates evaluated

| Format | Encryption | Compression | Portability | Verdict |
|---|---|---|---|---|
| Encrypted DMG (`hdiutil`, AES-256) | AES-256-CBC via macOS | HFS+ compression | macOS only | **Selected** |
| AES-256 ZIP (7-Zip / Info-ZIP) | AES-256 (ZipCrypto is weak — must use WinZip AES) | Deflate / zstd | Universal | Runner-up |
| GPG-encrypted tar.gz | AES-256 or RSA via GPG | gzip / bzip2 | Universal, requires GPG | Good for CLI users |
| Password-protected PDF | 128-bit AES | PDF stream | Universal | Too weak |
| MBOX in AES-256 ZIP | AES-256 | Deflate | Universal | Good hybrid |

**Selected: Encrypted `.dmg` as primary, MBOX inside for email content.**

- The outer container is an encrypted sparse-bundle or read/write DMG (`hdiutil create -encryption AES-256 -stdinpass`).
- Email content is stored as standard `.mbox` files inside the DMG (RFC 4155), one file per label/folder.
- Attachments are stored at their original filenames in an `attachments/` subdirectory.
- A `manifest.json` records metadata (message IDs, checksums, export date) for integrity verification.
- The passphrase is generated randomly at export time and offered to be saved to macOS Keychain or 1Password.

**Why not ZIP?** ZipCrypto (classic ZIP encryption) is trivially broken. WinZip AES-256 ZIP is solid but less native on macOS. DMG encryption is built into the OS and is the format macOS users already understand for secure containers.

---

## Core Features

### 1. Gmail OAuth Authentication
- PKCE flow via `AppAuth` library; no client secret required or stored.
- `client_id` is **not a secret** when using PKCE (RFC 8252 §8.4) — it identifies the app, not a user. Safe to bundle in the binary for a shipped app.
- Distribution strategy by phase:

| Phase | Where `client_id` lives | User experience |
|---|---|---|
| **Dev** | Each developer's own Keychain — run `scripts/setup-google-oauth.sh` | In-app setup form on first launch |
| **Testing** | Shared dev credential in `xcconfig/dev.xcconfig` (gitignored) | In-app setup form, or pre-seeded by test script |
| **Shipped app** | Compiled into the binary via a build-time xcconfig | Invisible — just a "Sign in with Google" button |

- When shipping: add `TIDY_GMAIL_CLIENT_ID = 123…apps.googleusercontent.com` to a gitignored `xcconfig/release.xcconfig`, read it at compile time via `Bundle.main.infoDictionary`, and remove the in-app setup form. The client_id being in the binary is expected and fine.
- Google OAuth app verification is required before the app can be used by more than 100 accounts without a warning screen. See: Google Cloud Console → APIs & Services → OAuth consent screen → Publish app.
- Access tokens and refresh tokens stored in Keychain, never on disk in plaintext.
- Scopes requested: `https://www.googleapis.com/auth/gmail.modify` (minimum viable; allows read + delete but not full account access).
- Token refresh handled transparently by `AppAuth`.

### 2. Search & Bulk Email Management
- Gmail search syntax passthrough (e.g. `from:newsletter@example.com older_than:1y`).
- Results shown in a list with sender, subject, date, size.
- Multi-select via checkbox column or `Cmd+A`.
- **Delete flow:** confirmation sheet showing count + sample subjects before any destructive action. Soft-delete (move to Trash) by default; permanent delete requires a second confirmation.
- **Export flow:** prompts for destination path and passphrase before any data leaves Gmail.
- Pagination handled via `nextPageToken`; large result sets stream into the UI progressively.

### 3. Secure Archive Export
- Exports selected emails (headers + body + attachments) to an encrypted `.dmg`.
- Passphrase can be saved to macOS Keychain or 1Password CLI (`op item create`).
- Progress shown in a sheet; cancellable at any point.
- Manifest written last; incomplete archives are deleted on cancel.

### 4. Password Manager Integration
- **macOS Keychain** (default): uses `Security.framework` directly.
- **1Password CLI** (`op`): detected at `/usr/local/bin/op` or via `which op`; used for storing archive passphrases and optionally OAuth tokens.
- Integration is optional; if neither is configured, the user must manage their passphrase manually.

---

## Proposed Additional Features (awaiting sign-off)

These are ideas I want to run past you before building. Each is scoped as a potential User Story:

1. **Sender Space Analyser** — visualise which senders consume the most storage. Useful for identifying bulk-unsubscribe candidates before you delete. Shows a ranked list with total size and message count per sender domain.

2. **Unsubscribe Assistant** — detect `List-Unsubscribe` headers in selected emails and present a one-click "unsubscribe from all" action. Follows RFC 2369 / RFC 8058 (one-click POST unsubscribe) where supported.

3. **Smart Age-Based Rules** — define rules like "delete all Promotions older than 90 days" that can be run on demand or on a schedule (using macOS `launchd`). Rules stored locally; no cloud sync.

4. **Duplicate Detector** — find emails with identical `Message-ID` headers or identical body hashes and offer to deduplicate. Useful after migrations or accidental re-imports.

5. **Attachment Extractor** — bulk-save attachments from a search result to a local folder, with options to also delete the emails after extraction or strip the attachment from the email.

6. **Read Receipt Stripper** — detect and remove tracking pixels (1×1 image links from known tracker domains) before exporting, so exported archives don't contain call-home URLs.

7. **Offline Label Manager** — view, rename, merge, and delete Gmail labels without opening the browser. Includes bulk re-labelling of search results.

8. **Scheduled Export** — define a recurring export job (e.g. "export Starred emails every Sunday") using macOS `launchd`. Archives accumulate incrementally; manifest tracks already-exported message IDs.

9. **Export to Apple Mail / Mimestream** — import the `.mbox` from the DMG directly into Apple Mail (`Mail.app`) via the standard `MboxImport` mechanism, or into Mimestream.

10. **Dark Mode & Accessibility** — full VoiceOver support, Dynamic Type, and system accent colour compliance from day one (not a bolt-on).

> Please confirm, reject, or reprioritise each of the above before any implementation begins.

---

## Testing Strategy

```
Tests/
  Unit/           # Pure logic: search query builder, token refresh, manifest writer
  Integration/    # Gmail API calls against a mock HTTP server (OHHTTPStubs or URLProtocol)
  Features/       # BDD scenarios (Quick/Nimble DSL or CucumberSwift .feature files)
  UI/             # XCUITest end-to-end flows
```

- Every new behaviour starts with a failing test.
- BDD scenarios are written in the `Features/` directory using Gherkin-style `describe`/`context`/`it` blocks.
- Integration tests mock the Gmail API at the `URLSession` transport layer; no real network calls in CI.
- UI tests run against a sandboxed test account using a dedicated Google Cloud project with test fixtures.
- Coverage target: 80% line coverage minimum; 100% on auth and delete paths.

---

## CI / CD

- GitHub Actions on `ubuntu-latest` is not sufficient; macOS runner required (`macos-14`).
- Workflow: lint → unit tests → integration tests → BDD scenarios → build → notarise (main branch only).
- Secrets in GitHub Actions: `GOOGLE_CLIENT_ID`, `APPLE_DEVELOPER_CERT`, `NOTARISATION_PASSWORD` — never in code.

---

## Directory Structure (planned)

```
tidy-gmail/
  TidyGmail/                  # Xcode project root
    App/                      # App entry point, scene setup
    Auth/                     # OAuth, token storage, AppAuth wrapper
    Gmail/                    # Gmail API client, models, pagination
    BulkOps/                  # Search, select, delete, export coordinators
    Export/                   # DMG creation, MBOX writer, manifest
    PasswordManager/          # Keychain + 1Password CLI adapters
    UI/                       # SwiftUI views and view models
    Resources/                # Assets, localisation
  Tests/
    Unit/
    Integration/
    Features/
    UI/
  features/                   # Gherkin .feature files (if using CucumberSwift)
  .github/
    ISSUE_TEMPLATE/
    workflows/
  CLAUDE.md
  README.md
```

---

## Commands

```bash
# Build
xcodebuild -scheme TidyGmail -destination 'platform=macOS' build

# Run all tests
xcodebuild -scheme TidyGmail -destination 'platform=macOS' test

# Run only BDD feature tests
xcodebuild -scheme TidyGmail -destination 'platform=macOS' -only-testing:TidyGmailTests/Features test

# Lint
swiftlint --strict

# Create encrypted DMG (manual test)
hdiutil create -size 100m -encryption AES-256 -volname "TidyGmail-Export" -fs HFS+ /tmp/test-export.dmg
```

---

## Branch Protection & Rulesets

Rulesets are stored as code in `.github/rulesets/` and mirror the configuration from the reference repo. Apply them once the repo exists on GitHub:

```bash
# Apply the main branch protection ruleset
gh api repos/{owner}/tidy-gmail/rulesets --method POST --input .github/rulesets/main.json

# Apply the signed-commits ruleset (created as disabled — enable when team has GPG configured)
gh api repos/{owner}/tidy-gmail/rulesets --method POST --input .github/rulesets/signed-commits.json
```

**Rules enforced on `main`:**

| Rule | Detail |
|---|---|
| No deletion | `main` cannot be deleted |
| No force push | Non-fast-forward pushes blocked |
| Required linear history | Merge commits disallowed; squash-only merge |
| Pull request required | Min. 1 approving review; stale reviews dismissed on new push |
| Thread resolution | All review threads must be resolved before merge |
| Required status checks | `Build & Test`, `SwiftLint`, `Conventional Commits` must pass |
| CodeQL scanning | High/critical security alerts block merge |

**Signed commits ruleset** is disabled by default. Enable it via GitHub UI or `gh api` once the team has GPG signing in place.

**Required status checks map to workflows:**

| Check name | Workflow | Job name |
|---|---|---|
| `Build & Test` | `ci.yml` | `build-and-test` |
| `SwiftLint` | `lint.yml` | `swiftlint` |
| `Conventional Commits` | `pr-title.yml` | `lint-pr-title` |

Note: status check names in `main.json` must exactly match the `name:` field of the workflow job. Update `main.json` if job names change.

---

## Security Checklist (per PR)

- [ ] No credentials, tokens, or secrets committed
- [ ] OAuth tokens written only to Keychain (`kSecClassGenericPassword`)
- [ ] Delete operations have a confirmation gate
- [ ] Exported archive uses AES-256 encryption
- [ ] New network calls go through the mocked test transport in tests
- [ ] `swiftlint` passes with zero warnings
