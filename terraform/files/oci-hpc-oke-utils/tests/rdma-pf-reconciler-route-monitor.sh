#!/usr/bin/env bash
set -euo pipefail

LC_NUMERIC=C

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
monitor="$script_dir/../files/rdma-pf-reconciler/restore-host-routes-monitor.sh"
reconciler="$script_dir/../files/rdma-pf-reconciler/rdma-pf-reconciler.sh"
tests=0
logs=""

load_function() {
  local name=$1 file=${2:-$monitor} body
  body=$(sed -n "/^${name}()/,/^}/p" "$file")
  if [ -z "$body" ]; then
    printf 'FAIL: function %s not found\n' "$name" >&2
    exit 1
  fi
  eval "$body"
}

load_function write_state_file
load_function remove_state_file
load_function pending_reason_text
load_function refresh_degraded
load_function clear_failure
load_function mark_failure
load_function clear_pending
load_function clear_interface_state
load_function record_pending
load_function restore_event_iface
load_function restore_all_host_ifaces
load_function restore_netlink_event
load_function check_route_monitor_degraded "$reconciler"

test_root=$(mktemp -d /tmp/rdma-pf-reconciler-monitor.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

# Loaded production functions consume this value.
# shellcheck disable=SC2034
RESTORE_ROUTES_PENDING=3
RESTORE_ROUTES_INVALID=4
PENDING_STATE_EXPIRED=2
PENDING_GRACE=90
STATE_DIR=""
DEGRADED=""
ifaces=()
mock_mode=success
mock_rules="10: from all oif rdma0 lookup 10"
restore_calls=0
restore_arg_counts=()
RESTORE_WAIT_REASON=""
RESTORE_CHANGED=0

log() {
  logs+="$*"$'\n'
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

new_case() {
  STATE_DIR=$(mktemp -d "$test_root/case.XXXXXX")
  DEGRADED="$STATE_DIR/route-monitor-degraded"
  ifaces=(rdma0 rdma1)
  logs=""
  restore_calls=0
  restore_arg_counts=()
  RESTORE_WAIT_REASON=""
  RESTORE_CHANGED=0
  mock_mode=success
}

interface_exists() {
  return 0
}

ip() {
  if [ "$*" = "-4 -o rule show" ]; then
    printf '%s\n' "$mock_rules"
    return 0
  fi
  printf 'unexpected ip call: %s\n' "$*" >&2
  return 1
}

nsenter() {
  while [ "$1" != -- ]; do
    shift
  done
  shift
  "$@"
}

restore_host_routes() {
  local iface=$1
  restore_calls=$(( restore_calls + 1 ))
  restore_arg_counts+=("$#")
  # restore_event_iface reads these outputs.
  # shellcheck disable=SC2034
  RESTORE_CHANGED=0
  RESTORE_WAIT_REASON=""

  case "$mock_mode" in
    transient-once)
      if [ "$restore_calls" -eq 1 ]; then
        RESTORE_WAIT_REASON=route-verification-failed
        return 1
      fi
      ;;
    invalid)
      RESTORE_WAIT_REASON=multiple-policy-tables
      return "$RESTORE_ROUTES_INVALID"
      ;;
    per-interface)
      if [ "$iface" = rdma0 ]; then
        # shellcheck disable=SC2034
        RESTORE_WAIT_REASON=multiple-policy-tables
        return "$RESTORE_ROUTES_INVALID"
      fi
      ;;
  esac
  return 0
}

test_pending_reasons_are_distinct() {
  local policy_text connected_text
  policy_text=$(pending_reason_text policy-rule-missing)
  connected_text=$(pending_reason_text connected-main-route-missing)
  assert_equal "output-interface policy rule is missing" "$policy_text" "policy pending text"
  assert_equal "main-table connected route is missing" "$connected_text" "connected route pending text"
  tests=$(( tests + 1 ))
}

test_pending_reason_change_resets_timer() {
  new_case
  local rc=0 state

  printf '%s\n' "1 policy-rule-missing" > "$STATE_DIR/rdma0.routes-pending"
  record_pending rdma0 connected-main-route-missing || rc=$?
  assert_equal 0 "$rc" "changed pending reason result"
  assert_equal 1 "$PENDING_STARTED" "changed pending reason starts timer"
  state=$(cat "$STATE_DIR/rdma0.routes-pending")
  assert_contains "$state" " connected-main-route-missing" "changed pending state"

  printf '%s\n' "$(( $(date +%s) - PENDING_GRACE )) connected-main-route-missing" \
    > "$STATE_DIR/rdma0.routes-pending"
  rc=0
  record_pending rdma0 connected-main-route-missing || rc=$?
  assert_equal "$PENDING_STATE_EXPIRED" "$rc" "expired pending result"
  tests=$(( tests + 1 ))
}

test_state_write_failure_is_not_a_timeout() {
  new_case
  local saved_state_dir=$STATE_DIR rc=0
  STATE_DIR=/proc/rdma-pf-reconciler-monitor-test
  record_pending rdma0 policy-rule-missing 2>/dev/null || rc=$?
  STATE_DIR=$saved_state_dir

  assert_equal 1 "$rc" "state write failure result"
  assert_contains "$logs" "cannot write route monitor state" "state write failure log"
  if [[ "$logs" == *"not ready within"* ]]; then
    printf 'FAIL: state write failure was reported as a route timeout\n' >&2
    exit 1
  fi
  tests=$(( tests + 1 ))
}

test_transient_retry_refreshes_rules() {
  new_case
  ifaces=(rdma0)
  mock_mode=transient-once
  local rc=0
  restore_event_iface rdma0 "cached rules" fallback || rc=$?

  assert_equal 0 "$rc" "transient retry result"
  assert_equal 2 "$restore_calls" "transient retry count"
  assert_equal "2 1" "${restore_arg_counts[*]}" "retry argument counts"
  tests=$(( tests + 1 ))
}

test_invalid_policy_state_is_not_retried() {
  new_case
  # Loaded production functions read this array.
  # shellcheck disable=SC2034
  ifaces=(rdma0)
  mock_mode=invalid
  local rc=0 state
  restore_event_iface rdma0 "cached rules" fallback || rc=$?

  assert_equal 0 "$rc" "invalid policy state result"
  assert_equal 1 "$restore_calls" "invalid policy retry count"
  state=$(cat "$STATE_DIR/rdma0.routes-pending")
  assert_contains "$state" " multiple-policy-tables" "invalid policy pending state"
  tests=$(( tests + 1 ))
}

test_failed_pf_does_not_stop_monitor_pass() {
  new_case
  mock_mode=per-interface
  printf '%s\n' "$(( $(date +%s) - PENDING_GRACE )) multiple-policy-tables" \
    > "$STATE_DIR/rdma0.routes-pending"
  local rc=0 failure_logs

  restore_all_host_ifaces fallback || rc=$?
  assert_equal 0 "$rc" "degraded pass result"
  assert_equal 2 "$restore_calls" "both PFs were checked"
  assert_contains "$(cat "$DEGRADED")" "rdma0 multiple-policy-tables" "degraded marker"

  restore_all_host_ifaces fallback || rc=$?
  failure_logs=$(grep -c "rdma0: host routes were not ready" <<< "$logs" || true)
  assert_equal 1 "$failure_logs" "persistent PF failure log count"

  mock_mode=success
  restore_all_host_ifaces fallback || rc=$?
  assert_equal 0 "$rc" "recovered pass result"
  if [ -e "$DEGRADED" ]; then
    printf 'FAIL: degraded marker remained after PF recovery\n' >&2
    exit 1
  fi
  tests=$(( tests + 1 ))
}

test_parent_marks_degraded_without_restart() {
  new_case
  local health="$STATE_DIR/health"
  mkdir -p "$health"
  printf '%s\n' ready > "$health/healthy"
  printf '%s\n' "rdma0 multiple-policy-tables" > "$DEGRADED"
  # Loaded production functions read these values.
  # shellcheck disable=SC2034
  route_monitor_degraded_file=$DEGRADED
  route_monitor_degraded=0

  check_route_monitor_degraded
  assert_equal 1 "$route_monitor_degraded" "parent degraded state"
  if [ -e "$health/healthy" ]; then
    printf 'FAIL: parent kept the healthy marker while routes were degraded\n' >&2
    exit 1
  fi

  rm -f "$DEGRADED"
  check_route_monitor_degraded
  assert_equal 0 "$route_monitor_degraded" "parent recovered state"
  tests=$(( tests + 1 ))
}

test_route_and_rule_events_trigger_restore() {
  new_case
  ifaces=(rdma0)

  restore_netlink_event "Deleted 10.224.0.0/12 dev rdma0 scope link table 10"
  assert_equal 1 "$restore_calls" "deleted route event restore count"

  restore_netlink_event "100: from all oif rdma0 lookup 10"
  assert_equal 2 "$restore_calls" "rule event restore count"
  tests=$(( tests + 1 ))
}

test_deleted_address_and_unrelated_events_are_ignored() {
  new_case
  # Loaded production functions read this array.
  # shellcheck disable=SC2034
  ifaces=(rdma0)

  restore_netlink_event "Deleted 2: rdma0    inet 10.224.0.1/24 scope global rdma0"
  restore_netlink_event "10.225.0.0/16 dev eth0 scope link"
  assert_equal 0 "$restore_calls" "ignored netlink event restore count"
  tests=$(( tests + 1 ))
}

test_pending_reasons_are_distinct
test_pending_reason_change_resets_timer
test_state_write_failure_is_not_a_timeout
test_transient_retry_refreshes_rules
test_invalid_policy_state_is_not_retried
test_failed_pf_does_not_stop_monitor_pass
test_parent_marks_degraded_without_restart
test_route_and_rule_events_trigger_restore
test_deleted_address_and_unrelated_events_are_ignored

printf 'PASS: %d RDMA PF reconciler route monitor tests\n' "$tests"
