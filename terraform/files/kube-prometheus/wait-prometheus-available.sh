#!/usr/bin/env bash
# Wait until every Prometheus shard and replica is available. helm --wait only
# covers the release's own objects; the Prometheus Operator creates the
# Prometheus StatefulSets afterwards, so a shard that can't schedule would go
# unnoticed: its targets are simply not scraped and Thanos Query returns the
# other shards' data without an error.
#
# usage: wait-prometheus-available.sh <namespace> <prometheus name> <expected pods> [timeout seconds]
set -euo pipefail

NS="$1"
NAME="$2"
WANT="$3"
TIMEOUT="${4:-1200}"
deadline=$(($(date +%s) + TIMEOUT))

while :; do
  # Require the Available condition for the current generation, so a status
  # left over from before this upgrade doesn't count.
  state=$(kubectl -n "$NS" get prometheus "$NAME" -o jsonpath='{.metadata.generation} {.status.conditions[?(@.type=="Available")].observedGeneration} {.status.conditions[?(@.type=="Available")].status} {.status.availableReplicas}' 2>/dev/null || true)
  read -r gen observed available ready <<<"$state" || true
  if [[ -n "${gen:-}" && "$gen" == "${observed:-}" && "${available:-}" == "True" && "${ready:-0}" == "$WANT" ]]; then
    echo "Prometheus $NAME: $ready/$WANT pods available"
    exit 0
  fi
  if (($(date +%s) >= deadline)); then
    echo "Prometheus $NAME: ${ready:-0}/$WANT pods available after ${TIMEOUT}s (generation ${gen:-?}, observed ${observed:-?}, Available=${available:-?})." >&2
    kubectl -n "$NS" get pods -l "operator.prometheus.io/name=$NAME" -o wide >&2 || true
    kubectl -n "$NS" get events --field-selector reason=FailedScheduling --sort-by=.lastTimestamp 2>/dev/null | tail -5 >&2 || true
    exit 1
  fi
  sleep 10
done
