#!/bin/bash
set -euo pipefail

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

echo ""
echo "✓ Build complete"
