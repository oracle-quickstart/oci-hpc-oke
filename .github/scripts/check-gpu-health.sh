#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${1:?Usage: $0 <state-file> <prefix>}"
PREFIX="${2:-}"

GPU_POOL_ID=$(jq -r ".${PREFIX}worker_gpu_pool_id.value // empty" "$STATE_FILE")
RDMA_POOL_ID=$(jq -r ".${PREFIX}worker_rdma_pool_id.value // empty" "$STATE_FILE")

if [ -z "$GPU_POOL_ID" ] && [ -z "$RDMA_POOL_ID" ]; then
  echo "No GPU or RDMA pools enabled, skipping GPU resource check"
  exit 0
fi

echo "Health check: GPU resources advertised on nodes"
GPU_NODES=$(kubectl get nodes -o json | jq -r '
  .items[] |
  select(
    (.status.allocatable["nvidia.com/gpu"] // "0" | tonumber) > 0 or
    (.status.allocatable["amd.com/gpu"] // "0" | tonumber) > 0
  ) |
  "\(.metadata.name) nvidia=\(.status.allocatable["nvidia.com/gpu"] // "0") amd=\(.status.allocatable["amd.com/gpu"] // "0")"
')

if [ -z "$GPU_NODES" ]; then
  echo "FAIL: GPU/RDMA pool(s) exist but no nodes advertise GPU resources"
  kubectl get nodes -o custom-columns='NAME:.metadata.name,NVIDIA:.status.allocatable.nvidia\.com/gpu,AMD:.status.allocatable.amd\.com/gpu'
  exit 1
fi

echo "  GPU nodes found:"
echo "$GPU_NODES" | while read -r line; do echo "    $line"; done
echo "OK:   GPU resources advertised on nodes"
