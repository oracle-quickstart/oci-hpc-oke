#!/usr/bin/env bash
set -euo pipefail

# Kill SSH tunnel processes and clean up kubeconfig files.

for pidfile in /tmp/oke-bastion-tunnel-*.pid; do
  [ -f "$pidfile" ] || continue
  PID=$(cat "$pidfile")
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    echo "Killed SSH tunnel (PID: $PID)"
  fi
  rm -f "$pidfile"
done
rm -f "$HOME/.kube/config" "$HOME/.kube/oke-bastion/"*.yaml 2>/dev/null || true
