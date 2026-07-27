#!/usr/bin/env bash
set -euo pipefail

interval="${SUPPLICANT_RUNNER_INTERVAL:-10}"

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
      date +%s > /tmp/healthy
      rm -f /tmp/unauthorized
      ;;
    2)
      date +%s > /tmp/healthy
      date +%s > /tmp/unauthorized
      ;;
    *)
      echo "supplicant-runner: reconciliation pass failed"
      ;;
  esac
  date +%s > /tmp/alive
  sleep "${interval}"
done
