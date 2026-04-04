#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${1:?Usage: $0 <state-file> <prefix>}"
PREFIX="${2:-}"

echo "Health check: API server connectivity"
kubectl cluster-info

echo "Health check: waiting for nodes to be Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=300s

NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
echo "  $NODE_COUNT node(s) ready"
[ "$NODE_COUNT" -ge 1 ] || { echo "FAIL: no nodes found"; exit 1; }

echo "Health check: node count matches expected pool sizes"
EXPECTED=0
for pool_key in worker_ops_pool_id worker_cpu_pool_id worker_gpu_pool_id; do
  POOL_ID=$(jq -r ".${PREFIX}${pool_key}.value // empty" "$STATE_FILE")
  if [ -n "$POOL_ID" ] && [ "$POOL_ID" != "null" ]; then
    SIZE=$(oci ce node-pool get --node-pool-id "$POOL_ID" --query 'data."node-config-details".size' --raw-output 2>/dev/null || echo "0")
    echo "  $pool_key: size=$SIZE"
    EXPECTED=$((EXPECTED + SIZE))
  fi
done
echo "  expected=$EXPECTED"
MAX_POLLS=60
POLL=0
while true; do
  ACTUAL=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
  if [ "$ACTUAL" -eq "$EXPECTED" ]; then
    echo "OK:   node count ($ACTUAL) matches expected ($EXPECTED)"
    break
  fi
  POLL=$((POLL + 1))
  if [ "$POLL" -gt "$MAX_POLLS" ]; then
    echo "FAIL: node count ($ACTUAL) does not match expected ($EXPECTED) after 30 minutes"
    exit 1
  fi
  echo "  [$POLL/$MAX_POLLS] actual=$ACTUAL expected=$EXPECTED, waiting 30s..."
  sleep 30
done

kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl wait --for=condition=Ready pods -l k8s-app=kube-dns -n kube-system --timeout=120s
kubectl wait --for=condition=Ready pods -l k8s-app=kube-proxy -n kube-system --timeout=120s

echo "Health check: all kube-system pods healthy"
for i in $(seq 1 20); do
  BAD_PODS=$(kubectl get pods -n kube-system --no-headers | grep -v -E 'Running|Completed' || true)
  if [ -z "$BAD_PODS" ]; then
    echo "OK:   all kube-system pods are Running or Completed"
    break
  fi
  if [ "$i" -eq 20 ]; then
    echo "FAIL: unhealthy pods in kube-system after 5 minutes:"
    echo "$BAD_PODS"
    exit 1
  fi
  echo "  waiting for pods to be ready (attempt $i/20)..."
  sleep 15
done
echo "Health check: all cluster health checks passed"
