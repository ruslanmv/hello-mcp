#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# scripts/register_matrix_url.sh
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------- User-configurable -------------------------------
HUB_BASE="${HUB_URL:-${HUB_ENDPOINT:-}}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
REMOTE_INDEX_URL="${REMOTE_INDEX_URL:-https://raw.githubusercontent.com/ruslanmv/hello-mcp/refs/heads/main/matrix/index.json}"
ENTITY_UID="${ENTITY_UID:-mcp_server:hello-sse-server@0.1.0}"   # type:id@version
# Optional: force manifest URL (skips reading index to discover it)
MANIFEST_URL="${MANIFEST_URL:-}"

echo "▶ Registering via catalog (remote → ingest → install)…"

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

# ----------------------- Helpers for fallback install -------------------------
# NOTE: do NOT use the name 'UID' here (readonly in bash). Use 'uid_str'.
parse_uid() {
  local uid_str="$1"
  TYPE="${uid_str%%:*}"
  local rest="${uid_str#*:}"
  ID="${rest%@*}"
  VERSION="${uid_str##*@}"
}

fetch_json() {
  local URL="$1"
  curl -fsSL "$URL"
}

discover_manifest_from_index() {
  # Sets GLOBAL var DISCOVERED_MANIFEST (json) and/or DISCOVERED_MANIFEST_URL (string)
  local IDX_JSON
  IDX_JSON="$(fetch_json "$REMOTE_INDEX_URL")" || {
    echo "❌ Failed to fetch index: $REMOTE_INDEX_URL"
    return 1
  }
  # find the entry matching type/id/version
  local ENTRY
  ENTRY="$(jq -c --arg t "$TYPE" --arg id "$ID" --arg v "$VERSION" \
      '.entities[]? | select(.type==$t and .id==$id and .version==$v)' \
      <<<"$IDX_JSON")" || true

  if [[ -z "$ENTRY" || "$ENTRY" == "null" ]]; then
    echo "❌ Could not find ${ENTITY_UID} in index.json"
    return 1
  fi

  DISCOVERED_MANIFEST="$(jq -c '.manifest // empty' <<<"$ENTRY")"
  DISCOVERED_MANIFEST_URL="$(jq -r '.manifest_url // empty' <<<"$ENTRY")"

  if [[ -n "$DISCOVERED_MANIFEST" ]]; then
    return 0
  fi
  if [[ -n "$DISCOVERED_MANIFEST_URL" ]]; then
    local MJSON
    MJSON="$(fetch_json "$DISCOVERED_MANIFEST_URL")" || {
      echo "❌ Failed to fetch manifest_url: $DISCOVERED_MANIFEST_URL"
      return 1
    }
    DISCOVERED_MANIFEST="$(jq -c '.' <<<"$MJSON")"
    return 0
  fi

  echo "❌ Entry has neither manifest nor manifest_url"
  return 1
}

direct_install_with_manifest() {
  # Uses MANIFEST_URL (if provided) or discovers from index
  local MANIFEST_JSON=""
  if [[ -n "$MANIFEST_URL" ]]; then
    echo "→ Fetching manifest from MANIFEST_URL override: $MANIFEST_URL"
    MANIFEST_JSON="$(fetch_json "$MANIFEST_URL")" || {
      echo "❌ Could not fetch MANIFEST_URL: $MANIFEST_URL"; return 1;
    }
  else
    echo "→ Discovering manifest from index.json"
    DISCOVERED_MANIFEST=""
    DISCOVERED_MANIFEST_URL=""
    discover_manifest_from_index || return 1
    MANIFEST_JSON="$DISCOVERED_MANIFEST"
    if [[ -z "$MANIFEST_JSON" ]]; then
      echo "❌ Discovery failed (no manifest found)"; return 1
    fi
  fi

  echo "→ POST $INSTALL_URL (direct install with inline manifest)"
  local PAYLOAD
  PAYLOAD="$(jq -nc --argjson m "$MANIFEST_JSON" '{target:"./", manifest:$m}')"
  local R S B
  R="$(curl -sS -w $'\n%{http_code}' -X POST "$INSTALL_URL" \
        "${AUTH_HDR[@]}" "${JSON_HDR[@]}" -d "$PAYLOAD")"
  S="${R##*$'\n'}"; B="${R%$'\n'*}"
  echo "   status: $S"
  if [[ "$S" =~ ^20[0-9]$ ]]; then
    echo "✅ Installed/registered (direct):"; echo "$B" | jq '.' 2>/dev/null || echo "$B"
    echo "✔ Done."
    exit 0
  else
    echo "❌ Direct install failed:"; echo "$B" | jq '.' 2>/dev/null || echo "$B"
    return 1
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
MAX_RETRIES=2
DELAY=2
INGEST_OK=0
R2=""; S2=""; B2=""
for ATTEMPT in $(seq 1 $MAX_RETRIES); do
  R2="$(curl_json POST "$INGEST_URL" "$(jq -nc --arg url "$REMOTE_INDEX_URL" '{url:$url}')" )"
  S2="${R2##*$'\n'}"; B2="${R2%$'\n'*}"
  echo "   attempt $ATTEMPT → status: $S2"
  echo "$B2" | jq '.' 2>/dev/null || echo "$B2"
  # consider 200/202 as fine AND also cases where results[].ok==true
  if [[ "$S2" =~ ^20[0-9]$ || "$S2" == "202" ]]; then
    if jq -e '.results | type=="array" and (map(.ok==true) | any)' >/dev/null 2>&1 <<<"$B2"; then
      INGEST_OK=1; break
    fi
  fi
  if [[ "$ATTEMPT" -lt "$MAX_RETRIES" ]]; then
    echo "   retrying in ${DELAY}s…"; sleep "$DELAY"; DELAY=$((DELAY*2))
  fi
done

# If ingest failed due to unsupported format, fallback to direct install with inline manifest.
if [[ $INGEST_OK -ne 1 ]]; then
  ERR_MSG="$(jq -r '.results[0].error? // empty' <<<"$B2" 2>/dev/null || true)"
  if [[ "$ERR_MSG" == *"No compatible ingest function"* || -n "$MANIFEST_URL" ]]; then
    echo "⚠️  Ingest not compatible (or MANIFEST_URL provided) — falling back to direct install with inline manifest."
    parse_uid "$ENTITY_UID"
    direct_install_with_manifest || exit 1
  fi
fi

# ------------------------------- 3) INSTALL (by UID) -------------------------
echo "→ POST $INSTALL_URL"
PAYLOAD="$(jq -nc --arg id "$ENTITY_UID" --arg target "./" '{id:$id, target:$target}')"
DELAY=2
for ATTEMPT in $(seq 1 3); do
  R3="$(curl_json POST "$INSTALL_URL" "$PAYLOAD")"
  S3="${R3##*$'\n'}"; B3="${R3%$'\n'*}"
  echo "   attempt $ATTEMPT → status: $S3"
  if [[ "$S3" =~ ^20[0-9]$ ]]; then
    echo "✅ Installed/registered:"; echo "$B3" | jq '.' 2>/dev/null || echo "$B3"
    echo "✔ Done."; exit 0
  fi
  if [[ "$ATTEMPT" -lt 3 ]]; then
    echo "   retrying in ${DELAY}s…"; sleep "$DELAY"; DELAY=$((DELAY*2))
  fi
done

# If install by UID still fails, last resort: try direct install once more.
echo "⚠️  Install by UID failed — trying direct install as last resort."
parse_uid "$ENTITY_UID"
direct_install_with_manifest