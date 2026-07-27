#!/usr/bin/env bash
set -euo pipefail

interval="${SUPPLICANT_RUNNER_INTERVAL:-10}"
health=/run/health

# A bad interval would otherwise reach `sleep` and CrashLoop every node.
if ! [ "$interval" -gt 0 ] 2>/dev/null; then
  echo "supplicant-runner: interval must be a positive integer, got '$interval'"
  exit 1
fi

mkdir -p "$health"

# Written via rename so a probe never reads a half-written marker.
mark() {
  date +%s > "$health/.$1.tmp" && mv -f "$health/.$1.tmp" "$health/$1"
}

while true; do
  # Streamed over stdin so nothing is staged on the host filesystem; the fd
  # survives the namespace switch. || rc=$? stops set -e exiting the loop.
  rc=0
  nsenter --target 1 --net --mount --uts --ipc --pid -- /bin/bash < /scripts/supplicant-runner.sh || rc=$?
  case $rc in
    0)
      mark healthy
      rm -f "$health/unauthorized"
      ;;
    # Fabric rejected a port. Stay Ready: an outage hits every node at once.
    2)
      mark healthy
      mark unauthorized
      ;;
    *)
      echo "supplicant-runner: reconciliation pass failed"
      ;;
  esac
  # Liveness only, not readiness: a restart kills this pod's supplicants.
  mark alive
  sleep "${interval}"
done
