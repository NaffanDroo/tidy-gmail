#!/bin/bash
# Sets up everything Google Cloud needs for Tidy Gmail:
#   - Creates (or reuses) a Google Cloud project
#   - Enables the Gmail and IAP APIs
#   - Configures the OAuth consent screen
#   - Adds the current account as a test user
#   - Creates a Desktop OAuth 2.0 client (client_id + client_secret)
#   - Saves credentials to xcconfig/ (gitignored) and UserDefaults
#
# Prerequisites:
#   brew install google-cloud-sdk
#   gcloud auth login
#
# Usage:
#   bash scripts/setup-google-oauth.sh                        # interactive
#   bash scripts/setup-google-oauth.sh --project my-proj-id  # specific project
#   bash scripts/setup-google-oauth.sh --new                  # always create new

set -euo pipefail

PROJECT_ID=""
CREATE_PROJECT=""   # empty = ask interactively

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

ACTIVE_ACCOUNT=$(gcloud auth list \
    --filter=status:ACTIVE \
    --format='value(account)' \
    --limit=1 \
    2>/dev/null || true)

# ── Project ────────────────────────────────────────────────────────────────────

if [[ -z "$CREATE_PROJECT" && -z "$PROJECT_ID" ]]; then
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

# ── Enable required APIs ───────────────────────────────────────────────────────
# iap.googleapis.com  — required for oauth-brands create (consent screen)
# gmail.googleapis.com — required for the Gmail API calls the app makes

echo "→ Enabling APIs (iap, gmail)…"
gcloud services enable \
    iap.googleapis.com \
    gmail.googleapis.com \
    --project="$PROJECT_ID"

# ── OAuth consent screen ───────────────────────────────────────────────────────
# gcloud alpha iap oauth-brands create sets the app title and support email.
# Idempotent: if a brand already exists for this project it returns an error we
# suppress, then we list to get the existing brand name.

echo "→ Configuring OAuth consent screen…"
gcloud alpha iap oauth-brands create \
    --application_title="Tidy Gmail" \
    --support_email="$ACTIVE_ACCOUNT" \
    --project="$PROJECT_ID" \
    --quiet 2>/dev/null || true

BRAND=$(gcloud alpha iap oauth-brands list \
    --project="$PROJECT_ID" \
    --format='value(name)' \
    --limit=1 \
    2>/dev/null || true)

# ── Test users ─────────────────────────────────────────────────────────────────
# While the app is in Testing mode only listed accounts can sign in.
# PATCH the brand resource to add the current gcloud account as a test user.

if [[ -n "$BRAND" ]]; then
    echo "→ Adding ${ACTIVE_ACCOUNT} as a test user…"
    ACCESS_TOKEN=$(gcloud auth print-access-token)
    PATCH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
        "https://iap.googleapis.com/v1/${BRAND}?updateMask=testUsers" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"testUsers\": [\"${ACTIVE_ACCOUNT}\"]}" \
        2>/dev/null || echo "000")

    if [[ "$PATCH_RESPONSE" != "200" ]]; then
        echo ""
        echo "  ⚠  Could not add test user automatically (HTTP $PATCH_RESPONSE)."
        echo "     Add ${ACTIVE_ACCOUNT} manually at:"
        echo "     https://console.cloud.google.com/apis/credentials/consent?project=${PROJECT_ID}"
        echo ""
        read -rp "  Press Enter once you've added the test user, or Ctrl-C to abort…"
        open "https://console.cloud.google.com/apis/credentials/consent?project=${PROJECT_ID}" 2>/dev/null || true
    fi
else
    echo ""
    echo "  ⚠  Could not determine brand — add ${ACTIVE_ACCOUNT} as a test user manually at:"
    echo "     https://console.cloud.google.com/apis/credentials/consent?project=${PROJECT_ID}"
    echo ""
    open "https://console.cloud.google.com/apis/credentials/consent?project=${PROJECT_ID}" 2>/dev/null || true
    read -rp "  Press Enter once done…"
fi

# ── Create OAuth client ────────────────────────────────────────────────────────

echo "→ Creating Desktop OAuth 2.0 client…"
ACCESS_TOKEN=$(gcloud auth print-access-token)

RESPONSE=$(curl -s -X POST \
    "https://oauth2.googleapis.com/v1/projects/${PROJECT_ID}/oauthClients" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"displayName": "TidyGmail Desktop", "clientType": "DESKTOP_APP"}')

# Fall back to the older endpoint if the v1 one isn't available yet.
if echo "$RESPONSE" | grep -q '"error"'; then
    RESPONSE=$(curl -s -X POST \
        "https://console.googleapis.com/v1/projects/${PROJECT_ID}/oauthClients" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"displayName": "TidyGmail Desktop", "clientType": "DESKTOP_APP"}')
fi

CLIENT_ID=$(echo "$RESPONSE" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('clientId', d.get('name','')))" \
    2>/dev/null || true)
CLIENT_SECRET=$(echo "$RESPONSE" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('clientSecret', ''))" \
    2>/dev/null || true)

if [[ -z "$CLIENT_ID" ]] || echo "$CLIENT_ID" | grep -q "projects/"; then
    echo ""
    echo "  ⚠  Automated client creation hit a policy gate — opening Cloud Console…"
    echo ""
    echo "     Steps:"
    echo "       1. Click '+ CREATE CREDENTIALS' → 'OAuth client ID'"
    echo "       2. Application type: Desktop app"
    echo "       3. Name: TidyGmail Desktop"
    echo "       4. Click Create, then copy the Client ID and Client Secret"
    echo ""
    open "https://console.cloud.google.com/apis/credentials?project=$PROJECT_ID" 2>/dev/null || true
    read -rp "  Paste Client ID: " CLIENT_ID
    read -rp "  Paste Client Secret: " CLIENT_SECRET
fi

if [[ -z "$CLIENT_ID" ]]; then
    echo "  ✗ No Client ID obtained. Exiting."
    exit 1
fi

if [[ -z "$CLIENT_SECRET" ]]; then
    echo "  ✗ No Client Secret obtained. Exiting."
    exit 1
fi

# ── Save credentials ───────────────────────────────────────────────────────────
# xcconfig/ files are gitignored; build.sh reads them and embeds the values in
# the app bundle's Info.plist at build time.
# UserDefaults is a fallback for swift run (no built bundle).

echo "→ Saving credentials to xcconfig/ (gitignored)…"
mkdir -p xcconfig
echo "$CLIENT_ID"     > xcconfig/client_id
echo "$CLIENT_SECRET" > xcconfig/client_secret

echo "→ Saving credentials to app preferences (UserDefaults fallback)…"
defaults write com.tidygmail.app "com.tidygmail.clientID"     "$CLIENT_ID"
defaults write com.tidygmail.app "com.tidygmail.clientSecret" "$CLIENT_SECRET"

# ── Verify ─────────────────────────────────────────────────────────────────────

echo ""
echo "→ Verifying setup…"

GMAIL_ENABLED=$(gcloud services list --enabled \
    --project="$PROJECT_ID" \
    --filter="name:gmail.googleapis.com" \
    --format='value(name)' 2>/dev/null || true)

IAP_ENABLED=$(gcloud services list --enabled \
    --project="$PROJECT_ID" \
    --filter="name:iap.googleapis.com" \
    --format='value(name)' 2>/dev/null || true)

[[ -n "$GMAIL_ENABLED" ]] && echo "  ✓ Gmail API enabled" \
                          || echo "  ✗ Gmail API NOT enabled — run: gcloud services enable gmail.googleapis.com"
[[ -n "$IAP_ENABLED"   ]] && echo "  ✓ IAP API enabled" \
                          || echo "  ✗ IAP API NOT enabled — run: gcloud services enable iap.googleapis.com"
[[ -f "xcconfig/client_id"     ]] && echo "  ✓ xcconfig/client_id saved" \
                                  || echo "  ✗ xcconfig/client_id missing"
[[ -f "xcconfig/client_secret" ]] && echo "  ✓ xcconfig/client_secret saved" \
                                  || echo "  ✗ xcconfig/client_secret missing"

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo "✓ Done!"
echo ""
echo "  Project:       $PROJECT_ID"
echo "  Client ID:     $CLIENT_ID"
echo "  Client Secret: (saved — do not commit)"
echo ""
echo "  Next steps:"
echo "    bash build.sh       — embeds credentials and builds TidyGmail.app"
echo "    open TidyGmail.app  — sign in with ${ACTIVE_ACCOUNT}"
echo ""
