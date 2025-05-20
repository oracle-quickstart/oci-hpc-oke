#!/usr/bin/env bash
set -e -o pipefail

function numvfs_path_for_interface() { # numvfs_path_for_interface(interface)
  echo "/sys/class/net/${1}/device/sriov_numvfs"
}
function get_vf_dev_name() (
  local interface="${1}" vf_idx="${2}"
  ls /sys/class/net/"${interface}"/device/virtfn"${vf_idx}"/net
)
function get_eff_mac_addr() (
  local interface="${1}" vf_idx="${2}"
  vf_dev_name=$(get_vf_dev_name "$interface" "$vf_idx")
  cat "/sys/class/net/${interface}/device/virtfn${vf_idx}/net/$vf_dev_name/address"
)
function get_vf_pci_addr() (
  local interface="${1}" vf_idx="${2}"
  local vf_dev_name; vf_dev_name=$(get_vf_dev_name "$interface" "$vf_idx")
  grep PCI_SLOT_NAME /sys/class/net/"${vf_dev_name}"/device/uevent | cut -d "=" -f 2
)
function create_vfs() (
  set +x; local interface="${1}" num_vfs="${2}"
  echo "Creating ${num_vfs} VFs for ${interface}" >&2
  numvfs_path=$(numvfs_path_for_interface "${interface}")
  if [[ ! -f "${numvfs_path}" ]]; then
    echo "virtual function path does not exist for interface ${interface}. Skipping..."
    return
  fi
  # Create the SRIOV virtual functions
  current_num_of_vfs=$(cat "${numvfs_path}")
  if [[ "${current_num_of_vfs}" != "${2}" ]]; then
    echo "Creating VFs for ${1} (current: ${current_num_of_vfs}, target: ${2}, path: ${numvfs_path})"
    if [[ "${current_num_of_vfs}" != "0" ]]; then # Must be set to 0 first
      echo "0" | tee "${numvfs_path}" > /dev/null 2>&1 || echo "Error resetting VFs for '${1}'"
    fi
    echo "${2}" | tee "${numvfs_path}" > /dev/null 2>&1 || echo "Error creating VFs for '${1}'"
  else
    echo "${2} VFs already created for ${interface}"
  fi
  # Configure the SRIOV virtual functions with the effective MAC address
  for (( i=0; i<=$((num_vfs-1)); i++ )); do
    local mac; mac=$(get_eff_mac_addr "${interface}" ${i})
    local vf_dev_name; vf_dev_name=$(get_vf_dev_name "$interface" $i)
    echo "Setting ${interface} VF ${i} ${vf_dev_name} MAC to ${mac}" >&2
    ip link set dev "$interface" vf ${i} mac "$mac"
    local vf_pci_addr; vf_pci_addr=$(get_vf_pci_addr "$interface" ${i})
    echo "$vf_pci_addr" > /sys/bus/pci/drivers/mlx5_core/unbind
    echo "$vf_pci_addr" > /sys/bus/pci/drivers/mlx5_core/bind
  done
)
interface="${1}"
num_vfs="${2:-1}"
create_vfs "${interface}" "${num_vfs}" || echo "Error creating ${num_vfs} VFs for ${interface}" >&2
