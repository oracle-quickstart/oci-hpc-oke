#!/usr/bin/env bash
set -euo pipefail

# The drain bounds parse EPOCHREALTIME as integer microseconds, so pin the
# decimal separator.
LC_NUMERIC=C

# exec {fd}<, fractional `read -t`, and EPOCHREALTIME are all used below.
if [ "${BASH_VERSINFO[0]}" -lt 5 ]; then
  echo "rdma-pf-reconciler: bash 5 or newer required, found $BASH_VERSION"
  exit 1
fi

interval="${RDMA_PF_RECONCILER_INTERVAL:-10}"
health=/run/health

# Waited out after a link event, because the host sees a PF leave before Dranet
# has finished configuring it in the Pod. Reconciling sooner can start a
# supplicant on a down, unconfigured interface.
settle_ms="${RDMA_PF_RECONCILER_SETTLE_MS:-500}"

# A bad interval would otherwise reach `read -t` and CrashLoop every node.
if ! [ "$interval" -gt 0 ] 2>/dev/null; then
  echo "rdma-pf-reconciler: interval must be a positive integer, got '$interval'"
  exit 1
fi
if ! [ "$settle_ms" -ge 0 ] 2>/dev/null; then
  echo "rdma-pf-reconciler: settle must be a non-negative integer, got '$settle_ms'"
  exit 1
fi

mkdir -p "$health"

# The emptyDir outlives a container restart, but the supplicants this pod
# started do not. Stale markers would let the probes pass on the previous
# container's timestamps while nothing is running, so start from nothing and
# make this loop earn them back.
rm -f "$health"/alive "$health"/healthy "$health"/unauthorized "$health"/stats

# Written via rename so a probe never reads a half-written marker.
mark() {
  date +%s > "$health/.$1.tmp" && mv -f "$health/.$1.tmp" "$health/$1"
}

# Host netns link events. A PF moving into a Pod netns shows up here as a delete
# and its return as an add, so a pass can run when something actually changed.
# Opened once and held, so events arriving during a pass queue in the pipe
# instead of landing in a gap between passes.
events=-1
watching=0
monitor_restarts=0
monitor_initial_backoff=10
monitor_backoff=10
monitor_retry_at=0
monitor_started_at=0
wake=startup
drained=0

# The host mount namespace is entered too, because this image ships no iproute2.
# A failed nsenter surfaces as EOF on the first read, not as a failure here.
start_monitor() {
  if [ "$events" -ge 0 ]; then
    exec {events}<&- || true
  fi
  exec {events}< <(nsenter --target 1 --net --mount -- ip -o monitor link 2>/dev/null)
  watching=1
  monitor_started_at=$EPOCHSECONDS
}

# Drops to interval-only reconciliation and schedules a retry. Reading a closed
# fd returns instantly and forever, so the fd has to go with the feature.
lose_monitor() {
  if [ "$events" -ge 0 ]; then
    exec {events}<&- || true
  fi
  events=-1
  watching=0
  monitor_restarts=$(( monitor_restarts + 1 ))
  if [ $(( EPOCHSECONDS - monitor_started_at )) -ge 60 ]; then
    monitor_backoff=$monitor_initial_backoff
  fi
  monitor_retry_at=$(( EPOCHSECONDS + monitor_backoff ))
  echo "rdma-pf-reconciler: host link watch ended (loss #$monitor_restarts)," \
    "retrying in ${monitor_backoff}s, interval-only until then"
  monitor_backoff=$(( monitor_backoff * 2 ))
  if [ "$monitor_backoff" -gt 300 ]; then
    monitor_backoff=300
  fi
}

# Waits for a quiet period after the latest event. The extra 250ms and event
# limit bound the delay when a node has sustained link churn.
settle_events() {
  local n=0 rc=0 now deadline remaining settle_us wait_us wait_seconds
  [ "$settle_ms" -eq 0 ] && return

  settle_us=$(( settle_ms * 1000 ))
  now=${EPOCHREALTIME/./}
  deadline=$(( now + settle_us + 250000 ))

  while [ "$n" -lt 256 ]; do
    now=${EPOCHREALTIME/./}
    remaining=$(( deadline - now ))
    if [ "$remaining" -le 0 ]; then
      echo "rdma-pf-reconciler: link event settle reached its time limit"
      break
    fi

    wait_us=$settle_us
    if [ "$remaining" -lt "$wait_us" ]; then
      wait_us=$remaining
    fi
    printf -v wait_seconds '%d.%06d' "$(( wait_us / 1000000 ))" "$(( wait_us % 1000000 ))"

    rc=0
    read -r -t "$wait_seconds" -u "$events" _ || rc=$?
    if [ "$rc" -gt 128 ]; then
      if [ "$wait_us" -lt "$settle_us" ]; then
        echo "rdma-pf-reconciler: link event settle reached its time limit"
      fi
      break
    fi
    if [ "$rc" -ne 0 ]; then
      lose_monitor
      break
    fi
    n=$(( n + 1 ))
  done

  if [ "$n" -ge 256 ]; then
    echo "rdma-pf-reconciler: link event settle reached its event limit"
  fi
  drained=$n
}

# Keeps periodic passes running without delaying the next monitor retry.
fallback_wait() {
  local wait_seconds=$interval retry_seconds
  retry_seconds=$(( monitor_retry_at - EPOCHSECONDS ))
  if [ "$retry_seconds" -gt 0 ] && [ "$retry_seconds" -lt "$wait_seconds" ]; then
    wait_seconds=$retry_seconds
  fi
  sleep "$wait_seconds"
}

# Blocks until a link event, the interval expires, or the watch dies. The
# interval stays the ceiling, so an event that is missed or arrives during a pass
# costs latency and nothing else. Correctness stays with the pass.
wait_for_change() {
  local rc=0
  drained=0

  if [ "$watching" -eq 0 ]; then
    if [ "$EPOCHSECONDS" -ge "$monitor_retry_at" ]; then
      start_monitor
      echo "rdma-pf-reconciler: host link watch restarted"
    else
      wake=fallback
      fallback_wait
      return
    fi
  fi

  read -r -t "$interval" -u "$events" _ || rc=$?
  if [ "$rc" -gt 128 ]; then
    # Timed out. This is the periodic pass.
    wake=timeout
    return
  fi
  if [ "$rc" -ne 0 ]; then
    lose_monitor
    wake=fallback
    fallback_wait
    return
  fi

  wake=event
  settle_events
}

route_monitor_pid=0
route_monitor_restarts=0
route_monitor_started_at=0
route_monitor_heartbeat_age=-1
route_monitor_heartbeat=/run/oke-rdma-pf-reconciler/route-monitor-heartbeat
route_monitor_degraded_file=/run/oke-rdma-pf-reconciler/route-monitor-degraded
route_monitor_degraded=0
route_monitor_stale=$(( interval * 2 ))
if [ "$route_monitor_stale" -lt 20 ]; then
  route_monitor_stale=20
fi

start_route_monitor() {
  nsenter --target 1 --mount -- rm -f "$route_monitor_heartbeat" 2>/dev/null || true
  {
    cat /scripts/restore-host-routes.sh
    cat /scripts/restore-host-routes-monitor.sh
  } | nsenter --target 1 --net --mount --uts --ipc -- setsid /bin/bash &
  route_monitor_pid=$!
  route_monitor_started_at=$EPOCHSECONDS
}

stop_route_monitor() {
  if [ "$route_monitor_pid" -gt 0 ]; then
    kill -TERM -- "-$route_monitor_pid" 2>/dev/null || true
    for _ in {1..10}; do
      kill -0 "$route_monitor_pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$route_monitor_pid" 2>/dev/null; then
      kill -KILL -- "-$route_monitor_pid" 2>/dev/null || true
    fi
    wait "$route_monitor_pid" 2>/dev/null || true
    route_monitor_pid=0
  fi
}

route_monitor_progressing() {
  local heartbeat
  route_monitor_heartbeat_age=-1
  if heartbeat=$(nsenter --target 1 --mount -- cat "$route_monitor_heartbeat" 2>/dev/null) &&
    [[ "$heartbeat" =~ ^[0-9]+$ ]]; then
    route_monitor_heartbeat_age=$(( EPOCHSECONDS - heartbeat ))
    [ "$route_monitor_heartbeat_age" -ge 0 ] &&
      [ "$route_monitor_heartbeat_age" -le "$route_monitor_stale" ] && return 0
  fi
  [ $(( EPOCHSECONDS - route_monitor_started_at )) -lt 5 ]
}

check_route_monitor() {
  local reason
  if ! kill -0 "$route_monitor_pid" 2>/dev/null; then
    reason="stopped"
  elif ! route_monitor_progressing; then
    if [ "$route_monitor_heartbeat_age" -ge 0 ]; then
      reason="made no progress for ${route_monitor_heartbeat_age}s"
    else
      reason="has no progress heartbeat"
    fi
  else
    return 0
  fi

  route_monitor_restarts=$(( route_monitor_restarts + 1 ))
  echo "rdma-pf-reconciler: host route event watch $reason, restarting"
  rm -f "$health/healthy"
  stop_route_monitor
  start_route_monitor
  return 1
}

check_route_monitor_degraded() {
  route_monitor_degraded=0
  if nsenter --target 1 --mount -- test -s "$route_monitor_degraded_file"; then
    route_monitor_degraded=1
    rm -f "$health/healthy"
  fi
}

trap stop_route_monitor EXIT
trap 'exit 0' INT TERM

start_route_monitor
start_monitor

while true; do
  pass_start=${EPOCHREALTIME/./}
  route_monitor_ok=1
  check_route_monitor || route_monitor_ok=0

  # Streamed over stdin so nothing is staged on the host filesystem.
  # || rc=$? stops set -e exiting the loop on a nonzero pass.
  rc=0
  nsenter --target 1 --net --mount --uts --ipc --pid -- /bin/bash < /scripts/reconcile-auth.sh || rc=$?
  pass_ms=$(( ( ${EPOCHREALTIME/./} - pass_start ) / 1000 ))

  check_route_monitor || route_monitor_ok=0
  check_route_monitor_degraded

  if [ "$route_monitor_ok" -eq 1 ] && [ "$route_monitor_degraded" -eq 0 ]; then
    case $rc in
      0)
        mark healthy
        rm -f "$health/unauthorized"
        ;;
      # Fabric rejected a port. Keep this pod Ready, an outage hits every node.
      2)
        mark healthy
        mark unauthorized
        ;;
    esac
  fi
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    echo "rdma-pf-reconciler: authentication reconciliation failed"
  fi
  # Liveness only, not readiness. A restart kills this pod's supplicants.
  mark alive

  # Machine-readable counters, renamed so a reader never sees a partial
  # file. pass_ms tracks claimed PF count and the container's CPU limit.
  {
    echo "wake=$wake"
    echo "pass_ms=$pass_ms"
    echo "pass_rc=$rc"
    echo "route_monitor_restarts=$route_monitor_restarts"
    echo "route_monitor_running=$route_monitor_ok"
    echo "route_monitor_degraded=$route_monitor_degraded"
    echo "route_monitor_heartbeat_age=$route_monitor_heartbeat_age"
    echo "drained_events=$drained"
    echo "monitor_restarts=$monitor_restarts"
    echo "watching=$watching"
  } > "$health/.stats.tmp" && mv -f "$health/.stats.tmp" "$health/stats"

  # Quiet on an idle node: only log a pass that was triggered by a change or did
  # not come back clean.
  if [ "$wake" != timeout ] || [ "$rc" -ne 0 ]; then
    echo "rdma-pf-reconciler: wake=$wake pass_ms=$pass_ms rc=$rc" \
      "drained=$drained watching=$watching"
  fi

  wait_for_change
done
