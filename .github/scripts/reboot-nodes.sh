#!/usr/bin/env bash
set -euo pipefail

echo "=== Rebooting all cluster nodes ==="

# Snapshot nodes up front so we have the list of names, instance IDs, and
# baseline bootIDs before any RESETs go out. If this call fails we abort
# before rebooting anything. Provider ID format: oci://<instance-ocid>.
NODE_SNAPSHOT=""
# Only capture stdout so kubectl warnings on stderr don't get parsed as rows.
if ! NODE_SNAPSHOT=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.providerID}{"\t"}{.status.nodeInfo.bootID}{"\n"}{end}'); then
  echo "FAIL: could not read cluster nodes (kubectl error shown above)"
  exit 1
fi

INSTANCE_IDS=()
NODE_NAMES=()
declare -A PRE_REBOOT_BOOT_ID
declare -A SEEN_REBOOTED
while IFS=$'\t' read -r node_name provider_id boot_id; do
  if [ -z "$node_name" ] && [ -z "$provider_id" ]; then
    continue
  fi
  instance_id="${provider_id#oci://}"
  if [ -z "$instance_id" ]; then
    echo "FAIL: node $node_name has no OCI provider ID; cannot reboot"
    exit 1
  fi
  if [ -z "$boot_id" ]; then
    echo "FAIL: node $node_name has no bootID in status.nodeInfo; cannot track reboot"
    exit 1
  fi
  INSTANCE_IDS+=("$instance_id")
  NODE_NAMES+=("$node_name")
  PRE_REBOOT_BOOT_ID["$node_name"]="$boot_id"
  SEEN_REBOOTED["$node_name"]=false
done <<< "$NODE_SNAPSHOT"

NODE_COUNT=${#INSTANCE_IDS[@]}
echo "  Found $NODE_COUNT node(s) to reboot"

if [ "$NODE_COUNT" -eq 0 ]; then
  echo "FAIL: no nodes found to reboot"
  exit 1
fi

# Snapshot GPU node count so we can confirm it's back after the reboot.
PRE_REBOOT_GPU_NODES=$(kubectl get nodes -o json | jq '[.items[] | select((.status.allocatable["nvidia.com/gpu"] // "0" | tonumber) > 0 or (.status.allocatable["amd.com/gpu"] // "0" | tonumber) > 0)] | length')
if [ "$PRE_REBOOT_GPU_NODES" -gt 0 ]; then
  echo "  $PRE_REBOOT_GPU_NODES node(s) currently advertising GPU resources"
fi

# Send RESET (immediate power cycle) to each instance.
for instance_id in "${INSTANCE_IDS[@]}"; do
  echo "  Sending RESET to instance: $instance_id"
  oci compute instance action --instance-id "$instance_id" --action RESET > /dev/null
done

echo "  All reboot commands sent. Waiting for every node's bootID to change..."

# bootID comes from the kernel and changes on every reboot, so a changed
# bootID proves the node actually rebooted, even if the reboot was too fast
# for the node to ever be marked NotReady.
MAX_POLLS=60
POLL=0
while true; do
  if CURRENT_SNAPSHOT=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.bootID}{"\n"}{end}'); then
    while IFS=$'\t' read -r name current_boot_id; do
      if [ -z "$name" ]; then
        continue
      fi
      if [ -n "$current_boot_id" ] \
        && [ "$current_boot_id" != "${PRE_REBOOT_BOOT_ID[$name]:-}" ] \
        && [ "${SEEN_REBOOTED[$name]:-}" = "false" ]; then
        SEEN_REBOOTED["$name"]=true
        echo "  Node $name rebooted (bootID changed)"
      fi
    done <<< "$CURRENT_SNAPSHOT"
  else
    echo "    kubectl get nodes failed (API may be unavailable; error shown above); treating as not yet rebooted"
  fi

  ALL_SEEN=true
  for name in "${NODE_NAMES[@]}"; do
    if [ "${SEEN_REBOOTED[$name]}" = "false" ]; then
      ALL_SEEN=false
      break
    fi
  done

  if $ALL_SEEN; then
    echo "  All $NODE_COUNT node(s) have rebooted (bootID changed)"
    break
  fi

  POLL=$((POLL + 1))
  if [ "$POLL" -gt "$MAX_POLLS" ]; then
    MISSING=()
    for name in "${NODE_NAMES[@]}"; do
      if [ "${SEEN_REBOOTED[$name]}" = "false" ]; then
        MISSING+=("$name")
      fi
    done
    echo "FAIL: nodes' bootIDs never changed after $MAX_POLLS polls: ${MISSING[*]}"
    exit 1
  fi
  echo "  [$POLL/$MAX_POLLS] Waiting for all nodes to reboot..."
  sleep 10
done

echo "  Waiting for all nodes to become Ready again..."
kubectl wait --for=condition=Ready nodes --all --timeout=900s
echo "  All $NODE_COUNT node(s) are Ready after reboot"

# Wait for every DaemonSet to have all pods ready. Covers GPU device plugins
# (needed for GPU resources to reappear) and node-level monitoring.
echo "  Waiting for all DaemonSets to become ready..."
for i in $(seq 1 40); do
  ALL_DS_READY=true
  DS_OUTPUT=""
  # Treat kubectl failures or empty output as "not ready" so we retry.
  # The API can be briefly unreachable right after a reboot.
  if ! DS_OUTPUT=$(kubectl get daemonsets --all-namespaces --no-headers); then
    ALL_DS_READY=false
    echo "    kubectl get daemonsets failed (API may be unavailable; error shown above)"
  elif [ -z "$DS_OUTPUT" ]; then
    ALL_DS_READY=false
    echo "    kubectl get daemonsets returned no rows; treating as not ready"
  else
    while IFS= read -r line; do
      ds_ns=$(echo "$line" | awk '{print $1}')
      ds_name=$(echo "$line" | awk '{print $2}')
      ds_desired=$(echo "$line" | awk '{print $3}')
      ds_ready=$(echo "$line" | awk '{print $5}')
      if [ "$ds_desired" != "$ds_ready" ]; then
        ALL_DS_READY=false
        if [ "$i" -eq 1 ] || [ $((i % 10)) -eq 0 ]; then
          echo "    $ds_ns/$ds_name: desired=$ds_desired ready=$ds_ready"
        fi
      fi
    done <<< "$DS_OUTPUT"
  fi

  if $ALL_DS_READY; then
    echo "  All DaemonSets are ready"
    break
  fi

  if [ "$i" -eq 40 ]; then
    echo "FAIL: DaemonSets not fully ready after 10 minutes:"
    kubectl get daemonsets --all-namespaces || true
    exit 1
  fi
  echo "  [$i/40] Waiting for DaemonSets to settle..."
  sleep 15
done

# DaemonSet readiness doesn't guarantee device plugins have re-advertised GPU
# resources to kubelet, so check the GPU node count separately.
if [ "$PRE_REBOOT_GPU_NODES" -gt 0 ]; then
  echo "  Waiting for GPU resources to be re-advertised on $PRE_REBOOT_GPU_NODES node(s)..."
  for i in $(seq 1 40); do
    # Run kubectl and jq separately so a transient failure just retries.
    # A piped `kubectl | jq` under `set -o pipefail` would abort the script.
    CURRENT_GPU_NODES=0
    if NODES_JSON=$(kubectl get nodes -o json); then
      if COUNT=$(jq '[.items[] | select((.status.allocatable["nvidia.com/gpu"] // "0" | tonumber) > 0 or (.status.allocatable["amd.com/gpu"] // "0" | tonumber) > 0)] | length' <<< "$NODES_JSON"); then
        CURRENT_GPU_NODES="$COUNT"
      else
        echo "    jq failed to parse node allocatable resources; treating as not ready"
      fi
    else
      echo "    kubectl get nodes failed (API may be unavailable; error shown above); treating as not ready"
    fi
    if [ "$CURRENT_GPU_NODES" -ge "$PRE_REBOOT_GPU_NODES" ]; then
      echo "  $CURRENT_GPU_NODES node(s) advertising GPU resources"
      break
    fi
    if [ "$i" -eq 40 ]; then
      echo "FAIL: GPU resources not re-advertised after 10 minutes (expected=$PRE_REBOOT_GPU_NODES current=$CURRENT_GPU_NODES)"
      kubectl get nodes -o custom-columns='NAME:.metadata.name,NVIDIA:.status.allocatable.nvidia\.com/gpu,AMD:.status.allocatable.amd\.com/gpu'
      exit 1
    fi
    echo "  [$i/40] GPU nodes: $CURRENT_GPU_NODES/$PRE_REBOOT_GPU_NODES, waiting..."
    sleep 15
  done
fi

echo "=== Node reboot complete ==="
