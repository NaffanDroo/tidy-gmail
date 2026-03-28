#!/bin/bash
# One-time developer environment setup.
# Run once after cloning: ./setup.sh
set -euo pipefail

echo "→ Checking requirements…"

if ! command -v brew &>/dev/null; then
    echo "  ✗ Homebrew not found. Install from https://brew.sh then re-run."
    exit 1
fi

# SwiftLint requires full Xcode (not just Command Line Tools) to load SourceKit.
XCODE_PATH=$(xcode-select -p 2>/dev/null || true)
if [[ "$XCODE_PATH" != */Xcode*.app/* ]]; then
    echo "  ✗ Xcode Command Line Tools are selected, but full Xcode is required"
    echo "    for SwiftLint to load SourceKit."
    echo ""
    echo "    Fix: sudo xcode-select -s /Applications/Xcode.app"
    echo ""
    exit 1
fi

echo "→ Installing pre-commit…"
brew install pre-commit

echo "→ Installing SwiftLint…"
brew install swiftlint

echo "→ Installing git hooks (pre-commit, commit-msg, pre-push)…"
pre-commit install
pre-commit install --hook-type commit-msg
pre-commit install --hook-type pre-push

echo ""
echo "✓ Setup complete. Git hooks are active:"
echo "  commit-msg  — validates Conventional Commits format"
echo "  pre-commit  — runs SwiftLint on staged Swift files"
echo "  pre-push    — runs full build + warnings-as-errors + test suite"
echo ""
echo "  To run all hooks manually:  pre-commit run --all-files"
echo "  To bypass in an emergency:  git commit --no-verify  (use sparingly)"
echo ""
echo "Next step — configure Google OAuth:"
echo "  bash scripts/setup-google-oauth.sh"
echo ""
echo "  This creates a Google Cloud project, enables the Gmail API, and"
echo "  saves your OAuth Client ID to the macOS Keychain automatically."
echo "  Requires: brew install google-cloud-sdk && gcloud auth login"
echo ""
