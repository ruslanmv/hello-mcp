export HUB_URL="http://$HUB_ENDPOINT"
# Optional: quick sanity checks
echo "$HUB_URL"
curl -s "$HUB_URL/health" || true