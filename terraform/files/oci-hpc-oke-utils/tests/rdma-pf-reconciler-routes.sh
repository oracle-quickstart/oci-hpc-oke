#!/usr/bin/env bash
set -euo pipefail

LC_NUMERIC=C

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$script_dir/../files/rdma-pf-reconciler/restore-host-routes.sh"

tests=0
logs=""
mock_rules=""
mock_main_routes=""
mock_table_routes=""
mock_apply_routes=1
mock_iface=""
mock_table=""
mock_address=""
mock_network=""
replace_calls=()

log() {
  logs+="$*"$'\n'
}

ip() {
  local args="$*"
  case "$args" in
    "-4 -o rule show")
      printf '%s\n' "$mock_rules"
      ;;
    "-4 -o route show table main dev $mock_iface proto kernel scope link")
      printf '%s\n' "$mock_main_routes"
      ;;
    "-4 -o route show table $mock_table")
      printf '%s\n' "$mock_table_routes"
      ;;
    "-4 route replace $mock_network dev $mock_iface src $mock_address table $mock_table")
      replace_calls+=("$args")
      ;;
    "-4 route replace local $mock_address dev $mock_iface src $mock_address table $mock_table")
      replace_calls+=("$args")
      if [ "$mock_apply_routes" -eq 1 ]; then
        mock_table_routes="$mock_network dev $mock_iface scope link src $mock_address
local $mock_address dev $mock_iface scope host src $mock_address"
      fi
      ;;
    *)
      printf 'unexpected ip call: %s\n' "$args" >&2
      return 1
      ;;
  esac
}

reset_case() {
  mock_iface=${1:-rdma7}
  mock_table=${2:-42}
  mock_address=${3:-10.224.1.7}
  mock_network=${4:-10.224.0.0/12}
  mock_rules="0: from all lookup local
10: from all oif $mock_iface lookup $mock_table
11: from $mock_address lookup $mock_table
12: from all to $mock_address lookup $mock_table
32766: from all lookup main
32767: from all lookup default"
  mock_main_routes="$mock_network dev $mock_iface proto kernel scope link src $mock_address"
  mock_table_routes=""
  mock_apply_routes=1
  replace_calls=()
  logs=""
}

assert_equal() {
  local want=$1 got=$2 message=$3
  if [ "$want" != "$got" ]; then
    printf 'FAIL: %s: want %q, got %q\n' "$message" "$want" "$got" >&2
    exit 1
  fi
}

assert_contains() {
  local value=$1 substring=$2 message=$3
  if [[ "$value" != *"$substring"* ]]; then
    printf 'FAIL: %s: %q does not contain %q\n' "$message" "$value" "$substring" >&2
    exit 1
  fi
}

run_restore() {
  restore_rc=0
  restore_host_routes "$mock_iface" || restore_rc=$?
}

test_restores_rule_derived_table() {
  reset_case
  local rc
  run_restore
  rc=$restore_rc
  assert_equal 0 "$rc" "restore result"
  assert_equal 2 "${#replace_calls[@]}" "replace call count"
  assert_contains "${replace_calls[*]}" "table 42" "derived table"
  assert_contains "$logs" "table=42 network=10.224.0.0/12 routes=2" "success log"
  tests=$(( tests + 1 ))
}

test_skips_routes_that_are_ready() {
  reset_case
  mock_table_routes="$mock_network dev $mock_iface scope link src $mock_address
local $mock_address dev $mock_iface scope host src $mock_address"
  local rc
  run_restore
  rc=$restore_rc
  assert_equal 0 "$rc" "ready result"
  assert_equal 0 "${#replace_calls[@]}" "ready replace call count"
  tests=$(( tests + 1 ))
}

test_waits_for_host_prerequisites() {
  reset_case
  mock_main_routes=""
  local rc
  run_restore
  rc=$restore_rc
  assert_equal "$RESTORE_ROUTES_PENDING" "$rc" "missing main route result"
  assert_equal connected-main-route-missing "$RESTORE_WAIT_REASON" "missing main route reason"
  assert_equal 0 "${#replace_calls[@]}" "missing main route replace call count"
  tests=$(( tests + 1 ))
}

test_waits_for_policy_rule() {
  reset_case
  mock_rules=""
  local rc
  run_restore
  rc=$restore_rc
  assert_equal "$RESTORE_ROUTES_PENDING" "$rc" "missing policy rule result"
  assert_equal policy-rule-missing "$RESTORE_WAIT_REASON" "missing policy rule reason"
  assert_equal 0 "${#replace_calls[@]}" "missing policy rule replace call count"
  tests=$(( tests + 1 ))
}

test_detects_lost_move_race() {
  reset_case
  mock_apply_routes=0
  local rc
  run_restore
  rc=$restore_rc
  assert_equal 1 "$rc" "lost race result"
  assert_equal 2 "${#replace_calls[@]}" "lost race replace call count"
  assert_contains "$logs" "verification failed (table=42 routes=0)" "lost race log"
  tests=$(( tests + 1 ))
}

test_rejects_inconsistent_rules() {
  reset_case
  mock_rules="10: from all oif $mock_iface lookup $mock_table
10: from all oif $mock_iface lookup 43"
  local rc
  run_restore
  rc=$restore_rc
  assert_equal "$RESTORE_ROUTES_INVALID" "$rc" "inconsistent rule result"
  assert_equal multiple-policy-tables "$RESTORE_WAIT_REASON" "inconsistent rule reason"
  assert_contains "$logs" "found more than one policy table" "inconsistent rule log"
  tests=$(( tests + 1 ))
}

test_restores_16_pfs() {
  local rc index iface table address network
  local call_count=0
  for index in {0..15}; do
    iface="rdma$index"
    table=$(( 100 + index ))
    address="10.224.$index.1"
    network="10.224.$index.0/24"
    reset_case "$iface" "$table" "$address" "$network"
    rc=0
    restore_host_routes "$iface" "$mock_rules" || rc=$?
    assert_equal 0 "$rc" "$iface restore result"
    call_count=$(( call_count + ${#replace_calls[@]} ))
  done
  assert_equal 32 "$call_count" "16 PF replace call count"
  tests=$(( tests + 1 ))
}

test_restores_rule_derived_table
test_skips_routes_that_are_ready
test_waits_for_host_prerequisites
test_waits_for_policy_rule
test_detects_lost_move_race
test_rejects_inconsistent_rules
test_restores_16_pfs

if declare -p RESTORE_CHANGED 2>/dev/null | grep -q 'declare -x'; then
  printf 'FAIL: RESTORE_CHANGED is exported\n' >&2
  exit 1
fi
tests=$(( tests + 1 ))

reconciler="$script_dir/../files/rdma-pf-reconciler/rdma-pf-reconciler.sh"
monitor="$script_dir/../files/rdma-pf-reconciler/restore-host-routes-monitor.sh"
if ! grep -qF 'ip -4 -o monitor address route rule' "$monitor"; then
  printf 'FAIL: reconciler does not monitor host address, route, and rule events\n' >&2
  exit 1
fi
if grep -qF 'ip -o monitor link address' "$monitor"; then
  printf 'FAIL: route monitor still reacts to early host link events\n' >&2
  exit 1
fi
if ! grep -qF 'RESTORE_ROUTES_PENDING' "$monitor"; then
  printf 'FAIL: route monitor does not retry pending prerequisites\n' >&2
  exit 1
fi
if ! grep -qF 'route-monitor-heartbeat' "$monitor" ||
  ! grep -qF 'route-monitor-heartbeat' "$reconciler"; then
  printf 'FAIL: route monitor progress heartbeat is not checked end to end\n' >&2
  exit 1
fi
if ! grep -qF 'route-monitor-degraded' "$monitor" ||
  ! grep -qF 'route-monitor-degraded' "$reconciler"; then
  printf 'FAIL: degraded route state is not checked end to end\n' >&2
  exit 1
fi
if ! grep -qF 'cat /scripts/restore-host-routes-monitor.sh' "$reconciler"; then
  printf 'FAIL: reconciler does not start the host route monitor\n' >&2
  exit 1
fi
route_monitor_line=$(grep -n '^start_route_monitor$' "$reconciler" | cut -d: -f1)
auth_monitor_line=$(grep -n '^start_monitor$' "$reconciler" | cut -d: -f1)
if [ -z "$route_monitor_line" ] || [ -z "$auth_monitor_line" ] || [ "$route_monitor_line" -ge "$auth_monitor_line" ]; then
  printf 'FAIL: route monitor does not start before authentication monitoring\n' >&2
  exit 1
fi
tests=$(( tests + 7 ))

printf 'PASS: %d RDMA PF reconciler route tests\n' "$tests"
