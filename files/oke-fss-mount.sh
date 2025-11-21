#!/bin/bash

# Variables (set these to your OCI FSS details)
MOUNT_TARGET_IP="$3"     # IP address of OCI FSS mount target
EXPORT_PATH="$1"      # Export path of FSS (from OCI Console)
MOUNT_POINT="$2"         # Local directory to mount FSS

# Install NFS utils on yum or apt-get systems
if command -v yum >/dev/null 2>&1; then
  yum install -y nfs-utils
  echo "Installed nfs-utils via yum"
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get install -y nfs-common
  echo "Installed nfs-common via apt-get"
fi

# Create mount point directory if it doesn't exist
mkdir -p "$MOUNT_POINT"

# Mount the NFS share
mount -t nfs -o vers=3 "$MOUNT_TARGET_IP:$EXPORT_PATH" "$MOUNT_POINT"
if [ $? -eq 0 ]; then
  echo "Successfully mounted $MOUNT_TARGET_IP:$EXPORT_PATH at $MOUNT_POINT"
else
  echo "Failed to mount $MOUNT_TARGET_IP:$EXPORT_PATH" >&2
  exit 1
fi

# Add entry to /etc/fstab for re-mount at boot (if not already present)
if ! grep -q "$MOUNT_TARGET_IP:$EXPORT_PATH" /etc/fstab; then
  echo "$MOUNT_TARGET_IP:$EXPORT_PATH $MOUNT_POINT nfs vers=3,_netdev 0 0" >> /etc/fstab
  echo "Added mount entry to /etc/fstab"
else
  echo "Mount entry already exists in /etc/fstab"
fi
