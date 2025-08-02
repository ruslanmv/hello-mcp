#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# -------- Config (edit only HUB_URL / ADMIN_TOKEN in your shell) -------------
HUB_BASE="${HUB_URL:-${HUB_ENDPOINT:-}}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
REMOTE_INDEX_URL="https://raw.githubusercontent.com/ruslanmv/hello-mcp/refs/heads/main/matrix/index.json"
ENTITY_UID="mcp_server:hello-sse-server@0.1.0"   # type:id@version

echo "▶ Registering Hello SSE via catalog (remote → ingest → install)…"

command -v jq >/dev/null || { echo "ERROR: jq is required"; exit 1; }
[[ -n "$HUB_BASE" ]] || { echo "ERROR: set HUB_URL (e.g. http://127.0.0.1:7300)"; exit 1; }
[[ -n "$ADMIN_TOKEN" ]] || { echo "ERROR: set ADMIN_TOKEN"; exit 1; }

# Normalize HUB URL
HUB_BASE="$(printf "%s" "$HUB_BASE" | tr -d '\r')"
[[ "$HUB_BASE" =~ ^https?:// ]] || HUB_BASE="http://${HUB_BASE}"
# Warn and auto-fix common pitfall
if [[ "$HUB_BASE" == http://0.0.0.0:* || "$HUB_BASE" == https://0.0.0.0:* ]]; then
  echo "⚠️  HUB_URL points to 0.0.0.0; switching to http://127.0.0.1:$(echo "$HUB_BASE" | awk -F: '{print $NF}')"
  HUB_BASE="http://127.0.0.1:$(echo "$HUB_BASE" | awk -F: '{print $NF}')"
fi

# --- Detect API prefix: try /catalog first, then /api/catalog ----------------
BASE_A="${HUB_BASE%/}"
BASE_B="${HUB_BASE%/}/api"

for TRY in "$BASE_A" "$BASE_B"; do
  PROBE="${TRY}/health"
  echo "→ Probing $PROBE"
  if curl -sS --max-time 3 "$PROBE" >/dev/null; then
    API_BASE="$TRY"
    break
  fi
done

if [[ -z "${API_BASE:-}" ]]; then
  echo "❌ Could not reach Hub health endpoint at $BASE_A/health or $BASE_B/health"
  exit 1
fi

REMOTES_URL="${API_BASE}/catalog/remotes"
INGEST_URL="${API_BASE}/catalog/ingest"
INSTALL_URL="${API_BASE}/catalog/install"

echo "→ HUB base: $API_BASE"
echo "→ REMOTE:   $REMOTE_INDEX_URL"
echo "→ ENTITY:   $ENTITY_UID"

# 1) Add/Update remote
echo "→ POST $REMOTES_URL"
R1="$(curl -sS -w $'\n%{http_code}' -X POST "$REMOTES_URL" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(jq -nc --arg url "$REMOTE_INDEX_URL" '{url:$url}')" )"
S1="${R1##*$'\n'}"; B1="${R1%$'\n'*}"
echo "   status: $S1"
echo "$B1" | jq '.' 2>/dev/null || echo "$B1"

# 2) Ingest remote
echo "→ POST $INGEST_URL"
R2="$(curl -sS -w $'\n%{http_code}' -X POST "$INGEST_URL" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(jq -nc --arg url "$REMOTE_INDEX_URL" '{url:$url}')" )"
S2="${R2##*$'\n'}"; B2="${R2%$'\n'*}"
echo "   status: $S2"
echo "$B2" | jq '.' 2>/dev/null || echo "$B2"

# 3) Install entity by UID
echo "→ POST $INSTALL_URL"
PAYLOAD="$(jq -nc --arg id "$ENTITY_UID" --arg target "./" '{id:$id, target:$target}')"
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
