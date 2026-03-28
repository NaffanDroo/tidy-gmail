#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "→ Running tests…"
echo ""

# KeychainServiceSpec hits the real macOS Keychain.
# In headless CI the Keychain is available but produces CoreData XPC noise
# in the logs — that is harmless and expected; the tests still pass.
swift test --parallel

echo ""
echo "✓ Tests passed"
