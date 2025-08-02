#!/usr/bin/env bash
set -Eeuo pipefail

# ----------------------------- Configuration ---------------------------------
HUB_BASE="${HUB_URL:-${HUB_ENDPOINT:-}}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
TIMEOUT=45
INTERVAL=3
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)  TIMEOUT="${2:-45}"; shift 2 ;;
    --interval) INTERVAL="${2:-3}"; shift 2 ;;
    -v|--verbose) VERBOSE=1; shift ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

log()  { echo "$@"; }
vlog() { [[ "$VERBOSE" -eq 1 ]] && echo "$@" || true; }
fail() { echo "❌ $*" >&2; exit 1; }
ok()   { echo "✅ $*"; }

command -v curl >/dev/null || fail "Missing dependency: curl"
command -v jq   >/dev/null || fail "Missing dependency: jq"
[[ -n "$HUB_BASE" ]] || fail "Set HUB_URL (e.g. http://127.0.0.1:7300)"

# ------------------------------- Normalize URL -------------------------------
norm() { printf "%s" "$1" | tr -d '\r' | sed 's:/*$::'; }

HUB_BASE="$(norm "$HUB_BASE")"
[[ "$HUB_BASE" =~ ^https?:// ]] || HUB_BASE="http://${HUB_BASE}"

# 0.0.0.0 → 127.0.0.1
if [[ "$HUB_BASE" =~ ^https?://0\.0\.0\.0:([0-9]+)$ ]]; then
  PORT="${BASH_REMATCH[1]}"
  log "⚠️  HUB_URL points to 0.0.0.0; using http://127.0.0.1:${PORT}"
  HUB_BASE="http://127.0.0.1:${PORT}"
fi

# Build candidates regardless of what the user passed
strip_api="$(echo "$HUB_BASE" | sed 's:/api$::')"
add_api="${strip_api}/api"

CANDIDATES=()
for c in "$HUB_BASE" "$strip_api" "$add_api"; do
  c="$(norm "$c")"
  [[ " ${CANDIDATES[*]} " == *" $c "* ]] || CANDIDATES+=("$c")
done

vlog "Candidates: ${CANDIDATES[*]}"

pick_api_base() {
  local API_BASE_LOCAL=""
  for TRY in "${CANDIDATES[@]}"; do
    for P in "/health"; do
      URL="${TRY}${P}"
      CODE="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 3 "$URL" || true)"
      vlog "Probe $URL → $CODE"
      if [[ "$CODE" =~ ^(200|204)$ ]]; then
        API_BASE_LOCAL="$TRY"; break 2
      fi
    done
  done
  echo "$API_BASE_LOCAL"
}

API_BASE="$(pick_api_base)"
[[ -n "$API_BASE" ]] || {
  echo "❌ Could not detect API base under any of:"
  for c in "${CANDIDATES[@]}"; do echo "   - $c"; done
  exit 1
}

log "→ API base: $API_BASE"

# --------------------------- Wait for /health OK -----------------------------
wait_for_health() {
  local DEADLINE=$(( $(date +%s) + TIMEOUT ))
  while :; do
    CODE="$(curl -sS -o /dev/null -w "%{http_code}" "${API_BASE}/health" || true)"
    [[ "$CODE" == "200" || "$CODE" == "204" ]] && return 0
    (( $(date +%s) >= DEADLINE )) && return 1
    vlog "Health not ready (code=$CODE); retrying in ${INTERVAL}s…"
    sleep "$INTERVAL"
  done
}

log "→ Waiting for ${API_BASE}/health (timeout ${TIMEOUT}s)…"
wait_for_health || fail "Health check did not become ready in ${TIMEOUT}s"
ok "Health endpoint is responding"

# Also check DB quickly if supported
RESP="$(curl -sS "${API_BASE}/health?check_db=true" || true)"
if echo "$RESP" | jq -e '.db=="ok"' >/dev/null 2>&1; then
  ok "DB connectivity OK"
else
  vlog "DB check response: $RESP"
fi

# --------------- Discover catalog path style (root vs /catalog) --------------
# Style A: /remotes, /ingest, /catalog/install
# Style B: /catalog/remotes, /catalog/ingest, /catalog/install
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
[[ -n "$STYLE" ]] || fail "Could not detect catalog route style (neither /remotes nor /catalog/remotes responded)"
if [[ "$STYLE" == "root" ]]; then
  REMOTES_PATH="/remotes"
  INGEST_PATH="/ingest"
else
  REMOTES_PATH="/catalog/remotes"
  INGEST_PATH="/catalog/ingest"
fi
INSTALL_PATH="/catalog/install"

ok "Catalog routes are mounted (${STYLE} style)"
vlog "Using paths: ${REMOTES_PATH}, ${INGEST_PATH}, ${INSTALL_PATH}"

# ------------------ If token provided, do authenticated checks ----------------
if [[ -n "$ADMIN_TOKEN" ]]; then
  AUTH=(-H "Authorization: Bearer ${ADMIN_TOKEN}")
  JSON=(-H "Content-Type: application/json")
  CODE="$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${API_BASE}${REMOTES_PATH}" "${AUTH[@]}" "${JSON[@]}" -d '{"url":"about:blank"}' || true)"
  if [[ "$CODE" =~ ^(200|201|409|412|422)$ ]]; then
    ok "Authentication works on ${REMOTES_PATH} (code=$CODE)"
  else
    fail "Authentication failed on ${REMOTES_PATH} (code=$CODE) — check ADMIN_TOKEN"
  fi
else
  log "ℹ️  ADMIN_TOKEN not provided — skipped authenticated checks."
fi

ok "Hub is alive and ready for ingest/install."
