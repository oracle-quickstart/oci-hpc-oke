#!/usr/bin/env bash
set -euo pipefail

# Generate kubeconfig for the OKE cluster.
# Usage: generate-kubeconfig.sh <state-file> <prefix>
# Env: TOPOLOGY, OCI_REGION

STATE_FILE="${1:?Usage: $0 <state-file> <prefix>}"
PREFIX="${2:-}"

CLUSTER_ID=$(jq -r ".${PREFIX}cluster_id.value" "$STATE_FILE")
mkdir -p "$HOME/.kube"

if [[ "$TOPOLOGY" == public* ]]; then
  oci ce cluster create-kubeconfig \
    --cluster-id "$CLUSTER_ID" \
    --file "$HOME/.kube/config" \
    --region "$OCI_REGION" \
    --token-version 2.0.0 \
    --kube-endpoint PUBLIC_ENDPOINT
else
  BASTION_ID=$(jq -r ".${PREFIX}bastion_service_id.value // empty" "$STATE_FILE")
  ENDPOINT_IP=$(jq -r ".${PREFIX}oke_private_endpoint_ip.value // empty" "$STATE_FILE")

  if [ -z "$BASTION_ID" ] || [ -z "$ENDPOINT_IP" ]; then
    echo "FAIL: bastion_service_id or oke_private_endpoint_ip is empty -- is create_oci_bastion_service enabled?"
    exit 1
  fi

  ./files/oke-bastion-service-session.sh \
    --bastion-ocid "$BASTION_ID" \
    --cluster-ocid "$CLUSTER_ID" \
    --oke-endpoint-ip "$ENDPOINT_IP" \
    --region "$OCI_REGION" \
    --ssh-key ~/.ssh/bastion_key \
    --local-port 6443 \
    --ttl-seconds 10800 \
    --auto-tunnel \
    --non-interactive

  BASTION_KCFG="$HOME/.kube/oke-bastion/${CLUSTER_ID}.yaml"
  if [ ! -f "$BASTION_KCFG" ]; then
    echo "ERROR: bastion script did not produce kubeconfig at $BASTION_KCFG"
    ls -la "$HOME/.kube/oke-bastion/" || true
    exit 1
  fi
  cp "$BASTION_KCFG" "$HOME/.kube/config"
  echo "Verifying tunnel connectivity..."
  kubectl --kubeconfig "$HOME/.kube/config" cluster-info
fi
