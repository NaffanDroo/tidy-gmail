#!/bin/bash
# Creates a Google Cloud project, enables the Gmail API, and creates a
# Desktop OAuth 2.0 client ID — then saves it to your macOS Keychain.
#
# Prerequisites:
#   brew install google-cloud-sdk
#   gcloud auth login
#
# Usage:
#   bash scripts/setup-google-oauth.sh                        # interactive
#   bash scripts/setup-google-oauth.sh --project my-proj-id  # specific project ID

set -euo pipefail

PROJECT_ID=""
CREATE_PROJECT=true

for arg in "$@"; do
    case "$arg" in
        --project=*) PROJECT_ID="${arg#--project=}"; CREATE_PROJECT=false ;;
        --project)   shift; PROJECT_ID="$1"; CREATE_PROJECT=false ;;
    esac
done

# ── Preflight ──────────────────────────────────────────────────────────────────

if ! command -v gcloud &>/dev/null; then
    echo ""
    echo "  ✗ gcloud CLI not found."
    echo "    Install with:  brew install google-cloud-sdk"
    echo "    Then run:      gcloud auth login"
    echo ""
    exit 1
fi

if ! gcloud auth print-access-token &>/dev/null; then
    echo ""
    echo "  ✗ Not authenticated with gcloud."
    echo "    Run:  gcloud auth login"
    echo ""
    exit 1
fi

# ── Project ────────────────────────────────────────────────────────────────────

if [[ -z "$PROJECT_ID" ]]; then
    PROJECT_ID="tidy-gmail-$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6)"
fi

if [[ "$CREATE_PROJECT" == true ]]; then
    echo "→ Creating Google Cloud project: $PROJECT_ID"
    gcloud projects create "$PROJECT_ID" --name="Tidy Gmail" 2>&1 | grep -v "already exists" || true
else
    echo "→ Using existing project: $PROJECT_ID"
fi

echo "→ Setting active project…"
gcloud config set project "$PROJECT_ID" --quiet

# ── OAuth consent screen ───────────────────────────────────────────────────────

echo "→ Configuring OAuth consent screen (External, testing)…"
# Set to 'external' so you can sign in with your own Google account during dev.
# Publishing status stays 'TESTING' — only explicit test users can sign in.
# Change to 'internal' if you have a Google Workspace org.
gcloud alpha iap oauth-brands create \
    --application_title="Tidy Gmail" \
    --support_email="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)" \
    --project="$PROJECT_ID" 2>/dev/null || true

# ── Enable Gmail API ───────────────────────────────────────────────────────────

echo "→ Enabling Gmail API…"
gcloud services enable gmail.googleapis.com --project="$PROJECT_ID"

# ── Create OAuth client ────────────────────────────────────────────────────────

echo "→ Creating Desktop OAuth 2.0 client…"

# The gcloud CLI does not expose oauth-clients create for desktop apps directly,
# so we use the REST API via gcloud's auth token.
ACCESS_TOKEN=$(gcloud auth print-access-token)

RESPONSE=$(curl -s -X POST \
    "https://oauth2.googleapis.com/v1/projects/${PROJECT_ID}/oauthClients" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "displayName": "TidyGmail Desktop",
        "clientType": "DESKTOP_APP"
    }')

# Fall back to the older API endpoint if the v1 one isn't available yet.
if echo "$RESPONSE" | grep -q '"error"'; then
    RESPONSE=$(curl -s -X POST \
        "https://console.googleapis.com/v1/projects/${PROJECT_ID}/oauthClients" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "displayName": "TidyGmail Desktop",
            "clientType": "DESKTOP_APP"
        }')
fi

CLIENT_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('clientId', d.get('name','')))" 2>/dev/null || true)

if [[ -z "$CLIENT_ID" ]] || echo "$CLIENT_ID" | grep -q "projects/"; then
    # Automated creation hit a policy gate — open Cloud Console as fallback.
    echo ""
    echo "  ⚠  Automated client creation requires the Cloud Console for this project."
    echo "     Opening the Credentials page now…"
    echo ""
    echo "     Steps:"
    echo "       1. Click '+ CREATE CREDENTIALS' → 'OAuth client ID'"
    echo "       2. Application type: Desktop app"
    echo "       3. Name: TidyGmail Desktop"
    echo "       4. Click Create, then copy the Client ID"
    echo "       5. Re-run this script with: --project=$PROJECT_ID"
    echo "         and paste when prompted."
    echo ""
    open "https://console.cloud.google.com/apis/credentials?project=$PROJECT_ID" 2>/dev/null || true
    read -rp "Paste Client ID here: " CLIENT_ID
fi

if [[ -z "$CLIENT_ID" ]]; then
    echo "  ✗ No Client ID obtained. Exiting."
    exit 1
fi

# ── Store in Keychain ──────────────────────────────────────────────────────────

echo "→ Saving Client ID to macOS Keychain (service: com.tidygmail.oauth)…"
security add-generic-password \
    -s "com.tidygmail.oauth" \
    -a "client_id" \
    -w "$CLIENT_ID" \
    -U   # -U = update if exists

echo ""
echo "✓ Done!"
echo ""
echo "  Project:   $PROJECT_ID"
echo "  Client ID: $CLIENT_ID"
echo ""
echo "  The Client ID is now in your Keychain. Open TidyGmail and sign in."
echo ""
echo "  Note: your OAuth app is in TESTING mode. Add test users at:"
echo "  https://console.cloud.google.com/apis/credentials/consent?project=$PROJECT_ID"
echo ""
