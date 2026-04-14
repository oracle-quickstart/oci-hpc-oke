#!/usr/bin/env bash
set -euo pipefail

echo "=== Rebooting all cluster nodes ==="

# Snapshot every node and its backing OCI instance up front. Done in a single
# pre-reboot kubectl call so that a transient API failure here aborts before
# we send any SOFTRESETs, and so the later NotReady-polling loop has a
# reliable list of node names to watch (an empty list would vacuously pass).
# Provider ID format in OCI: oci://<instance-ocid>
NODE_SNAPSHOT=""
# Let kubectl write any warnings/errors to stderr (surfaced in the workflow
# log). Only stdout is captured here so deprecation warnings and similar
# messages cannot be parsed as node rows below.
if ! NODE_SNAPSHOT=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.providerID}{"\n"}{end}'); then
  echo "FAIL: could not read cluster nodes (kubectl error shown above)"
  exit 1
fi

INSTANCE_IDS=()
NODE_NAMES=()
declare -A SEEN_NOT_READY
while IFS=$'\t' read -r node_name provider_id; do
  if [ -z "$node_name" ] && [ -z "$provider_id" ]; then
    continue
  fi
  instance_id="${provider_id#oci://}"
  if [ -z "$instance_id" ]; then
    echo "FAIL: node $node_name has no OCI provider ID; cannot reboot"
    exit 1
  fi
  INSTANCE_IDS+=("$instance_id")
  NODE_NAMES+=("$node_name")
  SEEN_NOT_READY["$node_name"]=false
done <<< "$NODE_SNAPSHOT"

NODE_COUNT=${#INSTANCE_IDS[@]}
echo "  Found $NODE_COUNT node(s) to reboot"

if [ "$NODE_COUNT" -eq 0 ]; then
  echo "FAIL: no nodes found to reboot"
  exit 1
fi

# Snapshot pre-reboot GPU node count so we can verify GPU resources reappear
# after device plugins re-register with kubelet.
PRE_REBOOT_GPU_NODES=$(kubectl get nodes -o json | jq '[.items[] | select((.status.allocatable["nvidia.com/gpu"] // "0" | tonumber) > 0 or (.status.allocatable["amd.com/gpu"] // "0" | tonumber) > 0)] | length')
if [ "$PRE_REBOOT_GPU_NODES" -gt 0 ]; then
  echo "  $PRE_REBOOT_GPU_NODES node(s) currently advertising GPU resources"
fi

# Send SOFTRESET (graceful reboot) to each instance.
for instance_id in "${INSTANCE_IDS[@]}"; do
  echo "  Sending SOFTRESET to instance: $instance_id"
  oci compute instance action --instance-id "$instance_id" --action SOFTRESET > /dev/null
done

echo "  All reboot commands sent. Waiting for every node to go NotReady..."

# NODE_NAMES and SEEN_NOT_READY were populated from the pre-reboot snapshot
# above. Tracking each node individually here (rather than re-querying the
# API after SOFTRESETs land) guarantees we have a non-empty list to poll
# against. A node is only considered rebooted once it has been observed as
# NotReady, which prevents a race where early nodes come back Ready before
# late nodes have even started rebooting.
MAX_POLLS=60
POLL=0
while true; do
  while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    status=$(echo "$line" | awk '{print $2}')
    if [[ "$status" == *"NotReady"* ]] && [ "${SEEN_NOT_READY[$name]:-}" = "false" ]; then
      SEEN_NOT_READY["$name"]=true
      echo "  Node $name observed NotReady"
    fi
  done < <(kubectl get nodes --no-headers)

  ALL_SEEN=true
  for name in "${NODE_NAMES[@]}"; do
    if [ "${SEEN_NOT_READY[$name]}" = "false" ]; then
      ALL_SEEN=false
      break
    fi
  done

  if $ALL_SEEN; then
    echo "  All $NODE_COUNT node(s) have been observed NotReady"
    break
  fi

  POLL=$((POLL + 1))
  if [ "$POLL" -gt "$MAX_POLLS" ]; then
    MISSING=()
    for name in "${NODE_NAMES[@]}"; do
      if [ "${SEEN_NOT_READY[$name]}" = "false" ]; then
        MISSING+=("$name")
      fi
    done
    echo "FAIL: nodes never became NotReady after $MAX_POLLS polls: ${MISSING[*]}"
    exit 1
  fi
  echo "  [$POLL/$MAX_POLLS] Waiting for all nodes to reboot..."
  sleep 10
done

echo "  Waiting for all nodes to become Ready again..."
kubectl wait --for=condition=Ready nodes --all --timeout=900s
echo "  All $NODE_COUNT node(s) are Ready after reboot"

# Wait for all DaemonSets across all namespaces to have their full complement
# of ready pods. This covers GPU device plugins (which must re-register with
# kubelet before allocatable GPU resources reappear) and monitoring DaemonSets
# like prometheus-node-exporter.
echo "  Waiting for all DaemonSets to become ready..."
for i in $(seq 1 40); do
  ALL_DS_READY=true
  DS_OUTPUT=""
  # Treat any kubectl failure or empty response as "not ready" rather than
  # letting the inner loop produce zero iterations and vacuously pass. The
  # API can be briefly unreachable right after a reboot while the bastion
  # tunnel or webhook endpoints are still catching up.
  # Capture only stdout. Warnings on stderr pass through to the workflow
  # log and must not be parsed as DaemonSet rows.
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

# DaemonSet readiness does not guarantee that device plugins have re-registered
# extended resources with kubelet. Wait for the same number of GPU nodes that
# existed before the reboot to re-advertise allocatable GPU resources.
if [ "$PRE_REBOOT_GPU_NODES" -gt 0 ]; then
  echo "  Waiting for GPU resources to be re-advertised on $PRE_REBOOT_GPU_NODES node(s)..."
  for i in $(seq 1 40); do
    # Split kubectl and jq so a transient API failure (or a jq parse error
    # on empty input) is treated as "not yet ready" and the loop retries,
    # matching how the DaemonSet poll above handles kubectl failures. A
    # piped `kubectl | jq` under `set -o pipefail` would abort the script.
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
