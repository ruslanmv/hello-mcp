#!/usr/bin/env bash
set -euo pipefail

# --- Resolve paths (relative to this script) ---------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST_PATH="${REPO_ROOT}/matrix/hello-server.manifest.json"

# --- Minimal required env ----------------------------------------------------
HUB_BASE="${HUB_URL:-${HUB_ENDPOINT:-}}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"

if [[ -z "$HUB_BASE" ]]; then
  echo "ERROR: HUB_URL (or HUB_ENDPOINT) is not set. e.g. export HUB_URL='http://127.0.0.1:7300'" >&2
  exit 1
fi
if [[ -z "$ADMIN_TOKEN" ]]; then
  echo "ERROR: ADMIN_TOKEN is not set. Export your minted admin JWT." >&2
  exit 1
fi
if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "ERROR: Manifest not found at: $MANIFEST_PATH" >&2
  exit 1
fi
command -v jq >/dev/null || { echo "ERROR: 'jq' is required."; exit 1; }

# Normalize HUB URL (strip CR; add scheme if missing)
HUB_BASE="$(printf "%s" "$HUB_BASE" | tr -d '\r')"
[[ "$HUB_BASE" =~ ^https?:// ]] || HUB_BASE="http://${HUB_BASE}"
INSTALL_URL="${HUB_BASE%/}/catalog/install"

echo "→ Registering using: $INSTALL_URL"
echo "→ Manifest:          $MANIFEST_PATH"

# Build wrapper body and POST
WRAPPED_BODY="$(
  jq -c \
    --arg id "hello-sse-server" \
    --arg target "server" \
    --argfile manifest "$MANIFEST_PATH" \
    '{id:$id, target:$target, manifest:$manifest}'
)"

RESP="$(curl -sS -w $'\n%{http_code}' -X POST "$INSTALL_URL" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$WRAPPED_BODY")"

STATUS="${RESP##*$'\n'}"
BODY="${RESP%$'\n'*}"

if [[ "$STATUS" =~ ^20[0-9]$ ]]; then
  ID="$(jq -r '.id // .server.id // .result.id // empty' <<<"$BODY" 2>/dev/null || true)"
  echo "✅ Successfully registered (HTTP $STATUS). ${ID:+id: $ID}"
  echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
else
  echo "❌ Registration failed (HTTP $STATUS). Response:" >&2
  echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
  exit 1
fi
