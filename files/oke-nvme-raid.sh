
#!/usr/bin/env bash
# shellcheck disable=SC2086,SC2174
set -o errexit -o nounset -o pipefail -x
shopt -s nullglob

level="${1:-0}"
pattern="${2:-/dev/nvme*n1}"
mount_primary="${3:-/mnt/nvme}"
mount_extra=(/var/lib/{containers,kubelet,logs/pods})
md_device="/dev/md/0"

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
if [ ! -e "$md_device" ]; then
  echo "y" | mdadm --create "$md_device" --level="$level" --chunk=$chunk --force --raid-devices="$count" "${devices[@]}"
  dd if=/dev/zero of="$md_device" bs=${bs}K count=128
else
  echo "$md_device already initialized" >&2
fi

if ! tune2fs -l "$md_device" &>/dev/null; then
  echo "Formatting '$md_device'" >&2
  mkfs.ext4 -I 512 -b $((bs*1024)) -E stride=${stride},stripe-width=${stripe} -O dir_index -m 1 -F "$md_device"
else
  echo "$md_device already formatted" >&2
fi

mkdir -m 0755 -p "$mount_primary" "${mount_extra[@]}"
dev_uuid=$(blkid -s UUID -o value "${md_device}")
mount_unit_name="$(systemd-escape --path --suffix=mount "${mount_primary}")"
cat > "/etc/systemd/system/${mount_unit_name}" << EOF
    [Unit]
    Description=Mount local NVMe RAID for OKE
    [Mount]
    What=UUID=${dev_uuid}
    Where=${mount_primary}
    Type=ext4
    Options=defaults,noatime
    [Install]
    WantedBy=multi-user.target
EOF
  systemd-analyze verify "${mount_unit_name}"
  systemctl enable "${mount_unit_name}" --now

for mount in "${mount_extra[@]}"; do
  name=$(basename "$mount")
  array_mount_point_name="$mount_primary/$name"
  mkdir -m 0755 -p "$mount_primary/$name"
  mount_unit_name="$(systemd-escape --path --suffix=mount "${mount}")"
  cat > "/etc/systemd/system/${mount_unit_name}" << EOF
      [Unit]
      Description=Mount ${name} on OKE NVMe RAID
      [Mount]
      What=${array_mount_point_name}
      Where=${mount}
      Type=none
      Options=bind
      [Install]
      WantedBy=multi-user.target
EOF
    systemd-analyze verify "${mount_unit_name}"
    systemctl enable "${mount_unit_name}" --now  
done

mdadm --detail --scan --verbose >> /etc/mdadm/mdadm.conf

update-initramfs -u
