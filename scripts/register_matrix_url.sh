#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

HUB_BASE="${HUB_URL:-${HUB_ENDPOINT:-}}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"

echo "▶ Starting registration (by URL)…"

command -v jq >/dev/null || { echo "ERROR: jq is required"; exit 1; }
[[ -n "$HUB_BASE" ]] || { echo "ERROR: set HUB_URL"; exit 1; }
[[ -n "$ADMIN_TOKEN" ]] || { echo "ERROR: set ADMIN_TOKEN"; exit 1; }

HUB_BASE="$(printf "%s" "$HUB_BASE" | tr -d '\r')"
[[ "$HUB_BASE" =~ ^https?:// ]] || HUB_BASE="http://${HUB_BASE}"
INSTALL_URL="${HUB_BASE%/}/catalog/install"

echo "→ HUB:        $INSTALL_URL"
echo "→ Token len:  ${#ADMIN_TOKEN}"

# --- Pick ONE of these payload blocks ---

# Option A: full UID (recommended)
PAYLOAD="$(cat <<'JSON'
{
  "id": "server:hello-sse-server@0.1.0",
  "target": "server",
  "manifest_url": "https://raw.githubusercontent.com/ruslanmv/hello-mcp/refs/heads/main/matrix/hello-server.manifest.json"
}
JSON
)"

# # Option B: short id + top-level version (uncomment to use)
# PAYLOAD="$(cat <<'JSON'
# {
#   "id": "hello-sse-server",
#   "version": "0.1.0",
#   "target": "server",
#   "manifest_url": "https://raw.githubusercontent.com/ruslanmv/hello-mcp/refs/heads/main/matrix/hello-server.manifest.json"
# }
# JSON
# )"

echo "→ POST /catalog/install"
RESP="$(curl -sS -w $'\n%{http_code}' -X POST "$INSTALL_URL" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")"

STATUS="${RESP##*$'\n'}"
BODY="${RESP%$'\n'*}"

echo "→ HTTP status: $STATUS"
if [[ "$STATUS" =~ ^20[0-9]$ ]]; then
  echo "✅ Registered."
  echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
else
  echo "❌ Registration failed."
  echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
  exit 1
fi
