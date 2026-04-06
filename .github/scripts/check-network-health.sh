#!/usr/bin/env bash
set -euo pipefail

# Unused here but accepted for consistent interface across health check scripts
# shellcheck disable=SC2034
STATE_FILE="${1:?Usage: $0 <state-file> <prefix>}"
# shellcheck disable=SC2034
PREFIX="${2:-}"

echo "Health check: pod-to-pod connectivity"
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: net-server
spec:
  restartPolicy: Never
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
  - key: amd.com/gpu
    operator: Exists
  containers:
  - name: server
    image: busybox
    command: ["sh", "-c", "echo 'net-check-ok' > /tmp/index.html && httpd -f -p 8080 -h /tmp"]
EOF

kubectl wait --for=condition=Ready pod/net-server --timeout=120s
SERVER_IP=$(kubectl get pod net-server -o jsonpath='{.status.podIP}')
echo "  server pod IP: $SERVER_IP"

kubectl apply -f - <<CLIENTEOF
apiVersion: v1
kind: Pod
metadata:
  name: net-client
spec:
  restartPolicy: Never
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
  - key: amd.com/gpu
    operator: Exists
  containers:
  - name: client
    image: busybox
    command: ["sh", "-c", "for i in \$(seq 1 30); do RESULT=\$(wget -qO- -T 5 http://${SERVER_IP}:8080/index.html 2>/dev/null) && echo \"\$RESULT\" && exit 0; sleep 2; done; echo 'timeout'; exit 1"]
CLIENTEOF

kubectl wait --for='jsonpath={.status.phase}=Succeeded' pod/net-client --timeout=120s
CLIENT_OUTPUT=$(kubectl logs net-client)
if [[ "$CLIENT_OUTPUT" != *"net-check-ok"* ]]; then
  echo "FAIL: pod-to-pod connectivity failed: $CLIENT_OUTPUT"
  exit 1
fi
echo "OK:   pod-to-pod connectivity verified"

echo "Health check: DNS resolution"
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: dns-checker
spec:
  restartPolicy: Never
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
  - key: amd.com/gpu
    operator: Exists
  containers:
  - name: dns
    image: busybox
    command: ["sh", "-c", "nslookup kubernetes.default.svc.cluster.local"]
EOF

kubectl wait --for='jsonpath={.status.phase}=Succeeded' pod/dns-checker --timeout=120s
DNS_OUTPUT=$(kubectl logs dns-checker)
if echo "$DNS_OUTPUT" | grep -q 'NXDOMAIN'; then
  echo "FAIL: DNS resolution failed: $DNS_OUTPUT"
  exit 1
fi
echo "OK:   DNS resolution verified"
echo "Health check: all network health checks passed"
