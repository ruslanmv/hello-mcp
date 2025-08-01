# How to register MCP Server in Matrix HUB

## 0) One-time setup

```bash
# 0.1 — Start your Hello SSE server
make install
make start-sse
# It serves on http://127.0.0.1:8000 (adjust to a LAN IP if Hub runs in Docker)

# 0.2 — Export the Hub base URL (must include http://) and your admin token
export HUB_URL='http://127.0.0.1:7300'      # NOT just 0.0.0.0:7300
export ADMIN_TOKEN='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'

# 0.3 — (Optional) Quick health check
curl -s "$HUB_URL/health" || true
```

> If Hub/Gateway are containerized, replace `127.0.0.1` with a **LAN-reachable host/IP**.

---

## 1) Complete manifests (SSE)

Save this **server** manifest as `matrix/hello-server.manifest.json`:

```json
{
  "id": "hello-sse-server",
  "name": "Hello World MCP (SSE)",
  "description": "A minimal MCP server exposing a single 'hello' tool over SSE.",
  "version": "0.1.0",
  "base_url": "http://127.0.0.1:8000/",
  "transport": {
    "type": "sse",
    "events_url": "http://127.0.0.1:8000/sse",
    "invoke_url": "http://127.0.0.1:8000/invoke"
  },
  "capabilities": { "tools": true },
  "tools": [
    {
      "name": "hello",
      "description": "Return a simple greeting.",
      "input_schema": {
        "type": "object",
        "properties": { "name": { "type": "string", "description": "Name to greet" } },
        "required": ["name"],
        "additionalProperties": false
      },
      "output_schema": {
        "type": "object",
        "properties": { "text": { "type": "string", "description": "Greeting text" } },
        "required": ["text"],
        "additionalProperties": false
      },
      "idempotent": true
    }
  ]
}
```

> If Hub/Gateway can’t reach `127.0.0.1`, change those URLs to your host’s **LAN IP** (e.g., `http://192.168.1.50:8000/`).

---

## 2) Register in **Matrix Hub** via HTTP

The **install** endpoint needs:

* `id`: a stable ID for the server in the Hub
* `target`: what you’re installing (use `"server"` here)
* `manifest_url` **or** `manifest`

### 2A) **By URL** (recommended)

Publish your JSON at a reachable URL. You already have one on GitHub:

```
https://raw.githubusercontent.com/ruslanmv/hello-mcp/refs/heads/main/matrix/hello-server.manifest.json
```

Then:

```bash
curl -X POST "$HUB_URL/catalog/install" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id":"hello-sse-server","target":"server","manifest_url":"https://raw.githubusercontent.com/ruslanmv/hello-mcp/refs/heads/main/matrix/hello-server.manifest.json"}'
```

### 2B) **Inline** (embed JSON file into the request)

Make sure you run these from the **project root**, where the file actually exists (`matrix/hello-server.manifest.json`). This constructs the wrapper body the API expects and inlines your JSON:

```bash
body="$(jq -c --arg id "hello-sse-server" --arg target "server" \
         --argfile manifest matrix/hello-server.manifest.json \
         '{id:$id, target:$target, manifest:$manifest}')"

curl -X POST "$HUB_URL/catalog/install" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$body"
```

> **Why your earlier call failed**
>
> * You posted only `{"manifest_url": "..."} → missing `id`and`target\`.
> * In the other script, curl couldn’t find `hello-server.manifest.json`, so the body was empty.

### 2C) Verify in Hub

```bash
curl -s "$HUB_URL/catalog/search?q=hello" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

You should see the server/tool returned.

---

## 3) (Optional) Register in the **Gateway** admin API

Your logs show you’re also hitting the Gateway at port **4444**. If your setup keeps a separate admin list of upstream servers, upsert there too.

Two common shapes exist; try **A**, and if the route isn’t found, try **B**.

**A) `/servers` upsert with wrapper body**

```bash
curl -X POST "http://127.0.0.1:4444/servers" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d @"<(jq -c --arg id "hello-sse-server" --arg target "server" \
             --argfile manifest matrix/hello-server.manifest.json \
             '{id:$id, target:$target, manifest:$manifest}')"
```

**B) `/admin/servers` or `/servers/upsert`** (alternate paths)

```bash
# Try one of these if A returns 404:
for p in /admin/servers /servers/upsert; do
  echo "Trying $p"
  curl -s -X POST "http://127.0.0.1:4444$p" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"<(jq -c --arg id "hello-sse-server" --arg target "server" \
               --argfile manifest matrix/hello-server.manifest.json \
               '{id:$id, target:$target, manifest:$manifest}')"
done
```

**List registered servers**

```bash
curl -s "http://127.0.0.1:4444/servers" -H "Authorization: Bearer $ADMIN_TOKEN"
```

---

## 4) Register via the **Python SDK** (same token)

```python
# register_hello_sdk.py
import json
from matrix_sdk.bulk.gateway_client import GatewayAdminClient

HUB_URL = "http://127.0.0.1:7300"
TOKEN = "REPLACE_WITH_YOUR_ADMIN_TOKEN"

with open("matrix/hello-server.manifest.json", "r", encoding="utf-8") as f:
    manifest = json.load(f)

# If your SDK client expects the same wrapper, pass plain manifest to upsert_server;
# the client will add id/target as needed. If it does not, wrap it yourself:
wrapped = {"id": manifest["id"], "target": "server", "manifest": manifest}

gw = GatewayAdminClient(base_url=HUB_URL, token=TOKEN)
result = gw.upsert_server(wrapped)   # or gw.upsert_server(manifest) if your SDK handles wrapping
print("Registered server:", getattr(result, "id", "unknown"))
```

Run:

```bash
python register_hello_sdk.py
```

---

## 5) Quick end-to-end check

```bash
# From Hub
curl -s "$HUB_URL/catalog/search?q=hello" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# From Gateway
curl -s "http://127.0.0.1:4444/servers" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

---

## 6) Common gotchas

* **No `http://` in HUB URL** → always include the scheme: `export HUB_URL='http://127.0.0.1:7300'`.
* **Missing wrapper fields** → the install API requires `id` and `target` alongside `manifest` **or** `manifest_url`.
* **Wrong working directory** → if curl can’t find `hello-server.manifest.json`, it sends an empty POST and you get `{"error":"ValidationError","detail":[{"type":"missing","loc":["body"]...}]}`.
* **127.0.0.1 not reachable from containers** → switch the manifest `base_url`, `events_url`, and `invoke_url` to a **LAN IP/hostname**.
* **Expired token** → re-run your token mint step and export the new value.

---

If you paste back the exact response you get from `POST $HUB_URL/catalog/install` after using the **wrapper body**, I can validate the next step (ingest/probe) with the precise payloads your Hub expects.
