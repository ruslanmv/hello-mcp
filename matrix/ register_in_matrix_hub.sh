curl -X POST "https://HUB_URL/catalog/install" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"manifest_url":"http://YOUR-HOST/hello-server.manifest.json"}'
