#!/usr/bin/env bash
# scripts/init.sh
# Thin wrapper around scripts/init.py + helpers to serve/register.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="${PYTHON:-python3}"
INIT_PY="${ROOT_DIR}/scripts/init.py"
REG_SCRIPT="${ROOT_DIR}/scripts/register_matrix_url.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/init.sh <command> [args]

Commands (proxied to scripts/init.py):
  init-empty           Initialize an empty index (default shape=items)
  add-url              Add one manifest URL to the index (Form B or A)
  add-entry            Add one (path, base_url) pair to the index (Form C)
  add-inline           Copy a local manifest into ./matrix and add entry
  scaffold-server      Generate a minimal mcp_server manifest (+ add entry)
  scaffold-tool        Generate a minimal tool manifest (+ add entry)
  scaffold-agent       Generate a minimal agent manifest (+ add entry)

Helpers:
  serve [PORT]         Serve repo root via python -m http.server (default: 8001)
  register             Run scripts/register_matrix_url.sh (env-driven)
                       Requires HUB_URL, ADMIN_TOKEN and REMOTE_INDEX_URL.
                       Optional: ENTITY_UID, MANIFEST_URL.

Examples:
  scripts/init.sh init-empty --shape items
  scripts/init.sh add-url --manifest-url https://host/matrix/hello.manifest.json
  scripts/init.sh scaffold-server \
    --base-url "http://127.0.0.1:8001/matrix" \
    --id hello-sse-server --name "Hello World MCP (SSE)" \
    --version 0.1.0 --transport sse \
    --url "http://127.0.0.1:8000/messages/"
  scripts/init.sh serve 8001
  HUB_URL=http://127.0.0.1:7300 ADMIN_TOKEN=... \
  REMOTE_INDEX_URL=http://127.0.0.1:8001/matrix/index.json \
  ENTITY_UID="mcp_server:hello-sse-server@0.1.0" \
  scripts/init.sh register
USAGE
}

ensure_tools() {
  command -v "$PY" >/dev/null || { echo "ERROR: Python not found (set \$PYTHON)"; exit 1; }
}

case "${1:-}" in
  init-empty|add-url|add-entry|add-inline|scaffold-server|scaffold-tool|scaffold-agent)
    ensure_tools
    exec "$PY" "$INIT_PY" "$@"
    ;;
  serve)
    PORT="${2:-8001}"
    echo "▶ Serving repo at http://127.0.0.1:${PORT}/"
    echo "  Tip: your index will be at http://127.0.0.1:${PORT}/matrix/index.json"
    cd "$ROOT_DIR"
    exec "$PY" -m http.server "$PORT"
    ;;
  register)
    [[ -f "$REG_SCRIPT" ]] || { echo "ERROR: $REG_SCRIPT not found"; exit 1; }
    exec "$REG_SCRIPT"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $1"; usage; exit 2
    ;;
esac
