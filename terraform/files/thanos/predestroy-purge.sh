#!/usr/bin/env bash
# Empty the stack-created Thanos bucket so terraform can delete it: OCI refuses
# to delete a bucket that still holds objects or uncommitted multipart uploads.
#
# Runs on destroy after kube-prometheus-stack (the sidecars and the Thanos
# Ruler) is gone and before the thanos release and the bucket are deleted. The
# purge itself runs in-cluster as the thanos ServiceAccount through OKE
# workload identity, so the caller needs only kubectl.
#
# usage: predestroy-purge.sh <namespace> <bucket> <region>
set -euo pipefail

NAMESPACE="$1"
BUCKET="$2"
REGION="$3"
POD=thanos-bucket-purge
IMAGE=ghcr.io/oracle/oci-cli:20261007

if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "Namespace $NAMESPACE not found, nothing to purge."
  exit 0
fi

# The compactor is the last writer: stop it so it can't upload a compacted
# block or a deletion mark after the purge.
kubectl -n "$NAMESPACE" scale statefulset thanos-compact --replicas=0 2>/dev/null || true
kubectl -n "$NAMESPACE" wait --for=delete pod -l app.kubernetes.io/name=thanos-compact --timeout=5m 2>/dev/null || true

read -r -d '' PURGE <<'EOF' || true
set -euo pipefail
oci() { command oci --auth oke_workload_identity "$@"; }
echo "Deleting all objects in $BUCKET"
oci os object bulk-delete -bn "$BUCKET" --force
echo "Aborting uncommitted multipart uploads"
oci os multipart list -bn "$BUCKET" --all --query 'data[].[object, "upload-id"]' --output json \
  | python3 -c 'import json, sys; [print(o, u, sep="\t") for o, u in (json.loads(sys.stdin.read() or "[]") or [])]' \
  | while IFS=$'\t' read -r object upload_id; do
      oci os multipart abort -bn "$BUCKET" -on "$object" --upload-id "$upload_id" --force
    done
left=$(oci os object list -bn "$BUCKET" --all --query 'length(data || `[]`)' --raw-output)
echo "Objects left: $left"
[ "$left" = "0" ]
EOF

kubectl -n "$NAMESPACE" delete pod "$POD" --ignore-not-found --wait=true
kubectl -n "$NAMESPACE" run "$POD" --restart=Never --image="$IMAGE" \
  --env="BUCKET=$BUCKET" \
  --env="OCI_RESOURCE_PRINCIPAL_VERSION=2.2" \
  --env="OCI_RESOURCE_PRINCIPAL_REGION=$REGION" \
  --overrides='{"spec":{"serviceAccountName":"thanos"}}' \
  --command -- bash -c "$PURGE"

phase=""
for _ in $(seq 1 180); do
  phase=$(kubectl -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  case "$phase" in Succeeded | Failed) break ;; esac
  sleep 10
done
kubectl -n "$NAMESPACE" logs "$POD" 2>/dev/null || true
kubectl -n "$NAMESPACE" delete pod "$POD" --ignore-not-found --wait=false
if [ "$phase" != "Succeeded" ]; then
  echo "Thanos bucket purge did not succeed (pod phase: ${phase:-unknown}). Empty bucket $BUCKET manually before deleting it."
  exit 1
fi
