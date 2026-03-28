#!/bin/bash

LUSTRE_IP="$1"
LUSTRE_FS_NAME="$2"
MOUNT_POINT="$3"

if ! modinfo lnet >/dev/null 2>&1; then
  echo "Lustre client (lnet kernel module) is not available on this node; skipping mount"
  exit 0
fi

if ! grep -q '^lnet ' /proc/modules 2>/dev/null; then
  echo "LNet not loaded, loading..."
  modprobe lnet
fi

lnet_output="$(lnetctl net show 2>&1 || true)"

if printf '%s\n' "$lnet_output" | grep -q "LNet stack down"; then
  lnetctl lnet configure
  DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}')
  lnetctl net add --net tcp --if "$DEFAULT_IFACE" --peer-timeout 180 --peer-credits 120 --credits 1024
  echo "LNet configured successfully"
fi

mkdir -p "$MOUNT_POINT"

if mount -t lustre "${LUSTRE_IP}@tcp:/${LUSTRE_FS_NAME}" "$MOUNT_POINT"; then
  echo "Successfully mounted ${LUSTRE_IP}@tcp:/${LUSTRE_FS_NAME} at $MOUNT_POINT"
else
  echo "Error mounting Lustre volume" >&2
  exit 1
fi

if ! grep -q "${LUSTRE_IP}@tcp:/${LUSTRE_FS_NAME}" /etc/fstab; then
  echo "${LUSTRE_IP}@tcp:/${LUSTRE_FS_NAME} $MOUNT_POINT lustre defaults,_netdev 0 0" >> /etc/fstab
  echo "Added mount entry to /etc/fstab"
else
  echo "Mount entry already exists in /etc/fstab"
fi
