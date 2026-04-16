#!/bin/bash
set -euo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <lustre_ip> <lustre_fs_name> <mount_point>" >&2
  exit 1
fi

LUSTRE_IP="$1"
LUSTRE_FS_NAME="$2"
MOUNT_POINT="$3"

if [ -z "$LUSTRE_IP" ] || [ -z "$LUSTRE_FS_NAME" ] || [ -z "$MOUNT_POINT" ]; then
  echo "Error: lustre_ip, lustre_fs_name, and mount_point must not be empty" >&2
  exit 1
fi

if ! modinfo lnet >/dev/null 2>&1; then
  echo "Lustre client (lnet kernel module) is not available on this node; skipping mount"
  exit 0
fi

LNET_IFACE=$(ip -o route get "$LUSTRE_IP" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
if [ -z "$LNET_IFACE" ] && ip link show eth0 >/dev/null 2>&1; then
  LNET_IFACE=eth0
fi
if [ -z "$LNET_IFACE" ]; then
  LNET_IFACE=$(ip route show default | awk '/default/ {print $5; exit}')
fi
if [ -z "$LNET_IFACE" ]; then
  echo "Error: unable to determine TCP interface for LNet" >&2
  exit 1
fi

case "$LNET_IFACE" in
  rdma*|ib*|mlx*)
    echo "Error: resolved interface '$LNET_IFACE' looks like an RDMA device; refusing to bind LNet TCP to it" >&2
    exit 1
    ;;
esac

MODPROBE_CONF="/etc/modprobe.d/lustre-client.conf"
MODPROBE_LINE="options lnet networks=\"tcp(${LNET_IFACE})\""
if [ ! -f "$MODPROBE_CONF" ] || ! grep -qxF "$MODPROBE_LINE" "$MODPROBE_CONF"; then
  echo "# Managed by oke-lustre-mount.sh. Do not edit." > "$MODPROBE_CONF"
  echo "$MODPROBE_LINE" >> "$MODPROBE_CONF"
  echo "Wrote LNet interface preference to $MODPROBE_CONF"
  if grep -q '^lnet ' /proc/modules 2>/dev/null; then
    echo "LNet already loaded; new interface setting will take effect on next reboot or manual module reload."
  fi
fi

if ! grep -q '^lnet ' /proc/modules 2>/dev/null; then
  echo "LNet not loaded, loading..."
  modprobe lnet
fi

lnet_output="$(lnetctl net show 2>&1 || true)"

if printf '%s\n' "$lnet_output" | grep -q "LNet stack down"; then
  lnetctl lnet configure
  lnetctl net add --net tcp --if "$LNET_IFACE" --peer-timeout 180 --peer-credits 120 --credits 1024
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
