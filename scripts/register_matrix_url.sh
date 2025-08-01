curl -X POST "$HUB_URL/catalog/install" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id":"hello-sse-server","target":"server","manifest_url":"https://raw.githubusercontent.com/ruslanmv/hello-mcp/refs/heads/main/matrix/hello-server.manifest.json"}'
