#!/usr/bin/env bash
# Publish/update this extension's package on the Chrome Web Store via the
# Chrome Web Store API V2. Never hardcode credentials here — they're read
# from the workspace-wide secrets file (never printed, never committed):
# /mnt/c/tools/ibaciu6/.secrets.env
#
# Usage:
#   ./publish-chrome.sh [--publish]
#
#   (no flag)   package + upload + validate only, then print the exact
#               follow-up command. Nothing goes live.
#   --publish   also submit the uploaded revision (DEFAULT_PUBLISH) and poll
#               until a terminal state. This is the only mutating call.
#
# Docs:
#   https://developer.chrome.com/docs/webstore/using-api
#   https://developer.chrome.com/docs/webstore/api/reference/rest

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDS_FILE="$SCRIPT_DIR/../.secrets.env"
NAME_PREFIX="dynamics-365-text-resizer"

[ -f "$CREDS_FILE" ] || { echo "Missing $CREDS_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CREDS_FILE"

DO_PUBLISH=0
[ "${1:-}" = "--publish" ] && DO_PUBLISH=1

[ -f "$SCRIPT_DIR/chrome/manifest.json" ] || { echo "Missing $SCRIPT_DIR/chrome/manifest.json" >&2; exit 1; }

: "${CHROME_SERVICE_ACCOUNT:?CHROME_SERVICE_ACCOUNT not set in $CREDS_FILE}"
: "${CHROME_WEBSTORE_PUBLISHER_ID:?CHROME_WEBSTORE_PUBLISHER_ID not set in $CREDS_FILE}"
: "${CHROME_WEBSTORE_ITEM_DYNAMICS365TEXTRESIZER:?CHROME_WEBSTORE_ITEM_DYNAMICS365TEXTRESIZER not set in $CREDS_FILE}"

API_BASE="https://chromewebstore.googleapis.com"
RESOURCE_NAME="publishers/${CHROME_WEBSTORE_PUBLISHER_ID}/items/${CHROME_WEBSTORE_ITEM_DYNAMICS365TEXTRESIZER}"

VERSION="$(python3 -c "import json; print(json.load(open('${SCRIPT_DIR}/chrome/manifest.json'))['version'])")"

# Uses gcloud + service-account impersonation, not the human OAuth refresh
# token — this does not expire the way CHROME_REFRESH_TOKEN does (see
# CLAUDE.md "Chrome Web Store — service-account path"). Requires:
# gcloud installed + logged in (gcloud auth login) as an identity granted
# roles/iam.serviceAccountTokenCreator on CHROME_SERVICE_ACCOUNT, and that
# same service account added to the publisher's "Service account" field in
# the Chrome Web Store Developer Dashboard (Settings page) -- not the
# "Trusted tester accounts" or "Members" fields, those don't grant API access.
command -v gcloud >/dev/null 2>&1 || source "$HOME/google-cloud-sdk/path.bash.inc" 2>/dev/null || true
command -v gcloud >/dev/null 2>&1 || { echo "gcloud not found — see CLAUDE.md for install/login steps" >&2; exit 1; }

echo "→ Minting service-account access token..."
CALLER_TOKEN="$(gcloud auth print-access-token 2>/dev/null || true)"
if [ -z "$CALLER_TOKEN" ]; then
  echo "gcloud has no active login — run: gcloud auth login --no-launch-browser (in a real terminal, not through an automation bridge — see CLAUDE.md)" >&2
  exit 1
fi
SA_TOKEN_RESP="$(curl -sS --fail-with-body -X POST \
  -H "Authorization: Bearer ${CALLER_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d "{\"scope\": [\"https://www.googleapis.com/auth/chromewebstore\"]}" \
  "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${CHROME_SERVICE_ACCOUNT}:generateAccessToken")"
ACCESS_TOKEN="$(python3 -c "import sys,json; print(json.load(sys.stdin).get('accessToken',''))" <<<"$SA_TOKEN_RESP")"
if [ -z "$ACCESS_TOKEN" ]; then
  echo "Failed to mint service-account access token (response withheld — check IAM impersonation grant)." >&2
  exit 1
fi
echo "✓ Got service-account access token"

echo "→ Checking currently published state..."
STATUS_RESP="$(curl -sS --fail-with-body -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${API_BASE}/v2/${RESOURCE_NAME}:fetchStatus")"
CURRENT_VERSION="$(python3 -c "
import sys, json
d = json.load(sys.stdin)
chans = d.get('publishedItemRevisionStatus', {}).get('distributionChannels', [])
print(chans[0]['crxVersion'] if chans else '')
" <<<"$STATUS_RESP")"
echo "  Currently published version: ${CURRENT_VERSION:-<none>}"
echo "  Manifest version to publish: ${VERSION}"

if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" = "$VERSION" ]; then
  echo "Manifest version ${VERSION} is already the published version — bump chrome/manifest.json first." >&2
  exit 1
fi

echo "→ Packaging chrome/ ..."
DIST_DIR="$SCRIPT_DIR/dist"
mkdir -p "$DIST_DIR"
PACKAGE_ZIP="$DIST_DIR/${NAME_PREFIX}-${VERSION}-chrome.zip"
rm -f "$PACKAGE_ZIP"
(cd "$SCRIPT_DIR/chrome" && zip -r -X "$PACKAGE_ZIP" . -x '.*' >/dev/null)

ZIP_ROOT_HAS_MANIFEST="$(unzip -l "$PACKAGE_ZIP" | awk '{print $4}' | grep -c '^manifest\.json$' || true)"
if [ "$ZIP_ROOT_HAS_MANIFEST" != "1" ]; then
  echo "Package does not contain manifest.json at its root — refusing to upload: $PACKAGE_ZIP" >&2
  exit 1
fi
echo "✓ Package built and verified: $PACKAGE_ZIP"

echo "→ Uploading package..."
UPLOAD_RESP="$(curl -sS --fail-with-body -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H 'Content-Type: application/zip' \
  --data-binary "@${PACKAGE_ZIP}" \
  "${API_BASE}/upload/v2/${RESOURCE_NAME}:upload")"
UPLOAD_STATE="$(python3 -c "import sys,json; print(json.load(sys.stdin).get('uploadState',''))" <<<"$UPLOAD_RESP")"
echo "  Upload state: $UPLOAD_STATE"
if [ "$UPLOAD_STATE" = "FAILURE" ]; then
  echo "Upload failed. Full response:" >&2
  echo "$UPLOAD_RESP" >&2
  exit 1
fi

# NOTE: there is no distinct "validation" sub-status separate from uploadState
# to poll here -- fetchStatus right after upload just reflects whatever the
# *currently published* revision's state is (always PUBLISHED once anything
# has ever shipped), which is not a signal about the new upload at all. The
# uploadState check above (FAILURE -> exit 1) is the real signal for this step.
echo "✓ Upload accepted (uploadState: $UPLOAD_STATE)."

if [ "$DO_PUBLISH" -ne 1 ]; then
  echo
  echo "Validation-only run complete. To actually publish this revision, run:"
  echo "  $0 --publish"
  exit 0
fi

echo "→ Submitting for publish..."
PUBLISH_RESP="$(curl -sS --fail-with-body -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"publishType":"DEFAULT_PUBLISH","blockOnWarnings":true}' \
  "${API_BASE}/v2/${RESOURCE_NAME}:publish")"
echo "$PUBLISH_RESP"

# The new revision shows up under `submittedItemRevisionStatus` while it's in
# Google's review queue -- `publishedItemRevisionStatus` keeps reporting the
# OLD live revision's state (always PUBLISHED) until review actually
# completes, which can take anywhere from seconds to days. So "submitted
# successfully, now pending review" is treated as a real success here, not
# just "PUBLISHED" -- don't wait around for manual review to finish.
echo "→ Checking submission status..."
for i in $(seq 1 5); do
  STATUS_RESP="$(curl -sS --fail-with-body -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${API_BASE}/v2/${RESOURCE_NAME}:fetchStatus")"
  RESULT="$(VERSION="$VERSION" python3 -c "
import sys, json, os
d = json.load(sys.stdin)
submitted = d.get('submittedItemRevisionStatus')
published = d.get('publishedItemRevisionStatus', {})
pub_chans = published.get('distributionChannels', [])
pub_version = pub_chans[0]['crxVersion'] if pub_chans else ''
target = os.environ['VERSION']
if submitted is None:
    print('LIVE' if pub_version == target else 'UNKNOWN')
else:
    state = submitted.get('state', '')
    if 'REJECT' in state:
        print('REJECTED')
    elif state == 'PUBLISHED':
        print('LIVE')
    else:
        print('PENDING:' + state)
" <<<"$STATUS_RESP")"
  echo "  [$i/5] $RESULT"
  case "$RESULT" in
    LIVE) echo "✓ Published and already live."; break ;;
    REJECTED) echo "Publish rejected. Full response:" >&2; echo "$STATUS_RESP" >&2; exit 1 ;;
    PENDING:*)
      echo "✓ Submitted successfully — currently ${RESULT#PENDING:} in Google's review queue, NOT live yet."
      echo "$STATUS_RESP"
      exit 0
      ;;
    *) sleep 5 ;;
  esac
done

echo "$STATUS_RESP"
