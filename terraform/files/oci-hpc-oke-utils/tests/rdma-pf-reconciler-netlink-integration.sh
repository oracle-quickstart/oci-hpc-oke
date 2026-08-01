#!/usr/bin/env bash
set -euo pipefail

LC_NUMERIC=C

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
routes="$script_dir/../files/rdma-pf-reconciler/restore-host-routes.sh"
monitor="$script_dir/../files/rdma-pf-reconciler/restore-host-routes-monitor.sh"

if [ "$(uname -s)" != Linux ]; then
  echo "SKIP: real netlink test requires Linux"
  exit 0
fi
if [ "${BASH_VERSINFO[0]}" -lt 5 ]; then
  echo "FAIL: real netlink test requires Bash 5 or newer" >&2
  exit 1
fi
for tool in ip setsid unshare; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "FAIL: real netlink test requires $tool" >&2
    exit 1
  fi
done

if [ "${1:-}" != --inside ]; then
  if [ "$(id -u)" -eq 0 ]; then
    exec unshare --net -- /bin/bash "$0" --inside
  fi
  if command -v sudo >/dev/null 2>&1; then
    exec sudo unshare --net -- /bin/bash "$0" --inside
  fi
  echo "SKIP: real netlink test requires root or sudo"
  exit 0
fi

state_dir=$(mktemp -d /tmp/rdma-pf-reconciler-netlink.XXXXXX)
monitor_pid=0

cleanup() {
  if [ "$monitor_pid" -gt 0 ]; then
    kill -TERM -- "-$monitor_pid" 2>/dev/null || true
    wait "$monitor_pid" 2>/dev/null || true
  fi
  rm -rf "$state_dir"
}
trap cleanup EXIT

interfaces=()
for index in {0..15}; do
  iface="rdma$index"
  table=$(( 10 + index ))
  interfaces+=("$iface")
  ip link add "$iface" type dummy
  ip link set "$iface" up
  # A new network namespace has no allocated custom FIB tables. OCA tables
  # already exist, so keep one unrelated route here to model that state.
  ip -4 route add blackhole "192.0.$index.0/24" table "$table"
  if [ "$index" -ne 0 ]; then
    ip -4 rule add priority "$(( 100 + index ))" oif "$iface" table "$table"
  fi
done

{
  cat "$routes"
  cat "$monitor"
} | RDMA_PF_RECONCILER_STATE_DIR="$state_dir" \
  RDMA_PF_RECONCILER_INTERFACES="${interfaces[*]}" \
  RDMA_PF_RECONCILER_INTERVAL=10 \
  setsid /bin/bash > "$state_dir/monitor.log" 2>&1 &
monitor_pid=$!

for _ in {1..100}; do
  [ -s "$state_dir/route-monitor-heartbeat" ] && break
  kill -0 "$monitor_pid" 2>/dev/null || {
    cat "$state_dir/monitor.log" >&2
    echo "FAIL: route monitor exited before becoming ready" >&2
    exit 1
  }
  sleep 0.02
done
if [ ! -s "$state_dir/route-monitor-heartbeat" ]; then
  echo "FAIL: route monitor did not write its progress heartbeat" >&2
  exit 1
fi
# The process substitution can write the heartbeat before ip has bound its
# netlink socket.
sleep 0.1

start_us=${EPOCHREALTIME/./}

# Trigger the first address event before its policy rule exists. The event
# retry must observe the rule added below without waiting for the fallback.
ip -4 address add 10.224.0.1/24 dev rdma0
sleep 0.3
ip -4 rule add priority 100 oif rdma0 table 10

for index in {1..15}; do
  ip -4 address add "10.224.$index.1/24" dev "rdma$index"
done

all_routes_ready() {
  local index table count
  for index in {0..15}; do
    table=$(( 10 + index ))
    count=$(ip -4 -o route show table "$table" | grep -c "dev rdma$index" || true)
    [ "$count" -eq 2 ] || return 1
  done
}

deadline_us=$(( start_us + 5000000 ))
while [ "${EPOCHREALTIME/./}" -lt "$deadline_us" ]; do
  all_routes_ready && break
  sleep 0.05
done
if ! all_routes_ready; then
  cat "$state_dir/monitor.log" >&2
  echo "FAIL: real netlink route restoration exceeded 5000ms" >&2
  exit 1
fi

elapsed_ms=$(( ( ${EPOCHREALTIME/./} - start_us ) / 1000 ))
unique_restore_count=$(awk '/restored host policy routes/ {gsub(":", "", $2); print $2}' \
  "$state_dir/monitor.log" | sort -u | wc -l)
if [ "$unique_restore_count" -ne 16 ]; then
  cat "$state_dir/monitor.log" >&2
  echo "FAIL: expected 16 interfaces in route logs, found $unique_restore_count" >&2
  exit 1
fi

# A policy route can disappear after the address event that first restored it.
# The route event must repair it before the ten-second fallback pass.
late_delete_start_us=${EPOCHREALTIME/./}
ip -4 route del 10.224.7.0/24 dev rdma7 table 17
late_delete_deadline_us=$(( late_delete_start_us + 2000000 ))
while [ "${EPOCHREALTIME/./}" -lt "$late_delete_deadline_us" ]; do
  count=$(ip -4 -o route show table 17 | grep -c "dev rdma7" || true)
  [ "$count" -eq 2 ] && break
  sleep 0.02
done
count=$(ip -4 -o route show table 17 | grep -c "dev rdma7" || true)
if [ "$count" -ne 2 ]; then
  cat "$state_dir/monitor.log" >&2
  echo "FAIL: route deletion was not restored before the fallback interval" >&2
  exit 1
fi
late_delete_elapsed_ms=$(( ( ${EPOCHREALTIME/./} - late_delete_start_us ) / 1000 ))

# A rule event must finish recovery after the route event's retry budget ends.
ip -4 route del 10.224.8.0/24 dev rdma8 table 18
ip -4 rule del priority 108 oif rdma8 table 18
sleep 1.2
rule_event_start_us=${EPOCHREALTIME/./}
ip -4 rule add priority 108 oif rdma8 table 18
rule_event_deadline_us=$(( rule_event_start_us + 2000000 ))
while [ "${EPOCHREALTIME/./}" -lt "$rule_event_deadline_us" ]; do
  count=$(ip -4 -o route show table 18 | grep -c "dev rdma8" || true)
  [ "$count" -eq 2 ] && break
  sleep 0.02
done
count=$(ip -4 -o route show table 18 | grep -c "dev rdma8" || true)
if [ "$count" -ne 2 ]; then
  cat "$state_dir/monitor.log" >&2
  echo "FAIL: rule event did not restore routes before the fallback interval" >&2
  exit 1
fi
rule_event_elapsed_ms=$(( ( ${EPOCHREALTIME/./} - rule_event_start_us ) / 1000 ))

printf 'PASS: real netlink restored 16 PF tables in %dms, a deleted route in %dms, and routes after a rule event in %dms\n' \
  "$elapsed_ms" "$late_delete_elapsed_ms" "$rule_event_elapsed_ms"
