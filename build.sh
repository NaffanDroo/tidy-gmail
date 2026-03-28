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

echo "→ Signing bundle…"
# Ad-hoc sign so macOS assigns the correct bundle ID (com.tidygmail.app) to
# the process. Without this the binary runs with no bundle ID, which breaks
# window tab indexing and several AppKit/SwiftUI subsystems.
codesign --force --sign - "$BUNDLE"

echo ""
echo "✓ Built: $BUNDLE"
echo "  Run:   open $BUNDLE"
