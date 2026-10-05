#!/usr/bin/env bash
# Sets the RDMA subsystem network namespace mode: shared for Dranet claims,
# exclusive for SR-IOV VFs. The runtime switch fails once pods exist, so this
# runs before the OKE bootstrap.
MODE="${1:-}"
case "$MODE" in
  shared) NETNS_MODE=1 ;;
  exclusive) NETNS_MODE=0 ;;
  *) echo "Usage: $0 shared|exclusive" >&2; exit 1 ;;
esac
if [ -n "$(ls -A /sys/class/infiniband 2>/dev/null)" ]; then
  echo "options ib_core netns_mode=${NETNS_MODE}" > /etc/modprobe.d/ib_core.conf
  # Keep the mode across reboots.
  if command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u || echo "RDMA netns: update-initramfs failed" >&2
  fi
  # The switch also fails while any other network namespace exists, for example
  # one of a short-lived service such as systemd-hostnamed, so retry for 90 s.
  for i in $(seq 1 30); do
    if rdma system set netns "$MODE" 2>/dev/null; then
      echo "RDMA netns: mode set to $MODE"
      break
    fi
    if [ "$i" -eq 30 ]; then
      echo "RDMA netns: failed to set the mode to $MODE; network namespaces:" >&2
      lsns -t net -o NS,PID,COMMAND >&2
      exit 1
    else
      sleep 3
    fi
  done
fi
