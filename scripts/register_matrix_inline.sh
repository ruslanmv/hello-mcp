# scripts/register_matrix_inline.sh
body="$(jq -c --arg id "hello-sse-server" --arg target "server" \
         --argfile manifest matrix/hello-server.manifest.json \
         '{id:$id, target:$target, manifest:$manifest}')"

curl -X POST "$HUB_URL/catalog/install" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$body"
