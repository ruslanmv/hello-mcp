#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Build bundle ZIP for hello-mcp (or any MCP) with:
#   - runner.json
#   - requirements.txt (exported from Poetry)
#   - agents/ ... (server code; excludes venv, git, caches)
#
# Output:
#   dist/<NAME>-<VERSION>.zip
#   dist/<NAME>-<VERSION>.zip.sha256
#   dist/<NAME>-<VERSION>.runner.json   (copied, for convenience)
#
# Usage:
#   scripts/build_bundle.sh [version]
#
# Env (optional):
#   NAME=hello-mcp
#   RELEASE_BASE_URL="https://github.com/<user>/<repo>/releases/download/v<VER>"
#   ENTRY="agents/hello_world/server_sse.py"
#   TRANSPORT="sse"  # or "stdio"
#
# Example:
#   RELEASE_BASE_URL="https://github.com/ruslanmv/hello-mcp/releases/download/v<VER>" \
#   scripts/build_bundle.sh 0.1.0
#
# After upload to GitHub Releases, /catalog/install plan can use:
# {
#   "artifacts": [
#     {"url": "<RELEASE_BASE_URL>/<NAME>-<VER>.zip", "path": "bundle.zip", "sha256": "<sha256>"}
#   ],
#   "files": [
#     {"path": "runner.json", "content": <runner.json as minified JSON string>}
#   ],
#   "results": []
# }
# ------------------------------------------------------------------------------

set -Eeuo pipefail

say(){ printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m!!\033[0m %s\n" "$*" >&2; }
die(){ printf "\033[1;31m✖\033[0m %s\n" "$*" >&2; exit 1; }

# --- locate repo root (directory containing this script is scripts/) ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

# --- prerequisites ------------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || die "Missing required tool: $1"; }

need zip
# sha256: Linux has sha256sum; macOS has shasum -a 256
if command -v sha256sum >/dev/null 2>&1; then
  SHA256="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  SHA256="shasum -a 256"
else
  die "Missing sha256 tool: install 'sha256sum' or use 'shasum' (macOS)"
fi

if command -v poetry >/dev/null 2>&1; then
  HAVE_POETRY=1
else
  HAVE_POETRY=0
  warn "Poetry not found; will try to re-use existing requirements.txt"
fi

# --- config & version detection ----------------------------------------------
NAME="${NAME:-hello-mcp}"

# Version precedence: arg > POETRY > fallback
VER="${1:-}"
if [[ -z "$VER" && "$HAVE_POETRY" == "1" ]]; then
  # 'poetry version -s' prints version only; 'poetry version' prints 'name ver'
  VER="$(poetry version -s 2>/dev/null || true)"
fi
VER="${VER:-0.0.0+dev}"

ENTRY_DEFAULT="agents/hello_world/server_sse.py"
ENTRY="${ENTRY:-$ENTRY_DEFAULT}"
TRANSPORT="${TRANSPORT:-sse}"

DIST_DIR="$ROOT/dist"
BUILD_DIR="$ROOT/.build/bundle"
BUNDLE_NAME="${NAME}-${VER}.zip"
BUNDLE_PATH="$DIST_DIR/$BUNDLE_NAME"
RUNNER_JSON="$ROOT/runner.json"
RUNNER_OUT="$DIST_DIR/${NAME}-${VER}.runner.json"

mkdir -p "$DIST_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

say "Building bundle"
say "  NAME      : $NAME"
say "  VERSION   : $VER"
say "  ENTRY     : $ENTRY"
say "  TRANSPORT : $TRANSPORT"
say "  DIST      : $BUNDLE_PATH"

# --- export requirements.txt from Poetry (preferred) -------------------------
if [[ "$HAVE_POETRY" == "1" ]]; then
  say "Exporting requirements.txt from Poetry..."
  poetry export -f requirements.txt --without-hashes -o "$BUILD_DIR/requirements.txt"
else
  if [[ -f "$ROOT/requirements.txt" ]]; then
    say "Using existing requirements.txt"
    cp -f "$ROOT/requirements.txt" "$BUILD_DIR/requirements.txt"
  else
    warn "No Poetry and no requirements.txt found; creating minimal placeholder"
    echo "# (intentionally empty)" > "$BUILD_DIR/requirements.txt"
  fi
fi

# --- ensure runner.json (generate if missing) --------------------------------
make_runner_json() {
  # Create a sensible default runner.json; PYTHONPATH: "." helps intra-repo imports
  cat > "$RUNNER_JSON" <<JSON
{
  "schema_version": 1,
  "type": "python",
  "entry": "$ENTRY",
  "transport": "$TRANSPORT",
  "python": {
    "venv": ".venv",
    "requirements": ["-r", "requirements.txt"]
  },
  "env": {
    "PYTHONPATH": "."
  }
}
JSON
}

if [[ ! -f "$RUNNER_JSON" ]]; then
  warn "runner.json not found; generating a default one → $RUNNER_JSON"
  make_runner_json
fi

# Validate entry referenced by runner.json exists
if ! jq -e .entry "$RUNNER_JSON" >/dev/null 2>&1; then
  warn "runner.json not valid JSON or missing 'entry'; regenerating"
  make_runner_json
fi
RUNNER_ENTRY="$(jq -r '.entry' "$RUNNER_JSON" 2>/dev/null || echo "$ENTRY")"
if [[ ! -f "$RUNNER_ENTRY" ]]; then
  warn "runner.entry '$RUNNER_ENTRY' does not exist. Using default '$ENTRY'."
  RUNNER_ENTRY="$ENTRY"
fi

# Copy runner.json to build dir (later also to dist/ as convenience copy)
cp -f "$RUNNER_JSON" "$BUILD_DIR/runner.json"

# --- stage files for zip ------------------------------------------------------
say "Staging files…"
# Include server code; safest is to include whole agents/ (minus junk)
rsync -a --delete \
  --exclude ".git/" \
  --exclude ".venv/" \
  --exclude "__pycache__/" \
  --exclude "*.pyc" \
  --exclude ".mypy_cache/" \
  --exclude ".pytest_cache/" \
  "agents/" "$BUILD_DIR/agents/" 2>/dev/null || {
    warn "No 'agents/' directory found. If your server lives elsewhere, adjust ENTRY and staging."
  }

# Copy requirements & runner.json already placed
# (Optionally copy a minimal README)
if [[ -f "README.md" ]]; then
  cp -f "README.md" "$BUILD_DIR/README.md"
fi

# --- create ZIP ---------------------------------------------------------------
say "Zipping…"
cd "$BUILD_DIR"
# zip relative contents only
zip -qr "$BUNDLE_PATH" \
  "runner.json" \
  "requirements.txt" \
  "agents" 2>/dev/null || true

# As a fallback (if 'agents' didn't exist), ensure at least runner+reqs are zipped
if [[ ! -s "$BUNDLE_PATH" ]]; then
  zip -q "$BUNDLE_PATH" "runner.json" "requirements.txt"
fi
cd "$ROOT"

# --- compute SHA256 -----------------------------------------------------------
say "Computing SHA-256…"
SHA_LINE="$($SHA256 "$BUNDLE_PATH")"
SHA_HEX="$(echo "$SHA_LINE" | awk '{print $1}')"
echo "$SHA_HEX  $(basename "$BUNDLE_PATH")" > "${BUNDLE_PATH}.sha256"
say "  SHA256: $SHA_HEX"

# Copy runner.json next to the bundle for convenience (Hub plan snippet)
cp -f "$RUNNER_JSON" "$RUNNER_OUT"

# --- print helpful Hub plan snippet ------------------------------------------
# RELEASE_BASE_URL may contain <VER> placeholder; substitute
RELEASE_BASE_URL="${RELEASE_BASE_URL:-}"
if [[ -n "$RELEASE_BASE_URL" ]]; then
  RELEASE_BASE_URL="${RELEASE_BASE_URL//<VER>/$VER}"
fi
ART_URL="${RELEASE_BASE_URL:+$RELEASE_BASE_URL/}${BUNDLE_NAME}"

say "Bundle ready:"
echo "  • $BUNDLE_PATH"
echo "  • ${BUNDLE_PATH}.sha256"
echo "  • $RUNNER_OUT"

echo
say "Suggested /catalog/install plan (copy-paste into your Hub's plan):"
# Minify runner.json content for embedding
RUNNER_MIN="$(jq -c . "$RUNNER_OUT" 2>/dev/null || cat "$RUNNER_OUT")"

cat <<JSON
{
  "artifacts": [
    {
      "url": "${ART_URL:-<UPLOAD_AND_FILL_RELEASE_URL>}",
      "path": "bundle.zip",
      "sha256": "$SHA_HEX"
    }
  ],
  "files": [
    {
      "path": "runner.json",
      "content": $RUNNER_MIN
    }
  ],
  "results": []
}
JSON

echo
say "Next steps"
echo "  1) Upload: $(basename "$BUNDLE_PATH")  and  $(basename "$BUNDLE_PATH").sha256  to your GitHub Release v$VER"
echo "  2) In Matrix Hub, set your entity's install plan as printed above (URL + sha256)."
echo "  3) Test locally:"
echo "       matrix install mcp_server:hello-sse-server@$VER --alias hello-world-mcp-sse"
echo "       matrix run hello-world-mcp-sse"
