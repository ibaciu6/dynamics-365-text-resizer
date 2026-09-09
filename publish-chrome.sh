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

: "${CHROME_CLIENT_ID:?CHROME_CLIENT_ID not set in $CREDS_FILE}"
: "${CHROME_CLIENT_SECRET:?CHROME_CLIENT_SECRET not set in $CREDS_FILE}"
: "${CHROME_REFRESH_TOKEN:?CHROME_REFRESH_TOKEN not set in $CREDS_FILE — see the TODO comment next to it}"
: "${CHROME_WEBSTORE_PUBLISHER_ID:?CHROME_WEBSTORE_PUBLISHER_ID not set in $CREDS_FILE}"
: "${CHROME_WEBSTORE_ITEM_DYNAMICS365TEXTRESIZER:?CHROME_WEBSTORE_ITEM_DYNAMICS365TEXTRESIZER not set in $CREDS_FILE}"

API_BASE="https://chromewebstore.googleapis.com"
RESOURCE_NAME="publishers/${CHROME_WEBSTORE_PUBLISHER_ID}/items/${CHROME_WEBSTORE_ITEM_DYNAMICS365TEXTRESIZER}"

VERSION="$(python3 -c "import json; print(json.load(open('${SCRIPT_DIR}/chrome/manifest.json'))['version'])")"

echo "→ Refreshing access token..."
TOKEN_RESP="$(curl -sS --fail-with-body -X POST 'https://oauth2.googleapis.com/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "client_id=${CHROME_CLIENT_ID}" \
  --data-urlencode "client_secret=${CHROME_CLIENT_SECRET}" \
  --data-urlencode "refresh_token=${CHROME_REFRESH_TOKEN}" \
  --data-urlencode 'grant_type=refresh_token')"
ACCESS_TOKEN="$(python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" <<<"$TOKEN_RESP")"
if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  echo "Failed to obtain access token (response withheld — check refresh token validity)." >&2
  exit 1
fi
echo "✓ Got access token"

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

echo "→ Polling validation status..."
for i in $(seq 1 30); do
  STATUS_RESP="$(curl -sS --fail-with-body -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${API_BASE}/v2/${RESOURCE_NAME}:fetchStatus")"
  ITEM_STATE="$(python3 -c "
import sys, json
d = json.load(sys.stdin)
rev = d.get('itemRevisionStatus') or d.get('publishedItemRevisionStatus') or {}
print(rev.get('state',''))
" <<<"$STATUS_RESP")"
  echo "  [$i/30] item state: ${ITEM_STATE:-<unknown>}"
  case "$ITEM_STATE" in
    ITEM_STATE_REJECTED|REJECTED)
      echo "Validation failed. Full response:" >&2
      echo "$STATUS_RESP" >&2
      exit 1
      ;;
    "" ) sleep 5 ;;
    *) break ;;
  esac
done

echo "✓ Upload accepted and validated (uploadState: $UPLOAD_STATE)."

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
  -d '{"publishType":"DEFAULT_PUBLISH"}' \
  "${API_BASE}/v2/${RESOURCE_NAME}:publish")"
echo "$PUBLISH_RESP"

echo "→ Polling publish status..."
for i in $(seq 1 30); do
  STATUS_RESP="$(curl -sS --fail-with-body -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${API_BASE}/v2/${RESOURCE_NAME}:fetchStatus")"
  STATE="$(python3 -c "
import sys, json
d = json.load(sys.stdin)
rev = d.get('itemRevisionStatus') or d.get('publishedItemRevisionStatus') or {}
print(rev.get('state',''))
" <<<"$STATUS_RESP")"
  echo "  [$i/30] state: ${STATE:-<unknown>}"
  case "$STATE" in
    PUBLISHED) echo "✓ Published."; break ;;
    ITEM_STATE_REJECTED|REJECTED) echo "Publish rejected. Full response:" >&2; echo "$STATUS_RESP" >&2; exit 1 ;;
    *) sleep 20 ;;
  esac
done

echo "$STATUS_RESP"
