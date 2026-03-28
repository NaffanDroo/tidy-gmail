#!/bin/bash
set -euo pipefail

BUNDLE="TidyGmail.app"
BINARY_NAME="TidyGmail"

CONFIG="release"
EXTRA_FLAGS=()

for arg in "$@"; do
    case "$arg" in
        --debug)              CONFIG="debug"; echo "→ Debug build" ;;
        --warnings-as-errors) EXTRA_FLAGS+=(-Xswiftc -warnings-as-errors); echo "→ Warnings as errors" ;;
        *) echo "Unknown flag: $arg" >&2; exit 1 ;;
    esac
done

if [[ ${#EXTRA_FLAGS[@]} -eq 0 && "$CONFIG" == "release" ]]; then
    echo "→ Release build"
fi

echo "→ Resolving dependencies…"
swift package resolve

echo "→ Compiling…"
swift build -c "$CONFIG" ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"}

CONTENTS="$BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
mkdir -p "$MACOS" "$RESOURCES"

echo "→ Assembling bundle…"
cp "$(swift build -c "$CONFIG" --show-bin-path)/$BINARY_NAME" "$MACOS/$BINARY_NAME"
cp Info.plist "$CONTENTS/Info.plist"

# Embed client ID if available (not a secret — safe to bake into the bundle).
# Source priority: TIDY_GMAIL_CLIENT_ID env var → xcconfig/client_id file.
EMBED_CLIENT_ID="${TIDY_GMAIL_CLIENT_ID:-}"
if [[ -z "$EMBED_CLIENT_ID" && -f "xcconfig/client_id" ]]; then
    EMBED_CLIENT_ID=$(tr -d '[:space:]' < xcconfig/client_id)
fi
if [[ -n "$EMBED_CLIENT_ID" ]]; then
    echo "→ Embedding client ID…"
    /usr/libexec/PlistBuddy -c "Add :TidyGmailClientID string $EMBED_CLIENT_ID" "$CONTENTS/Info.plist"
fi

# Embed client secret if available.
# For Google Desktop app clients the secret is distributed in the binary (not truly
# confidential, per RFC 8252 §8.5), but Google still requires it in the token exchange.
# Source priority: TIDY_GMAIL_CLIENT_SECRET env var → xcconfig/client_secret file.
EMBED_CLIENT_SECRET="${TIDY_GMAIL_CLIENT_SECRET:-}"
if [[ -z "$EMBED_CLIENT_SECRET" && -f "xcconfig/client_secret" ]]; then
    EMBED_CLIENT_SECRET=$(tr -d '[:space:]' < xcconfig/client_secret)
fi
if [[ -n "$EMBED_CLIENT_SECRET" ]]; then
    echo "→ Embedding client secret…"
    /usr/libexec/PlistBuddy -c "Add :TidyGmailClientSecret string $EMBED_CLIENT_SECRET" "$CONTENTS/Info.plist"
fi

echo "→ Generating app icon…"
if swift scripts/generate-icon.swift "$RESOURCES" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist"
else
    echo "  ⚠ Icon generation failed (skipping)"
fi

echo "→ Signing bundle…"
# Ad-hoc sign so macOS assigns the correct bundle ID (com.tidygmail.app) to
# the process. Without this the binary runs with no bundle ID, which breaks
# window tab indexing and several AppKit/SwiftUI subsystems.
codesign --force --sign - "$BUNDLE"

echo ""
echo "✓ Built: $BUNDLE"
echo "  Run:   open $BUNDLE"
