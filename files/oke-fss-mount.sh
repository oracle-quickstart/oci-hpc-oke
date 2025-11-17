#!/bin/bash

# Variables (set these to your OCI details)
MOUNT_TARGET_IP="10.140.0.122"     # IP address of OCI FSS mount target
EXPORT_PATH="/oke-gpu-jevhap" # Export path of FSS (found in OCI console)
MOUNT_POINT="/mnt/oci-fss"      # Local directory to mount FSS

# Script to execute on each worker node
if command -v yum >/dev/null 2>&1; then
  sudo yum install -y nfs-utils
  echo "Installed nfs-utils"
elif command -v apt-get >/dev/null 2>&1; then
fi
  sudo mkdir -p $MOUNT_POINT
  sudo mount -t nfs -o vers=3 $MOUNT_TARGET_IP:$EXPORT_PATH $MOUNT_POINT
  echo "Successfully mounted"
  if ! grep -q '$MOUNT_TARGET_IP:$EXPORT_PATH' /etc/fstab; then
    echo "$MOUNT_TARGET_IP:$EXPORT_PATH $MOUNT_POINT nfs vers=3,_netdev 0 0" | sudo tee -a /etc/fstab
fi
