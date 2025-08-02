#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------- User-configurable -------------------------------
HUB_BASE="${HUB_URL:-${HUB_ENDPOINT:-}}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
REMOTE_INDEX_URL="${REMOTE_INDEX_URL:-https://raw.githubusercontent.com/ruslanmv/hello-mcp/refs/heads/main/matrix/index.json}"
ENTITY_UID="${ENTITY_UID:-mcp_server:hello-sse-server@0.1.0}"   # type:id@version

echo "▶ Registering Hello SSE via catalog (remote → ingest → install)…"

command -v jq >/dev/null   || { echo "ERROR: jq is required"; exit 1; }
command -v curl >/dev/null || { echo "ERROR: curl is required"; exit 1; }
[[ -n "$HUB_BASE" ]]   || { echo "ERROR: set HUB_URL (e.g. http://127.0.0.1:7300)"; exit 1; }
[[ -n "$ADMIN_TOKEN" ]]|| { echo "ERROR: set ADMIN_TOKEN"; exit 1; }

# ------------------------------ Normalize URL --------------------------------
norm() { printf "%s" "$1" | tr -d '\r' | sed 's:/*$::'; }

HUB_BASE="$(norm "$HUB_BASE")"
[[ "$HUB_BASE" =~ ^https?:// ]] || HUB_BASE="http://${HUB_BASE}"

if [[ "$HUB_BASE" =~ ^https?://0\.0\.0\.0:([0-9]+)$ ]]; then
  PORT="${BASH_REMATCH[1]}"
  echo "⚠️  HUB_URL points to 0.0.0.0; switching to http://127.0.0.1:${PORT}"
  HUB_BASE="http://127.0.0.1:${PORT}"
fi

# Try root and /api, but prefer the one whose /health works
BASES=()
strip_api="$(echo "$HUB_BASE" | sed 's:/api$::')"
add_api="${strip_api}/api"
for c in "$HUB_BASE" "$strip_api" "$add_api"; do
  c="$(norm "$c")"
  [[ " ${BASES[*]} " == *" $c "* ]] || BASES+=("$c")
done

API_BASE=""
for TRY in "${BASES[@]}"; do
  CODE="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 3 "${TRY}/health" || true)"
  echo "→ Probing ${TRY}/health → $CODE"
  if [[ "$CODE" =~ ^(200|204)$ ]]; then API_BASE="$TRY"; break; fi
done
[[ -n "$API_BASE" ]] || { echo "❌ Hub health not responding on candidates: ${BASES[*]}"; exit 1; }

# -------- Discover route style: /remotes vs /catalog/remotes ------------------
detect_catalog_style() {
  local ROOT_REMOTES="${API_BASE}/remotes"
  local CATALOG_REMOTES="${API_BASE}/catalog/remotes"
  local code_root code_cat
  code_root="$(curl -sS -o /dev/null -w "%{http_code}" -X OPTIONS "$ROOT_REMOTES" || true)"
  code_cat="$(curl -sS -o /dev/null -w "%{http_code}" -X OPTIONS "$CATALOG_REMOTES" || true)"
  if [[ "$code_root" =~ ^(200|204|401|403|405|415|422)$ ]]; then
    echo "root"; return
  fi
  if [[ "$code_cat" =~ ^(200|204|401|403|405|415|422)$ ]]; then
    echo "catalog"; return
  fi
  echo ""
}

STYLE="$(detect_catalog_style)"
if [[ -z "$STYLE" ]]; then
  echo "❌ Could not detect catalog route style on $API_BASE (neither /remotes nor /catalog/remotes)."; exit 1;
fi
if [[ "$STYLE" == "root" ]]; then
  REMOTES_URL="${API_BASE}/remotes"
  INGEST_URL="${API_BASE}/ingest"
else
  REMOTES_URL="${API_BASE}/catalog/remotes"
  INGEST_URL="${API_BASE}/catalog/ingest"
fi
INSTALL_URL="${API_BASE}/catalog/install"

echo "→ HUB base: $API_BASE"
echo "→ Style:    $STYLE"
echo "→ REMOTE:   $REMOTE_INDEX_URL"
echo "→ ENTITY:   $ENTITY_UID"

AUTH_HDR=(-H "Authorization: Bearer ${ADMIN_TOKEN}")
JSON_HDR=(-H "Content-Type: application/json")

curl_json() {
  local METHOD="$1"; shift
  local URL="$1"; shift
  local DATA="${1:-}"
  if [[ -n "$DATA" ]]; then
    curl -sS -w $'\n%{http_code}' -X "$METHOD" "$URL" "${AUTH_HDR[@]}" "${JSON_HDR[@]}" -d "$DATA"
  else
    curl -sS -w $'\n%{http_code}' -X "$METHOD" "$URL" "${AUTH_HDR[@]}" "${JSON_HDR[@]}"
  fi
}

# ------------------------------- 1) REMOTE -----------------------------------
echo "→ POST $REMOTES_URL"
R1="$(curl_json POST "$REMOTES_URL" "$(jq -nc --arg url "$REMOTE_INDEX_URL" '{url:$url}')" )"
S1="${R1##*$'\n'}"; B1="${R1%$'\n'*}"
echo "   status: $S1"
if [[ "$S1" =~ ^20[0-9]$ || "$S1" == "409" || "$S1" == "412" ]]; then
  echo "$B1" | jq '.' 2>/dev/null || echo "$B1"
else
  echo "❌ Failed to add remote. Response:"; echo "$B1" | jq '.' 2>/dev/null || echo "$B1"; exit 1
fi

# ------------------------------- 2) INGEST -----------------------------------
echo "→ POST $INGEST_URL"
MAX_RETRIES=3
DELAY=2
for ATTEMPT in $(seq 1 $MAX_RETRIES); do
  R2="$(curl_json POST "$INGEST_URL" "$(jq -nc --arg url "$REMOTE_INDEX_URL" '{url:$url}')" )"
  S2="${R2##*$'\n'}"; B2="${R2%$'\n'*}"
  echo "   attempt $ATTEMPT → status: $S2"
  if [[ "$S2" =~ ^20[0-9]$ || "$S2" == "202" ]]; then
    echo "$B2" | jq '.' 2>/dev/null || echo "$B2"; break
  fi
  if [[ "$ATTEMPT" -lt "$MAX_RETRIES" ]]; then
    echo "   retrying in ${DELAY}s…"; sleep "$DELAY"; DELAY=$((DELAY*2))
  else
    echo "❌ Ingest failed. Response:"; echo "$B2" | jq '.' 2>/dev/null || echo "$B2"; exit 1
  fi
done

# ------------------------------- 3) INSTALL ----------------------------------
echo "→ POST $INSTALL_URL"
PAYLOAD="$(jq -nc --arg id "$ENTITY_UID" --arg target "./" '{id:$id, target:$target}')"
DELAY=2
for ATTEMPT in $(seq 1 $MAX_RETRIES); do
  R3="$(curl_json POST "$INSTALL_URL" "$PAYLOAD")"
  S3="${R3##*$'\n'}"; B3="${R3%$'\n'*}"
  echo "   attempt $ATTEMPT → status: $S3"
  if [[ "$S3" =~ ^20[0-9]$ ]]; then
    echo "✅ Installed/registered:"; echo "$B3" | jq '.' 2>/dev/null || echo "$B3"
    echo "✔ Done."; exit 0
  fi
  if [[ "$ATTEMPT" -lt "$MAX_RETRIES" ]]; then
    echo "   retrying in ${DELAY}s…"; sleep "$DELAY"; DELAY=$((DELAY*2))
  else
    echo "❌ Install failed. Response:"; echo "$B3" | jq '.' 2>/dev/null || echo "$B3"; exit 1
  fi
done
