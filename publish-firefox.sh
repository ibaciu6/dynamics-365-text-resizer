#!/usr/bin/env bash
# Publish/update this extension's package on addons.mozilla.org (AMO) via the
# addons-server v5 API. Never hardcode credentials here — they're read from
# the workspace-wide secrets file (gitignored-by-location, never uploaded
# anywhere): /mnt/c/tools/ibaciu6/.secrets.env
#
# Usage:
#   ./publish-firefox.sh <addon-slug> <package.zip> [release-notes]
#
# Example:
#   ./publish-firefox.sh "$AMO_SLUG_DYNAMICS365TEXTRESIZER" dist/dynamics-365-text-resizer-1.0.1-firefox.zip "1.0.1 - fix scrollbar flicker"
#
# Docs: https://mozilla.github.io/addons-server/topics/api/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDS_FILE="$SCRIPT_DIR/../.secrets.env"

[ -f "$CREDS_FILE" ] || { echo "Missing $CREDS_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CREDS_FILE"

ADDON_SLUG="${1:?Usage: $0 <addon-slug> <package.zip> [release-notes]}"
PACKAGE="${2:?Usage: $0 <addon-slug> <package.zip> [release-notes]}"
NOTES="${3:-Automated release}"

[ -f "$PACKAGE" ] || { echo "Package not found: $PACKAGE" >&2; exit 1; }
: "${MOZILLA_JWT_ISSUER:?MOZILLA_JWT_ISSUER not set in $CREDS_FILE}"
: "${MOZILLA_JWT_SECRET:?MOZILLA_JWT_SECRET not set in $CREDS_FILE}"

API_BASE="https://addons.mozilla.org/api/v5"

# JWT is short-lived (max 5 min per Mozilla's docs) — mint one fresh per call
# rather than reusing a token across the whole script.
make_jwt() {
  MOZILLA_JWT_ISSUER="$MOZILLA_JWT_ISSUER" MOZILLA_JWT_SECRET="$MOZILLA_JWT_SECRET" python3 - <<'PY'
import time, json, hmac, hashlib, base64, os, uuid

def b64url(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b'=')

now = int(time.time())
header = {"alg": "HS256", "typ": "JWT"}
payload = {
    "iss": os.environ["MOZILLA_JWT_ISSUER"],
    "jti": str(uuid.uuid4()),
    "iat": now,
    "exp": now + 60,
}
h = b64url(json.dumps(header, separators=(",", ":")).encode())
p = b64url(json.dumps(payload, separators=(",", ":")).encode())
signing_input = h + b"." + p
sig = hmac.new(os.environ["MOZILLA_JWT_SECRET"].encode(), signing_input, hashlib.sha256).digest()
print((signing_input + b"." + b64url(sig)).decode())
PY
}

echo "→ Uploading package: $PACKAGE"
JWT="$(make_jwt)"
UPLOAD_BODY_FILE="$(mktemp)"
UPLOAD_HTTP_CODE="$(curl -sS -o "$UPLOAD_BODY_FILE" -w '%{http_code}' -X POST "${API_BASE}/addons/upload/" \
  -H "Authorization: JWT ${JWT}" \
  -F "upload=@${PACKAGE};type=application/zip" \
  -F "channel=listed")"
UPLOAD_RESP="$(cat "$UPLOAD_BODY_FILE")"
rm -f "$UPLOAD_BODY_FILE"

if [[ ! "$UPLOAD_HTTP_CODE" =~ ^2 ]]; then
  echo "Failed to create upload (HTTP $UPLOAD_HTTP_CODE). Response:" >&2
  echo "$UPLOAD_RESP" >&2
  exit 1
fi
UPLOAD_UUID="$(python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))" <<<"$UPLOAD_RESP")"
echo "✓ Upload created: $UPLOAD_UUID"

echo "→ Waiting for validation..."
VALID=""
for i in $(seq 1 30); do
  JWT="$(make_jwt)"
  STATUS_RESP="$(curl -sS "${API_BASE}/addons/upload/${UPLOAD_UUID}/" -H "Authorization: JWT ${JWT}")"
  PROCESSED="$(python3 -c "import sys,json; print(json.load(sys.stdin).get('processed', False))" <<<"$STATUS_RESP")"
  echo "  [$i/30] processed: $PROCESSED"
  if [ "$PROCESSED" = "True" ]; then
    VALID="$(python3 -c "import sys,json; print(json.load(sys.stdin).get('valid', False))" <<<"$STATUS_RESP")"
    break
  fi
  sleep 5
done

if [ "$VALID" != "True" ]; then
  echo "Upload did not pass validation (or timed out waiting). Full response:" >&2
  echo "$STATUS_RESP" >&2
  exit 1
fi
echo "✓ Upload valid"

echo "→ Creating version on addon: $ADDON_SLUG"
VERSION_BODY="$(python3 - "$UPLOAD_UUID" "$NOTES" <<'PY'
import json, sys
upload_uuid, notes = sys.argv[1], sys.argv[2]
print(json.dumps({"upload": upload_uuid, "release_notes": {"en-US": notes}}))
PY
)"

JWT="$(make_jwt)"
VERSION_BODY_FILE="$(mktemp)"
VERSION_HTTP_CODE="$(curl -sS -o "$VERSION_BODY_FILE" -w '%{http_code}' -X POST \
  "${API_BASE}/addons/addon/${ADDON_SLUG}/versions/" \
  -H "Authorization: JWT ${JWT}" \
  -H "Content-Type: application/json" \
  -d "$VERSION_BODY")"
VERSION_RESP="$(cat "$VERSION_BODY_FILE")"
rm -f "$VERSION_BODY_FILE"

if [[ ! "$VERSION_HTTP_CODE" =~ ^2 ]]; then
  echo "Version creation failed (HTTP $VERSION_HTTP_CODE). Full response:" >&2
  echo "$VERSION_RESP" >&2
  exit 1
fi

VERSION_NUM="$(python3 -c "import sys,json; print(json.load(sys.stdin).get('version',''))" <<<"$VERSION_RESP")"
echo "✓ Version ${VERSION_NUM} submitted for review (HTTP $VERSION_HTTP_CODE)."
echo "  Track status at https://addons.mozilla.org/en-US/developers/addon/${ADDON_SLUG}/versions"
