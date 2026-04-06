#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${1:?Usage: $0 <state-file> <prefix>}"
PREFIX="${2:-}"

GRAFANA_URL=$(jq -r ".${PREFIX}grafana_url.value" "$STATE_FILE")
GRAFANA_PASS=$(jq -r ".${PREFIX}grafana_admin_password.value" "$STATE_FILE")
for i in $(seq 1 60); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "admin:${GRAFANA_PASS}" "${GRAFANA_URL}/api/org" --insecure || true)
  if [ "$STATUS" = "200" ]; then
    echo "OK:   Grafana API responded 200"
    break
  fi
  echo "  attempt $i: status=$STATUS, retrying in 10s..."
  sleep 10
done
[ "$STATUS" = "200" ] || { echo "FAIL: Grafana API did not respond 200 after 60 attempts"; exit 1; }

echo "Health check: Grafana dashboards"
DASH_COUNT=$(curl -s --insecure -u "admin:${GRAFANA_PASS}" "${GRAFANA_URL}/api/search?type=dash-db" | jq 'length')
if [ "$DASH_COUNT" -gt 0 ] 2>/dev/null; then
  echo "OK:   $DASH_COUNT dashboard(s) found"
else
  echo "FAIL: no dashboards found"
  exit 1
fi

echo "Health check: Grafana -> Prometheus query"
QUERY_STATUS=$(curl -s --insecure -u "admin:${GRAFANA_PASS}" "${GRAFANA_URL}/api/datasources/proxy/uid/prometheus/api/v1/query?query=up" | jq -r '.status // empty')
if [ "$QUERY_STATUS" = "success" ]; then
  echo "OK:   Prometheus query via Grafana returned success"
else
  echo "FAIL: Prometheus query via Grafana returned: $QUERY_STATUS"
  exit 1
fi

echo "Health check: node-exporter DaemonSet"
DS_DESIRED=$(kubectl get daemonset -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter -o jsonpath='{.items[0].status.desiredNumberScheduled}')
DS_READY=$(kubectl get daemonset -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter -o jsonpath='{.items[0].status.numberReady}')
echo "  desired=$DS_DESIRED ready=$DS_READY"
if [ "$DS_DESIRED" != "$DS_READY" ] || [ "$DS_DESIRED" -lt 1 ]; then
  echo "FAIL: node-exporter DaemonSet desired ($DS_DESIRED) != ready ($DS_READY)"
  exit 1
fi
echo "OK:   node-exporter DaemonSet $DS_READY/$DS_DESIRED pods ready"
echo "Health check: all monitoring health checks passed"
