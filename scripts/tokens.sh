export ADMIN_TOKEN='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFkbWluIiwiZXhwIjoxNzU0MDk2NjAyfQ.TWbg2mu7-Icjf-yGzvU3LHa6fpYCYDIiePid9cKsvoM'
export HUB_ENDPOINT='0.0.0.0:7300'
export HUB_URL="http://$HUB_ENDPOINT"
# 0.3 — (Optional) Quick health check
curl -s "$HUB_URL/health" || true