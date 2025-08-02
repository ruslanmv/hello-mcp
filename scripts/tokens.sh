export HUB_URL="http://$HUB_ENDPOINT"
# 0.3 — (Optional) Quick health check
curl -s "$HUB_URL/health" || true