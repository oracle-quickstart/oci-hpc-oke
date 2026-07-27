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
  # Streamed over stdin: the fd survives the namespace switch, so nothing
  # is staged on the host filesystem. Readiness (healthy) tracks whether the
  # runner is working, not whether the fabric authorizes us: a RADIUS outage
  # would otherwise take every node NotReady at once and fail helm --wait.
  # Liveness (alive) tracks only the loop, since a restart kills the
  # supplicants this pod started.
  # || rc=$? keeps a nonzero pass from tripping set -e and exiting the loop.
  rc=0
  nsenter --target 1 --net --mount --uts --ipc --pid -- /bin/bash < /scripts/supplicant-runner.sh || rc=$?
  case $rc in
    0)
      mark healthy
      rm -f "$health/unauthorized"
      ;;
    2)
      mark healthy
      mark unauthorized
      ;;
    *)
      echo "supplicant-runner: reconciliation pass failed"
      ;;
  esac
  mark alive
  sleep "${interval}"
done
