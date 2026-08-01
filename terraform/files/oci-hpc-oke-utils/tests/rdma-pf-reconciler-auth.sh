#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
auth="$script_dir/../files/rdma-pf-reconciler/reconcile-auth.sh"
tests=0

load_function() {
  local name=$1 body
  body=$(sed -n "/^${name}()/,/^}/p" "$auth")
  if [ -z "$body" ]; then
    printf 'FAIL: function %s not found\n' "$name" >&2
    exit 1
  fi
  eval "$body"
}

load_function netns_has_other_procs
load_function find_in_netns

declare -A NS_PIDS=()
declare -A OUR_PIDS=()

build_proc_map() { :; }

readlink() {
  case "$1" in
    /proc/100/ns/net | /proc/200/ns/net) printf '%s\n' 'net:[10]' ;;
    /proc/101/ns/net) printf '%s\n' 'net:[gone]' ;;
    *) command readlink "$@" ;;
  esac
}

cat() {
  case "$1" in
    /proc/200/comm) printf '%s\n' pause ;;
    *) command cat "$@" ;;
  esac
}

netns_has_iface() { return 0; }
netns_ifaces() { printf '%s\n' rdma0; }
bus_info() { printf '%s\n' '0000:00:01.0'; }

NS_PIDS['net:[10]']='100 101 '
OUR_PIDS[100]=1
if netns_has_other_procs 'net:[10]'; then
  printf 'FAIL: dead cached PID was treated as a workload process\n' >&2
  exit 1
fi
tests=$(( tests + 1 ))

NS_PIDS['net:[10]']='100 200 '
if ! netns_has_other_procs 'net:[10]'; then
  printf 'FAIL: live workload process was not detected\n' >&2
  exit 1
fi
tests=$(( tests + 1 ))

NS_PIDS['net:[10]']='100 '
if found=$(find_in_netns rdma0 '0000:00:01.0'); then
  printf 'FAIL: PF was rediscovered through its own supplicant namespace: %s\n' "$found" >&2
  exit 1
fi
tests=$(( tests + 1 ))

NS_PIDS['net:[10]']='100 200 '
# The loaded production functions read these arrays through eval.
: "${NS_PIDS['net:[10]']}" "${OUR_PIDS[100]}"
found=$(find_in_netns rdma0 '0000:00:01.0')
if [ "$found" != '100 rdma0' ]; then
  printf 'FAIL: PF in a live pod namespace was not found: %s\n' "$found" >&2
  exit 1
fi
tests=$(( tests + 1 ))

printf 'PASS: %d RDMA PF reconciler authentication tests\n' "$tests"
