#!/usr/bin/env bash
# shellcheck disable=SC2086,SC2174
set -o errexit -o nounset -o pipefail -x
shopt -s nullglob

level="${1:-0}"
pattern="${2:-/dev/nvme*n1}"
mount_primary="${3:-/mnt/nvme}"
mount_extra=(/var/lib/{containers,kubelet,openebs})

# Enumerate NVMe devices, exit if absent
devices=($pattern)
if [ ${#devices[@]} -eq 0 ]; then
  echo "No NVMe devices" >&2
  exit 0
fi

# Determine config for detected device count and RAID level
count=${#devices[@]}; bs=4; chunk=256
stride=$((chunk/bs)) # chunk size / block size
eff_count=$count # $level == 0
if [[ $level == 10 ]]; then eff_count=$((count/2)); fi
if [[ $level == 5 ]]; then eff_count=$((count-1)); fi
if [[ $level == 6 ]]; then eff_count=$((count-2)); fi
stripe=$((eff_count*stride)) # number of data disks * stride

echo -e "Creating RAID${level} filesystem mounted under ${mount_primary} with $count devices:\n  ${devices[*]}" >&2
echo -e "Filesystem options:\n  eff_count=$eff_count; chunk=${chunk}K; bs=${bs}K; stride=$stride; stripe-width=${stripe}" >&2
shopt -u nullglob; seen_arrays=(/dev/md/*); device=${seen_arrays[0]}
if [ ! -e "$device" ]; then
  device="/dev/md/0"
  echo "y" | mdadm --create "$device" --level="$level" --chunk=$chunk --force --raid-devices="$count" "${devices[@]}"
  dd if=/dev/zero of="$device" bs=${bs}K count=128
else
  echo "$device already initialized" >&2
fi

if ! tune2fs -l "$device" &>/dev/null; then
  echo "Formatting '$device'" >&2
  mkfs.ext4 -I 512 -b $((bs*1024)) -E stride=${stride},stripe-width=${stripe} -O dir_index -m 1 -F "$device"
else
  echo "$device already formatted" >&2
fi

mkdir -m 0755 -p "$mount_primary" "${mount_extra[@]}"
mountpoint -q "$mount_primary" || mount -v -o rw,noatime,nofail "$device" "$mount_primary" || :
grep -v "$mount_primary" /etc/fstab > /etc/fstab.new
echo "$device $mount_primary ext4 rw,noatime,nofail 0 2" | tee -a /etc/fstab.new

for mount in "${mount_extra[@]}"; do
  name=$(basename "$mount")
  mkdir -m 0755 -p "$mount_primary/$name"
  mountpoint -q "$mount" || mount -vB "$mount_primary/$name" "$mount" || :
  echo "$mount_primary $mount none defaults,bind 0 2" | tee -a /etc/fstab.new
done

mv -v /etc/fstab.new /etc/fstab # update persisted filesystem mounts
mdadm --detail --scan --verbose >> /etc/mdadm/mdadm.conf

update-initramfs -u