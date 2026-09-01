#!/usr/bin/env bash
# Publish/update this extension's package on Microsoft Edge Add-ons via the
# Publish API v1.1 (API-key auth — no OAuth token exchange, no tenant ID).
# Never hardcode credentials here — they're read from the workspace-wide
# secrets file (never uploaded anywhere): /mnt/c/tools/ibaciu6/.secrets.env
#
# Usage:
#   ./publish-edge.sh <product-id> <package.zip> [submission-notes]
#
# Example (this extension):
#   ./publish-edge.sh "$EDGE_PRODUCT_ID_DYNAMICS365TEXTRESIZER" dist/dynamics-365-text-resizer-1.0.1-edge.zip "1.0.1 release"
#
# Docs: https://learn.microsoft.com/en-us/microsoft-edge/extensions/update/api/using-addons-api

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDS_FILE="$SCRIPT_DIR/../.secrets.env"

[ -f "$CREDS_FILE" ] || { echo "Missing $CREDS_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CREDS_FILE"

PRODUCT_ID="${1:?Usage: $0 <product-id> <package.zip> [notes]}"
PACKAGE="${2:?Usage: $0 <product-id> <package.zip> [notes]}"
NOTES="${3:-Automated package update}"

[ -f "$PACKAGE" ] || { echo "Package not found: $PACKAGE" >&2; exit 1; }
: "${EDGE_CLIENT_ID:?EDGE_CLIENT_ID not set in $CREDS_FILE}"
: "${EDGE_API_KEY:?EDGE_API_KEY not set in $CREDS_FILE}"

API_BASE="https://api.addons.microsoftedge.microsoft.com"
AUTH_HEADER=(-H "Authorization: ApiKey ${EDGE_API_KEY}" -H "X-ClientID: ${EDGE_CLIENT_ID}")

echo "→ Uploading package: $PACKAGE"
UPLOAD_HEADERS="$(mktemp)"
UPLOAD_STATUS_CODE="$(curl -sS -D "$UPLOAD_HEADERS" -o /dev/null -w '%{http_code}' -X POST \
  "${API_BASE}/v1/products/${PRODUCT_ID}/submissions/draft/package" \
  "${AUTH_HEADER[@]}" \
  -H "Content-Type: application/zip" \
  -T "${PACKAGE}")"

if [ "$UPLOAD_STATUS_CODE" != "202" ]; then
  echo "Upload failed (HTTP $UPLOAD_STATUS_CODE). Response headers:" >&2
  cat "$UPLOAD_HEADERS" >&2
  rm -f "$UPLOAD_HEADERS"
  exit 1
fi

OPERATION_ID="$(grep -i '^location:' "$UPLOAD_HEADERS" | sed -E 's#.*/operations/([a-zA-Z0-9_-]+).*#\1#i' | tr -d '\r')"
rm -f "$UPLOAD_HEADERS"

if [ -z "$OPERATION_ID" ]; then
  echo "Could not determine operation ID from upload response headers." >&2
  exit 1
fi
echo "✓ Upload accepted (202), operation ID: $OPERATION_ID"

echo "→ Polling package processing status..."
STATUS_URL="${API_BASE}/v1/products/${PRODUCT_ID}/submissions/draft/package/operations/${OPERATION_ID}"
STATUS=""
for i in $(seq 1 30); do
  STATUS_RESP="$(curl -sS "$STATUS_URL" "${AUTH_HEADER[@]}")"
  STATUS="$(python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" <<<"$STATUS_RESP")"
  echo "  [$i/30] status: $STATUS"
  case "$STATUS" in
    Succeeded) break ;;
    Failed) echo "Package processing failed:" >&2; echo "$STATUS_RESP" >&2; exit 1 ;;
    *) sleep 10 ;;
  esac
done
[ "$STATUS" = "Succeeded" ] || { echo "Timed out waiting for package processing." >&2; exit 1; }
echo "✓ Package processed"

echo "→ Publishing submission..."
PUBLISH_HEADERS="$(mktemp)"
PUBLISH_STATUS_CODE="$(curl -sS -D "$PUBLISH_HEADERS" -o /dev/null -w '%{http_code}' -X POST \
  "${API_BASE}/v1/products/${PRODUCT_ID}/submissions" \
  "${AUTH_HEADER[@]}" \
  -H "Content-Type: application/json" \
  -d "{\"notes\": \"${NOTES}\"}")"

if [ "$PUBLISH_STATUS_CODE" != "202" ]; then
  echo "Publish request failed (HTTP $PUBLISH_STATUS_CODE). Response headers:" >&2
  cat "$PUBLISH_HEADERS" >&2
  rm -f "$PUBLISH_HEADERS"
  exit 1
fi

PUBLISH_OP_ID="$(grep -i '^location:' "$PUBLISH_HEADERS" | sed -E 's#.*/operations/([a-zA-Z0-9_-]+).*#\1#i' | tr -d '\r')"
rm -f "$PUBLISH_HEADERS"
echo "✓ Publish submitted (202). Operation ID: ${PUBLISH_OP_ID:-<none returned>}"

if [ -n "$PUBLISH_OP_ID" ]; then
  echo "→ Polling publish status..."
  PUBLISH_STATUS_URL="${API_BASE}/v1/products/${PRODUCT_ID}/submissions/operations/${PUBLISH_OP_ID}"
  for i in $(seq 1 30); do
    PSTATUS_RESP="$(curl -sS "$PUBLISH_STATUS_URL" "${AUTH_HEADER[@]}")"
    PSTATUS="$(python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" <<<"$PSTATUS_RESP")"
    echo "  [$i/30] publish status: $PSTATUS"
    case "$PSTATUS" in
      Succeeded) echo "✓ Published."; break ;;
      Failed) echo "Publish failed:" >&2; echo "$PSTATUS_RESP" >&2; exit 1 ;;
      *) sleep 10 ;;
    esac
  done
fi

echo "  Review progress on https://partner.microsoft.com/en-us/dashboard/microsoftedge/${PRODUCT_ID}/submissions"
