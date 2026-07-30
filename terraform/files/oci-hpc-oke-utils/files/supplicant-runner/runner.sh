#!/usr/bin/env bash
set -euo pipefail

# The drain bounds parse EPOCHREALTIME as integer microseconds, so pin the
# decimal separator.
LC_NUMERIC=C

# exec {fd}<, fractional `read -t`, and EPOCHREALTIME are all used below.
if [ "${BASH_VERSINFO[0]}" -lt 5 ]; then
  echo "supplicant-runner: bash 5 or newer required, found $BASH_VERSION"
  exit 1
fi

interval="${SUPPLICANT_RUNNER_INTERVAL:-10}"
health=/run/health

# Waited out after a link event, because the host sees a PF leave before Dranet
# has finished configuring it in the Pod. Reconciling sooner can start a
# supplicant on a down, unconfigured interface.
settle_ms="${SUPPLICANT_RUNNER_SETTLE_MS:-500}"

# A bad interval would otherwise reach `read -t` and CrashLoop every node.
if ! [ "$interval" -gt 0 ] 2>/dev/null; then
  echo "supplicant-runner: interval must be a positive integer, got '$interval'"
  exit 1
fi
if ! [ "$settle_ms" -ge 0 ] 2>/dev/null; then
  echo "supplicant-runner: settle must be a non-negative integer, got '$settle_ms'"
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
  echo "supplicant-runner: host link watch ended (loss #$monitor_restarts)," \
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
      echo "supplicant-runner: link event settle reached its time limit"
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
        echo "supplicant-runner: link event settle reached its time limit"
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
    echo "supplicant-runner: link event settle reached its event limit"
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
      echo "supplicant-runner: host link watch restarted"
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

start_monitor

while true; do
  pass_start=${EPOCHREALTIME/./}
  # Streamed over stdin so nothing is staged on the host filesystem.
  # || rc=$? stops set -e exiting the loop on a nonzero pass.
  rc=0
  nsenter --target 1 --net --mount --uts --ipc --pid -- /bin/bash < /scripts/supplicant-runner.sh || rc=$?
  pass_ms=$(( ( ${EPOCHREALTIME/./} - pass_start ) / 1000 ))

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
    *)
      echo "supplicant-runner: reconciliation pass failed"
      ;;
  esac
  # Liveness only, not readiness. A restart kills this pod's supplicants.
  mark alive

  # Machine-readable counters, renamed so a reader never sees a partial
  # file. pass_ms tracks claimed PF count and the container's CPU limit.
  {
    echo "wake=$wake"
    echo "pass_ms=$pass_ms"
    echo "pass_rc=$rc"
    echo "drained_events=$drained"
    echo "monitor_restarts=$monitor_restarts"
    echo "watching=$watching"
  } > "$health/.stats.tmp" && mv -f "$health/.stats.tmp" "$health/stats"

  # Quiet on an idle node: only log a pass that was triggered by a change or did
  # not come back clean.
  if [ "$wake" != timeout ] || [ "$rc" -ne 0 ]; then
    echo "supplicant-runner: wake=$wake pass_ms=$pass_ms rc=$rc" \
      "drained=$drained watching=$watching"
  fi

  wait_for_change
done
