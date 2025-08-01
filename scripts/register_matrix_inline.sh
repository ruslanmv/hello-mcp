# Option B: manifest by URL
curl -X POST "http://$HUB_ENDPOINT/catalog/install" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"manifest_url":"https://raw.githubusercontent.com/ruslanmv/hello-mcp/refs/heads/main/matrix/hello-server.manifest.json"}'
