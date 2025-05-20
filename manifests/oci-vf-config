#!/usr/bin/env bash
set -e -o pipefail

num_vfs="${1:-1}"

find /sys/class/net -name "rdma*" | grep -v "v[0-9]*" | sort | \
  xargs -n1 basename | xargs -I{} oci-create-vfs {} "$num_vfs"
