#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# scripts/test_remote_connection.sh
#
# Purpose:
#   Quickly verify that your Matrix-Hub and your remote index/manifest URLs are
#   reachable and compatible BEFORE you attempt /remotes, /ingest, /catalog/install.
#
# What it checks:
#   1) HUB_URL health → picks the correct API base (/ or /api)
#   2) Index URL (if provided or derived) → HTTP status, JSON parseable, recognized shape
#      - Recognized shapes for current Matrix-Hub ingestor:
#          A) {"manifests": ["https://.../a.yaml", ...]}
#          B) {"items": [{"manifest_url": "https://.../a.yaml"}, ...]}
#          C) {"entries": [{"path":"a.yaml","base_url":"https://host/matrix/"}]}
#      - Also detects {"entities":[...]} and warns that ingest may not support it
#   3) Manifest URL (if provided or discovered) → HTTP status, minimal keys
#
# Usage:
#   scripts/test_remote_connection.sh [--index <INDEX_URL>] [--manifest <MANIFEST_URL>]
#
# Env (optional):
#   HUB_URL (default: http://127.0.0.1:7300)
#
# Examples:
#   scripts/test_remote_connection.sh \
#     --index "http://127.0.0.1:8001/matrix/index.json"
#
#   scripts/test_remote_connection.sh \
#     --manifest "http://127.0.0.1:8001/matrix/hello-server.manifest.json"
#
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------- Defaults / Args ---------------------------------
HUB_BASE="${HUB_URL:-http://127.0.0.1:7300}"
REMOTE_INDEX_URL=""
MANIFEST_URL=""

usage() {
  cat <<'EOF'
Check Matrix-Hub health and remote index/manifest URLs.

Usage:
  scripts/test_remote_connection.sh [--index <INDEX_URL>] [--manifest <MANIFEST_URL>]

If --index is omitted but --manifest is provided, this script derives:
  INDEX_URL = <manifest_url_before_/matrix/>/matrix/index.json

Examples:
  scripts/test_remote_connection.sh \
    --index "http://127.0.0.1:8001/matrix/index.json"

  scripts/test_remote_connection.sh \
    --manifest "http://127.0.0.1:8001/matrix/hello-server.manifest.json"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index)    REMOTE_INDEX_URL="$2"; shift 2 ;;
    --manifest) MANIFEST_URL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

# Derive index from manifest if only manifest was provided
if [[ -z "$REMOTE_INDEX_URL" && -n "$MANIFEST_URL" ]]; then
  base="${MANIFEST_URL%/matrix/*}"
  REMOTE_INDEX_URL="${base}/matrix/index.json"
fi

command -v jq  >/dev/null || { echo "ERROR: jq is required"; exit 1; }
command -v curl >/dev/null || { echo "ERROR: curl is required"; exit 1; }

# ------------------------------ Helpers --------------------------------------
norm() { printf "%s" "$1" | tr -d '\r' | sed 's:/*$::'; }

http_status() {
  # Usage: http_status <URL>
  curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "$1" || true
}

fetch_json() {
  # Prints body on stdout; returns nonzero on error
  curl -fsSL --max-time 10 "$1"
}

# Build URL from entries (Form C) path + base_url
join_url() {
  local base="$1" path="$2"
  # Ensure single slash
  echo "${base%/}/${path#/}"
}

# ------------------------------ 1) Hub health --------------------------------
HUB_BASE="$(norm "$HUB_BASE")"
[[ "$HUB_BASE" =~ ^https?:// ]] || HUB_BASE="http://${HUB_BASE}"

if [[ "$HUB_BASE" =~ ^https?://0\.0\.0\.0:([0-9]+)$ ]]; then
  PORT="${BASH_REMATCH[1]}"
  echo "⚠️  HUB_URL=0.0.0.0; switching to http://127.0.0.1:${PORT}"
  HUB_BASE="http://127.0.0.1:${PORT}"
fi

candidates=()
strip_api="$(echo "$HUB_BASE" | sed 's:/api$::')"
add_api="${strip_api}/api"
for c in "$HUB_BASE" "$strip_api" "$add_api"; do
  c="$(norm "$c")"
  [[ " ${candidates[*]} " == *" $c "* ]] || candidates+=("$c")
done

API_BASE=""
for TRY in "${candidates[@]}"; do
  code="$(http_status "${TRY}/health")"
  echo "→ Probing ${TRY}/health → ${code}"
  if [[ "$code" =~ ^(200|204)$ ]]; then API_BASE="$TRY"; break; fi
done

if [[ -z "$API_BASE" ]]; then
  echo "❌ Matrix-Hub health is not responding on candidates:"
  printf '   - %s\n' "${candidates[@]}"
  echo "   Check that Matrix-Hub is running and reachable."
  exit 1
fi

echo "✅ Hub healthy at: $API_BASE"

# ------------------------------ 2) Index URL ---------------------------------
if [[ -n "$REMOTE_INDEX_URL" ]]; then
  echo "→ Checking index: $REMOTE_INDEX_URL"
  code="$(http_status "$REMOTE_INDEX_URL")"
  echo "   HTTP: $code"
  if [[ "$code" != "200" ]]; then
    echo "❌ Index not reachable (status $code)."
    if [[ "$REMOTE_INDEX_URL" == http://127.0.0.1:8001/* ]]; then
      echo "   Tip: serve your repo root so /matrix is available:"
      echo "        python3 -m http.server 8001"
    fi
    exit 1
  fi

  body="$(fetch_json "$REMOTE_INDEX_URL" || true)"
  if [[ -z "$body" ]]; then
    echo "❌ Failed to download index body."; exit 1
  fi

  if ! echo "$body" | jq '.' >/dev/null 2>&1; then
    echo "❌ Index is not valid JSON."
    echo "   The ingestor expects JSON with one of the keys: manifests | items | entries"
    exit 1
  fi

  has_manifests="$(echo "$body" | jq 'has("manifests")' )"
  has_items="$(echo "$body" | jq 'has("items")' )"
  has_entries="$(echo "$body" | jq 'has("entries")' )"
  has_entities="$(echo "$body" | jq 'has("entities")' )"

  if [[ "$has_manifests" == "true" ]]; then
    echo "✅ Index shape recognized: manifests[] (Form A)"
    count="$(echo "$body" | jq '.manifests | length')"
    echo "   manifests: $count"
    # Test up to 3 URLs
    for u in $(echo "$body" | jq -r '.manifests[]' | head -n 3); do
      c="$(http_status "$u")"
      echo "   - $u → $c"
      if [[ "$c" != "200" ]]; then
        echo "     ⚠️  Not reachable (status $c)"
      fi
    done

  elif [[ "$has_items" == "true" ]]; then
    echo "✅ Index shape recognized: items[].manifest_url (Form B)"
    count="$(echo "$body" | jq '.items | length')"
    echo "   items: $count"
    for u in $(echo "$body" | jq -r '.items[]?.manifest_url // empty' | head -n 3); do
      c="$(http_status "$u")"
      echo "   - $u → $c"
      if [[ "$c" != "200" ]]; then
        echo "     ⚠️  Not reachable (status $c)"
      fi
    done

  elif [[ "$has_entries" == "true" ]]; then
    echo "✅ Index shape recognized: entries[] (Form C)"
    count="$(echo "$body" | jq '.entries | length')"
    echo "   entries: $count"
    # Build URLs and test a few
    mapfile -t lines < <(echo "$body" | jq -r '.entries[] | @base64')
    for row in "${lines[@]:0:3}"; do
      rec="$(echo "$row" | base64 --decode)"
      path="$(echo "$rec" | jq -r '.path // empty')"
      base="$(echo "$rec" | jq -r '.base_url // empty')"
      if [[ -n "$path" && -n "$base" ]]; then
        url="$(join_url "$base" "$path")"
        c="$(http_status "$url")"
        echo "   - $url → $c"
        if [[ "$c" != "200" ]]; then
          echo "     ⚠️  Not reachable (status $c)"
        fi
      else
        echo "   - ⚠️  entry missing path or base_url"
      fi
    done

  elif [[ "$has_entities" == "true" ]]; then
    echo "⚠️  Index has 'entities'[]; current ingestor may not support this shape."
    echo "   Recommended shapes: manifests | items | entries"
    echo "   (You can still do direct install with the manifest inline.)"
    # Try to show first entity & manifest_url if present
    echo "$body" | jq '.entities[0] // {}'
    mu="$(echo "$body" | jq -r '.entities[0].manifest_url // empty')"
    [[ -n "$mu" ]] && echo "   first manifest_url: $mu (status $(http_status "$mu"))"

  else
    echo "❌ Unrecognized index shape."
    echo "   Ensure it has one of: manifests | items | entries"
    exit 1
  fi
else
  echo "ℹ️  No index URL provided (and no manifest to derive one from)."
fi

# ------------------------------ 3) Manifest URL -------------------------------
if [[ -n "$MANIFEST_URL" ]]; then
  echo "→ Checking manifest: $MANIFEST_URL"
  code="$(http_status "$MANIFEST_URL")"
  echo "   HTTP: $code"
  if [[ "$code" != "200" ]]; then
    echo "❌ Manifest not reachable (status $code)."
    if [[ "$MANIFEST_URL" == http://127.0.0.1:8001/* ]]; then
      echo "   Tip: serve your repo root so /matrix is available:"
      echo "        python3 -m http.server 8001"
    fi
    exit 1
  fi

  mbody="$(fetch_json "$MANIFEST_URL" || true)"
  if [[ -z "$mbody" ]]; then
    echo "❌ Failed to download manifest body."; exit 1
  fi

  if ! echo "$mbody" | jq '.' >/dev/null 2>&1; then
    echo "⚠️  Manifest is not valid JSON (could be YAML). Matrix-Hub supports YAML/JSON."
  else
    # Minimal key presence (helpful sanity)
    has_type="$(echo "$mbody"    | jq -r '.type // empty')"
    has_id="$(echo "$mbody"      | jq -r '.id // empty')"
    has_ver="$(echo "$mbody"     | jq -r '.version // empty')"
    if [[ -n "$has_type" && -n "$has_id" && -n "$has_ver" ]]; then
      echo "✅ Manifest has minimal keys: type='$has_type', id='$has_id', version='$has_ver'"
    else
      echo "⚠️  Manifest missing some minimal keys (type/id/version)."
    fi
  fi
else
  echo "ℹ️  No manifest URL provided."
fi

echo "----------------------------------------------------------------------------"
echo "✅ Remote connection checks complete."
echo "   If your index shape is recognized and manifests are reachable (200),"
echo "   Matrix-Hub should be able to /remotes and /ingest successfully."
echo "   For local files (127.0.0.1:8001), ensure you are serving the folder:"
echo "     python3 -m http.server 8001"
