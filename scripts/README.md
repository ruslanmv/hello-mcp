# Matrix-Hub – Quick Developer Guide (Catalog + Ingestion)

This guide shows how to use the **catalog initializer** to produce an ingestable
`matrix/index.json` and how to ingest/register your content in **Matrix-Hub**.

## What you get

- `scripts/init.py` – Python tool that:
  - **Initializes** an index in one of three shapes Matrix-Hub supports:
    - **A)** `{"manifests":[ "...", ...]}`
    - **B)** `{"items":[ {"manifest_url":"..."}, ...]}`
    - **C)** `{"entries":[ {"path":"a.json","base_url":"https://host/matrix/"} ]}`
  - **Adds** entries: `add-url`, `add-entry`, `add-inline`
  - **Scaffolds** manifests: `scaffold-server`, `scaffold-tool`, `scaffold-agent`
- `scripts/init.sh` – Bash wrapper that proxies to `init.py` and provides helpers:
  - Serve index locally, register with a running Hub.
- `scripts/register_matrix_url.sh` – Robust **remote → ingest → install** script.

## Prerequisites

- Python 3.10+ (for `scripts/init.py`)
- `curl`, `jq` (for registration)
- A running Matrix-Hub (`HUB_URL`, e.g., `http://127.0.0.1:7300`) and `ADMIN_TOKEN`
- If you want Hub to auto-register MCP servers to the MCP-Gateway, set in Hub env:
  - `MCP_GATEWAY_URL`, `MCP_GATEWAY_TOKEN`

## Typical workflows

### A) Host manifests yourself (preferred for scale)
1) **Initialize index** (Form **B**: `items` with `manifest_url`):
   ```bash
   scripts/init.py init-empty --shape items
```

2. **Add an MCP server by URL**:

   ```bash
   scripts/init.py add-url \
     --manifest-url "https://your.host/matrix/hello-server.manifest.json"
   ```
3. **Publish** the resulting `matrix/index.json` to a public URL (GitHub raw, S3, CDN).
4. **Register with Hub**:

   ```bash
   HUB_URL=http://127.0.0.1:7300 \
   ADMIN_TOKEN=your-admin-token \
   REMOTE_INDEX_URL="https://your.host/matrix/index.json" \
   ENTITY_UID="mcp_server:hello-sse-server@0.1.0" \
   scripts/register_matrix_url.sh
   ```

### B) Serve local manifests (fully local; Form **C**: `entries`)

1. **Initialize index**:

   ```bash
   scripts/init.py init-empty --shape entries
   ```
2. **Scaffold a server/tool/agent** (creates JSONs into `./matrix` and adds entries):

   ```bash
   scripts/init.py scaffold-server \
     --base-url "http://127.0.0.1:8001/matrix" \
     --id hello-sse-server --name "Hello World MCP (SSE)" \
     --version 0.1.0 --transport sse \
     --url "http://127.0.0.1:8000/messages/" \
     --summary "Minimal SSE server exposing one 'hello' tool."
   ```
3. **Serve** the repo root so Hub can fetch `/matrix/index.json`:

   ```bash
   python3 -m http.server 8001
   ```
4. **Register with Hub**:

   ```bash
   HUB_URL=http://127.0.0.1:7300 \
   ADMIN_TOKEN=your-admin-token \
   REMOTE_INDEX_URL="http://127.0.0.1:8001/matrix/index.json" \
   ENTITY_UID="mcp_server:hello-sse-server@0.1.0" \
   scripts/register_matrix_url.sh
   ```

## Shortcuts via `init.sh`

For convenience, you can use Bash wrappers:

```bash
# Initialize an empty index (items by default)
scripts/init.sh init-empty

# Add a manifest URL
scripts/init.sh add-url --manifest-url "https://host/matrix/hello.manifest.json"

# Scaffold a server
scripts/init.sh scaffold-server \
  --base-url "http://127.0.0.1:8001/matrix" \
  --id hello-sse-server --name "Hello World MCP (SSE)" \
  --version 0.1.0 --transport sse \
  --url "http://127.0.0.1:8000/messages/"

# Serve the repo so Hub can fetch /matrix/index.json
scripts/init.sh serve 8001

# Register with Hub
HUB_URL=http://127.0.0.1:7300 \
ADMIN_TOKEN=your-admin-token \
REMOTE_INDEX_URL="http://127.0.0.1:8001/matrix/index.json" \
ENTITY_UID="mcp_server:hello-sse-server@0.1.0" \
scripts/init.sh register
```

## Notes

* For **Docker**: If Hub runs in a container, `127.0.0.1` refers to the container.
  Use `http://host.docker.internal:PORT/` or a reachable LAN hostname.
* Matrix-Hub stores Entities in its **DB** (SQLite by default) on **ingest**; the **index** is just a feed file.
* “Install” step invokes `mcp_registration` to register MCP servers with the MCP-Gateway.

Happy shipping!
