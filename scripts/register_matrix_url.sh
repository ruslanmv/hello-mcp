#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --- Config ------------------------------------------------------------------
HUB_BASE="${HUB_URL:-${HUB_ENDPOINT:-}}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
REMOTE_INDEX_URL="https://raw.githubusercontent.com/ruslanmv/hello-mcp/refs/heads/main/matrix/index.json"
UID="mcp_server:hello-sse-server@0.1.0"   # type:id@version (NOTE: mcp_server)

echo "▶ Registering Hello SSE via catalog (remote → ingest → install)…"

command -v jq >/dev/null || { echo "ERROR: jq is required"; exit 1; }
[[ -n "$HUB_BASE" ]] || { echo "ERROR: set HUB_URL (e.g. http://127.0.0.1:7300)"; exit 1; }
[[ -n "$ADMIN_TOKEN" ]] || { echo "ERROR: set ADMIN_TOKEN"; exit 1; }

# Normalize HUB URL
HUB_BASE="$(printf "%s" "$HUB_BASE" | tr -d '\r')"
[[ "$HUB_BASE" =~ ^https?:// ]] || HUB_BASE="http://${HUB_BASE}"

REMOTES_URL="${HUB_BASE%/}/catalog/remotes"
INGEST_URL="${HUB_BASE%/}/catalog/ingest"
INSTALL_URL="${HUB_BASE%/}/catalog/install"

echo "→ HUB:     $HUB_BASE"
echo "→ REMOTE:  $REMOTE_INDEX_URL"
echo "→ UID:     $UID"

# --- 1) Add (or update) remote ----------------------------------------------
echo "→ POST $REMOTES_URL"
R1="$(curl -sS -w $'\n%{http_code}' -X POST "$REMOTES_URL" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(jq -nc --arg url "$REMOTE_INDEX_URL" '{url:$url}')" )"
S1="${R1##*$'\n'}"; B1="${R1%$'\n'*}"
echo "   status: $S1"
echo "$B1" | jq '.' 2>/dev/null || echo "$B1"

# --- 2) Ingest the remote (pulls manifest into catalog) ----------------------
echo "→ POST $INGEST_URL"
R2="$(curl -sS -w $'\n%{http_code}' -X POST "$INGEST_URL" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(jq -nc --arg url "$REMOTE_INDEX_URL" '{url:$url}')" )"
S2="${R2##*$'\n'}"; B2="${R2%$'\n'*}"
echo "   status: $S2"
echo "$B2" | jq '.' 2>/dev/null || echo "$B2"

# --- 3) Install by UID (this registers with the Gateway via mcp_registration) -
echo "→ POST $INSTALL_URL"
PAYLOAD="$(jq -nc --arg id "$UID" --arg target "./" '{id:$id, target:$target}')"
R3="$(curl -sS -w $'\n%{http_code}' -X POST "$INSTALL_URL" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" )"
S3="${R3##*$'\n'}"; B3="${R3%$'\n'*}"
echo "   status: $S3"
if [[ "$S3" =~ ^20[0-9]$ ]]; then
  echo "✅ Installed/registered:"
  echo "$B3" | jq '.' 2>/dev/null || echo "$B3"
else
  echo "❌ Install failed:"
  echo "$B3" | jq '.' 2>/dev/null || echo "$B3"
  exit 1
fi

echo "✔ Done."
