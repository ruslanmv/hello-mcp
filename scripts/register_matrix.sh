#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# scripts/register_matrix_url.sh
#
# Register MCP servers into Matrix-Hub via:
#   1) POST /remotes      (register index URL)
#   2) POST /ingest       (pull manifests → upsert into DB)
#   3) POST /catalog/install (install/registration with MCP-Gateway)
#
# Local defaults:
#   - HUB_URL            → http://127.0.0.1:7300
#   - You should serve your matrix/ folder, e.g.:
#       python3 -m http.server 8001   (and then use http://127.0.0.1:8001/matrix/index.json)
#
# Usage examples:
#   # Register using an index URL directly
#   ADMIN_TOKEN=xyz scripts/register_matrix_url.sh \
#     --index "https://raw.githubusercontent.com/user/repo/ref/matrix/index.json"
#
#   # Register using only a manifest URL (we derive …/matrix/index.json)
#   ADMIN_TOKEN=xyz scripts/register_matrix_url.sh \
#     --manifest "https://raw.githubusercontent.com/user/repo/ref/matrix/hello-server.manifest.json" \
#     --entity "mcp_server:hello-sse-server@0.1.0"
#
#   # Production (Matrix Hub on www.matrixhub.io)
#   HUB_URL=https://www.matrixhub.io ADMIN_TOKEN=xyz scripts/register_matrix_url.sh \
#     --index "https://cdn.your.org/matrix/index.json" \
#     --entity "mcp_server:your-server@1.2.3"
#
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ------------------------------- Defaults ------------------------------------
HUB_BASE="${HUB_URL:-${HUB_ENDPOINT:-http://127.0.0.1:7300}}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
REMOTE_INDEX_URL=""     # can be passed via --index
MANIFEST_URL=""         # can be passed via --manifest
ENTITY_UID="${ENTITY_UID:-}"  # optional override; e.g. mcp_server:hello@0.1.0

# ------------------------------- Args ----------------------------------------
usage() {
  cat <<'EOF'
Register content into Matrix-Hub (remote → ingest → install).

Usage:
  scripts/register_matrix_url.sh [--index <INDEX_URL>] [--manifest <MANIFEST_URL>] [--entity <UID>]

Flags:
  --index     Absolute URL to matrix/index.json (remote catalog)
  --manifest  Absolute URL to a single manifest (we derive …/matrix/index.json if --index is omitted)
  --entity    UID for install step (type:id@version), e.g., mcp_server:hello-sse-server@0.1.0

Env:
  HUB_URL      Matrix-Hub base URL (default: http://127.0.0.1:7300)
  ADMIN_TOKEN  Admin token for Hub API (required)
  (Optional) You can also set:
    - MANIFEST_URL, REMOTE_INDEX_URL, ENTITY_UID instead of passing flags.

Examples:
  ADMIN_TOKEN=xyz scripts/register_matrix_url.sh \
    --index "https://raw.githubusercontent.com/user/repo/ref/matrix/index.json"

  ADMIN_TOKEN=xyz scripts/register_matrix_url.sh \
    --manifest "https://raw.githubusercontent.com/user/repo/ref/matrix/hello-server.manifest.json" \
    --entity "mcp_server:hello-sse-server@0.1.0"

  HUB_URL=https://www.matrixhub.io ADMIN_TOKEN=xyz scripts/register_matrix_url.sh \
    --index "https://cdn.your.org/matrix/index.json" \
    --entity "mcp_server:your-server@1.2.3"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index)    REMOTE_INDEX_URL="$2"; shift 2 ;;
    --manifest) MANIFEST_URL="$2"; shift 2 ;;
    --entity)   ENTITY_UID="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

# If index not provided, derive from manifest if possible
if [[ -z "$REMOTE_INDEX_URL" && -n "$MANIFEST_URL" ]]; then
  # Expect manifest URLs of the form …/matrix/<something>.manifest.json
  base="${MANIFEST_URL%/matrix/*}"
  REMOTE_INDEX_URL="${base}/matrix/index.json"
fi

# Final sanity checks
if [[ -z "$REMOTE_INDEX_URL" && -z "$MANIFEST_URL" ]]; then
  echo "ERROR: provide --index <INDEX_URL> or --manifest <MANIFEST_URL>" >&2
  usage; exit 1
fi

command -v jq >/dev/null   || { echo "ERROR: jq is required"; exit 1; }
command -v curl >/dev/null || { echo "ERROR: curl is required"; exit 1; }
[[ -n "$ADMIN_TOKEN" ]] || { echo "ERROR: set ADMIN_TOKEN"; exit 1; }

# ------------------------------ Normalize URL --------------------------------
norm() { printf "%s" "$1" | tr -d '\r' | sed 's:/*$::'; }

HUB_BASE="$(norm "$HUB_BASE")"
[[ "$HUB_BASE" =~ ^https?:// ]] || HUB_BASE="http://${HUB_BASE}"

# If using 0.0.0.0, prefer 127.0.0.1
if [[ "$HUB_BASE" =~ ^https?://0\.0\.0\.0:([0-9]+)$ ]]; then
  PORT="${BASH_REMATCH[1]}"
  echo "⚠️  HUB_URL=0.0.0.0; switching to http://127.0.0.1:${PORT}"
  HUB_BASE="http://127.0.0.1:${PORT}"
fi

# Try root and /api, pick the one whose /health responds
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

# -------- Detect route style: /remotes vs /catalog/remotes -------------------
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
  echo "❌ Could not detect catalog route style on $API_BASE."; exit 1;
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
[[ -n "$REMOTE_INDEX_URL" ]] && echo "→ Index:    $REMOTE_INDEX_URL"
[[ -n "$MANIFEST_URL"    ]] && echo "→ Manifest: $MANIFEST_URL"
[[ -n "$ENTITY_UID"      ]] && echo "→ Entity:   $ENTITY_UID"

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

# ----------------------- Fallback helpers (direct install) -------------------
parse_uid() {
  local uid_str="$1"
  TYPE="${uid_str%%:*}"
  local rest="${uid_str#*:}"
  ID="${rest%@*}"
  VERSION="${uid_str##*@}"
}

fetch_json() { curl -fsSL "$1"; }

discover_manifest_from_index() {
  local IDX_JSON
  IDX_JSON="$(fetch_json "$REMOTE_INDEX_URL")" || {
    echo "❌ Failed to fetch index: $REMOTE_INDEX_URL"; return 1; }
  # Try "entities" first (older format), else try "items" (manifest_url list)
  local ENTRY
  ENTRY="$(jq -c --arg t "$TYPE" --arg id "$ID" --arg v "$VERSION" \
      '.entities[]? | select(.type==$t and .id==$id and .version==$v)' \
      <<<"$IDX_JSON")" || true
  if [[ -z "$ENTRY" || "$ENTRY" == "null" ]]; then
    # If using "items": just match by manifest_url domain or try to pull anyway
    # (We can't map UID -> URL without opening every manifest; so expect entities format here)
    echo "❌ Could not find ${ENTITY_UID} in index.json (entities[] expected)"; return 1
  fi
  DISCOVERED_MANIFEST="$(jq -c '.manifest // empty' <<<"$ENTRY")"
  DISCOVERED_MANIFEST_URL="$(jq -r '.manifest_url // empty' <<<"$ENTRY")"
  if [[ -n "$DISCOVERED_MANIFEST" ]]; then return 0; fi
  if [[ -n "$DISCOVERED_MANIFEST_URL" ]]; then
    local MJSON
    MJSON="$(fetch_json "$DISCOVERED_MANIFEST_URL")" || {
      echo "❌ Failed to fetch manifest_url: $DISCOVERED_MANIFEST_URL"; return 1; }
    DISCOVERED_MANIFEST="$(jq -c '.' <<<"$MJSON")"; return 0
  fi
  echo "❌ Entry has neither manifest nor manifest_url"; return 1
}

direct_install_with_manifest() {
  local MANIFEST_JSON=""
  if [[ -n "$MANIFEST_URL" ]]; then
    echo "→ Fetching manifest override: $MANIFEST_URL"
    MANIFEST_JSON="$(fetch_json "$MANIFEST_URL")" || {
      echo "❌ Could not fetch MANIFEST_URL: $MANIFEST_URL"; return 1; }
  else
    [[ -n "$ENTITY_UID" ]] || { echo "❌ ENTITY_UID is required for discovery"; return 1; }
    echo "→ Discovering manifest from index.json"
    DISCOVERED_MANIFEST=""; DISCOVERED_MANIFEST_URL=""
    discover_manifest_from_index || return 1
    MANIFEST_JSON="$DISCOVERED_MANIFEST"
    [[ -n "$MANIFEST_JSON" ]] || { echo "❌ No manifest found"; return 1; }
  fi
  echo "→ POST $INSTALL_URL (direct install with inline manifest)"
  local PAYLOAD R S B
  PAYLOAD="$(jq -nc --argjson m "$MANIFEST_JSON" '{target:"./", manifest:$m}')"
  R="$(curl -sS -w $'\n%{http_code}' -X POST "$INSTALL_URL" \
        "${AUTH_HDR[@]}" "${JSON_HDR[@]}" -d "$PAYLOAD")"
  S="${R##*$'\n'}"; B="${R%$'\n'*}"
  echo "   status: $S"
  if [[ "$S" =~ ^20[0-9]$ ]]; then
    echo "✅ Installed/registered (direct):"; echo "$B" | jq '.' 2>/dev/null || echo "$B"
    echo "✔ Done."; exit 0
  else
    echo "❌ Direct install failed:"; echo "$B" | jq '.' 2>/dev/null || echo "$B"
    return 1
  fi
}

# -------------------------------- 1) REMOTE ----------------------------------
if [[ -n "$REMOTE_INDEX_URL" ]]; then
  echo "→ POST $REMOTES_URL"
  R1="$(curl_json POST "$REMOTES_URL" "$(jq -nc --arg url "$REMOTE_INDEX_URL" '{url:$url}')" )"
  S1="${R1##*$'\n'}"; B1="${R1%$'\n'*}"
  echo "   status: $S1"
  if [[ "$S1" =~ ^20[0-9]$ || "$S1" == "409" || "$S1" == "412" ]]; then
    echo "$B1" | jq '.' 2>/dev/null || echo "$B1"
  else
    echo "❌ Failed to add remote. Response:"; echo "$B1" | jq '.' 2>/dev/null || echo "$B1"; exit 1
  fi
else
  echo "ℹ️  REMOTE_INDEX_URL not set; skipping /remotes registration."
fi

# -------------------------------- 2) INGEST ----------------------------------
if [[ -n "$REMOTE_INDEX_URL" ]]; then
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
    if [[ "$S2" =~ ^20[0-9]$ || "$S2" == "202" ]]; then
      if jq -e '.results | type=="array" and (map(.ok==true) | any)' >/dev/null 2>&1 <<<"$B2"; then
        INGEST_OK=1; break
      fi
    fi
    if [[ "$ATTEMPT" -lt "$MAX_RETRIES" ]]; then
      echo "   retrying in ${DELAY}s…"; sleep "$DELAY"; DELAY=$((DELAY*2))
    fi
  done
else
  INGEST_OK=0
  echo "ℹ️  REMOTE_INDEX_URL not set; will try direct install if ENTITY/MANIFEST is provided."
fi

# Fallback to direct install with inline manifest if needed.
if [[ $INGEST_OK -ne 1 ]]; then
  echo "⚠️  Ingest may not be compatible — falling back to direct install (if possible)."
  if [[ -z "$ENTITY_UID" && -z "$MANIFEST_URL" ]]; then
    echo "❌ Need --entity <UID> or --manifest <URL> for direct install fallback."; exit 1;
  fi
  [[ -n "$ENTITY_UID" ]] && parse_uid "$ENTITY_UID"
  direct_install_with_manifest || exit 1
fi

# -------------------------------- 3) INSTALL ---------------------------------
if [[ -n "$ENTITY_UID" ]]; then
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
  echo "⚠️  Install by UID failed — trying direct install as last resort."
  parse_uid "$ENTITY_UID"
  direct_install_with_manifest
else
  echo "ℹ️  ENTITY not provided; remote + ingest completed."
fi
