#!/usr/bin/env bash
set -euo pipefail

# Clean up test pods and PVCs created by health checks.
# Env: TOPOLOGY

if [ ! -f "$HOME/.kube/config" ]; then
  echo "No kubeconfig found, skipping cleanup"
  exit 0
fi

# Network test resources (always)
kubectl delete pod net-server net-client dns-checker --ignore-not-found --wait=true --timeout=60s || true

# FSS test resources
if [[ "$TOPOLOGY" == *fss* ]]; then
  kubectl delete pod fss-writer fss-reader fss-hostpath-reader --ignore-not-found --wait=true --timeout=60s || true
  kubectl delete pvc fss-test-pvc --ignore-not-found --wait=true --timeout=120s || true
fi

# Lustre test resources
if [[ "$TOPOLOGY" == *lustre* ]]; then
  kubectl delete pod lustre-writer lustre-reader lustre-hostpath-reader --ignore-not-found --wait=true --timeout=60s || true
  kubectl delete pvc lustre-test-pvc --ignore-not-found --wait=true --timeout=120s || true
  # PV uses Retain reclaim policy, so clear claimRef to return it to Available
  # and let subsequent PVCs bind to it (e.g. the post-reboot health check).
  if kubectl get pv lustre-pv >/dev/null 2>&1; then
    kubectl patch pv lustre-pv --type=merge -p '{"spec":{"claimRef":null}}' || true
  fi
fi
