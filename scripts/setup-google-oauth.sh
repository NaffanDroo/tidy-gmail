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
CREATE_PROJECT=""   # empty = ask the user

for arg in "$@"; do
    case "$arg" in
        --project=*) PROJECT_ID="${arg#--project=}"; CREATE_PROJECT=false ;;
        --project)   shift; PROJECT_ID="$1"; CREATE_PROJECT=false ;;
        --new)       CREATE_PROJECT=true ;;
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

if [[ -z "$CREATE_PROJECT" && -z "$PROJECT_ID" ]]; then
    # Ask the user what they want to do.
    echo ""
    EXISTING=$(gcloud projects list --format='value(projectId)' 2>/dev/null || true)

    if [[ -n "$EXISTING" ]]; then
        echo "Your existing Google Cloud projects:"
        echo "$EXISTING" | while IFS= read -r pid; do echo "  $pid"; done
        echo ""
        read -rp "Use an existing project, or create a new one? [existing/new]: " CHOICE
    else
        echo "No existing Google Cloud projects found."
        CHOICE="new"
    fi

    case "$CHOICE" in
        new|n|N)   CREATE_PROJECT=true ;;
        *)         CREATE_PROJECT=false
                   read -rp "Project ID to use: " PROJECT_ID ;;
    esac
fi

if [[ "$CREATE_PROJECT" == true && -z "$PROJECT_ID" ]]; then
    SUFFIX=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom 2>/dev/null | dd bs=1 count=6 2>/dev/null || true)
    PROJECT_ID="tidy-gmail-${SUFFIX}"
    echo ""
    echo "→ Creating Google Cloud project: $PROJECT_ID"
    CREATE_OUT=$(gcloud projects create "$PROJECT_ID" --name="Tidy Gmail" 2>&1 || true)
    if [[ -n "$CREATE_OUT" ]] && ! echo "$CREATE_OUT" | grep -qi "already exists"; then
        echo "$CREATE_OUT"
    fi
else
    echo "→ Using existing project: $PROJECT_ID"
fi

echo "→ Setting active project…"
gcloud config set project "$PROJECT_ID" --quiet

# ── OAuth consent screen ───────────────────────────────────────────────────────

echo "→ Configuring OAuth consent screen (External, testing)…"
# Capture the active account without piping through head — head closing the
# read-end after one line sends SIGPIPE to gcloud, which pipefail then treats
# as a fatal error.  --limit=1 lets gcloud stop itself cleanly instead.
ACTIVE_ACCOUNT=$(gcloud auth list \
    --filter=status:ACTIVE \
    --format='value(account)' \
    --limit=1 \
    2>/dev/null || true)

# iap oauth-brands create is best-effort; it may fail if the consent screen
# is already configured or if the alpha component is not installed.
# Do NOT redirect stderr — gcloud alpha may prompt to install the component,
# and silencing that makes it appear to hang waiting for hidden input.
gcloud alpha iap oauth-brands create \
    --application_title="Tidy Gmail" \
    --support_email="$ACTIVE_ACCOUNT" \
    --project="$PROJECT_ID" \
    --quiet || true

# ── Enable Gmail API ───────────────────────────────────────────────────────────

echo "→ Enabling Gmail API…"
gcloud services enable gmail.googleapis.com --project="$PROJECT_ID"

# ── Create OAuth client ────────────────────────────────────────────────────────

echo "→ Creating Desktop OAuth 2.0 client…"

ACCESS_TOKEN=$(gcloud auth print-access-token)

RESPONSE=$(curl -s -X POST \
    "https://oauth2.googleapis.com/v1/projects/${PROJECT_ID}/oauthClients" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "displayName": "TidyGmail Desktop",
        "clientType": "DESKTOP_APP"
    }')

# Fall back to the older endpoint if the v1 one isn't available yet.
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

CLIENT_ID=$(echo "$RESPONSE" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('clientId', d.get('name','')))" \
    2>/dev/null || true)

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
    -U

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
