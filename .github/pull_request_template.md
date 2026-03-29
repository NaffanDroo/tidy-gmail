## Summary

<!-- What does this PR do and why? -->

## Changes

<!-- Key files changed and the reason for each -->

## Test plan

- [ ] `xcodebuild -scheme TidyGmail -destination 'platform=macOS' build` passes
- [ ] `xcodebuild -scheme TidyGmail -destination 'platform=macOS' test` passes
- [ ] `swiftlint --strict` passes with zero warnings
- [ ] Manually tested the affected flows

## Checklist

- [ ] No credentials, tokens, or secrets committed
- [ ] OAuth tokens written only to Keychain (`kSecClassGenericPassword`)
- [ ] Delete operations have a confirmation gate
- [ ] Exported archive uses AES-256 encryption (if applicable)
- [ ] New network calls go through the mocked test transport in tests
- [ ] New behaviour starts with a failing test (TDD)
- [ ] PR title follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) (`feat:`, `fix:`, `docs:`, etc.)
