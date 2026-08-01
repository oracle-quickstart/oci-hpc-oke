#!/usr/bin/env bash
set -uo pipefail

LC_NUMERIC=C

# Everything below assumes host paths, so bail out if nsenter did not work.
if [ "$(readlink /proc/self/ns/mnt 2>/dev/null)" != "$(readlink /proc/1/ns/mnt 2>/dev/null)" ]; then
  echo "rdma-pf-reconciler: route monitor is not in the host mount namespace"
  exit 1
fi
if [ "${BASH_VERSINFO[0]}" -lt 5 ]; then
  echo "rdma-pf-reconciler: route monitor requires bash 5 or newer"
  exit 1
fi

STATE_DIR=${RDMA_PF_RECONCILER_STATE_DIR:-/run/oke-rdma-pf-reconciler}
HEARTBEAT="$STATE_DIR/route-monitor-heartbeat"
DEGRADED="$STATE_DIR/route-monitor-degraded"
PENDING_GRACE=90
PENDING_STATE_EXPIRED=2
interval=${RDMA_PF_RECONCILER_INTERVAL:-10}

log() { echo "rdma-pf-reconciler: $*"; }

if ! command -v ip >/dev/null 2>&1; then
  log "required tool ip not found, route monitor exiting"
  exit 1
fi
if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
  log "cannot write $STATE_DIR, route monitor exiting"
  exit 1
fi

mark_progress() {
  date +%s > "$HEARTBEAT.tmp" && mv -f "$HEARTBEAT.tmp" "$HEARTBEAT"
}

ifaces=()
if [ -n "${RDMA_PF_RECONCILER_INTERFACES:-}" ]; then
  read -r -a ifaces <<< "$RDMA_PF_RECONCILER_INTERFACES"
else
  for unit in /etc/systemd/system/wpa_supplicant-wired@*.service; do
    [ -e "$unit" ] || continue
    unit=${unit##*/wpa_supplicant-wired@}
    unit=${unit%.service}
    [ -n "$unit" ] && ifaces+=("$unit")
  done
fi

if [ ${#ifaces[@]} -eq 0 ]; then
  if ! rm -f "$DEGRADED"; then
    log "cannot remove route monitor state $DEGRADED"
    exit 1
  fi
  while true; do
    mark_progress
    sleep "$interval"
  done
fi

interface_exists() {
  if [ -n "${RDMA_PF_RECONCILER_INTERFACES:-}" ]; then
    ip link show dev "$1" >/dev/null 2>&1
  else
    [ -e "/sys/class/net/$1" ]
  fi
}

write_state_file() {
  local path=$1 value=$2
  local tmp="$path.$BASHPID.tmp"
  if ! printf '%s\n' "$value" > "$tmp"; then
    rm -f "$tmp" 2>/dev/null || true
    log "cannot write route monitor state $path"
    return 1
  fi
  if ! mv -f "$tmp" "$path"; then
    rm -f "$tmp" 2>/dev/null || true
    log "cannot replace route monitor state $path"
    return 1
  fi
}

remove_state_file() {
  local path=$1
  [ ! -e "$path" ] || rm -f "$path" || {
    log "cannot remove route monitor state $path"
    return 1
  }
}

pending_reason_text() {
  case "$1" in
    policy-rule-missing) printf '%s' "output-interface policy rule is missing" ;;
    connected-main-route-missing) printf '%s' "main-table connected route is missing" ;;
    multiple-policy-tables) printf '%s' "more than one policy table matches the interface" ;;
    multiple-connected-routes) printf '%s' "more than one main-table connected route matches the interface" ;;
    policy-rule-read-failed) printf '%s' "IPv4 policy rules could not be read" ;;
    connected-main-route-read-failed) printf '%s' "main-table connected routes could not be read" ;;
    policy-table-read-failed) printf '%s' "the policy table could not be read" ;;
    connected-route-replace-failed) printf '%s' "the connected route could not be restored" ;;
    local-route-replace-failed) printf '%s' "the local route could not be restored" ;;
    policy-table-verify-read-failed) printf '%s' "the restored policy table could not be read" ;;
    route-verification-failed) printf '%s' "restored routes did not pass verification" ;;
    *) printf '%s' "$1" ;;
  esac
}

refresh_degraded() {
  local iface reason content="" current=""
  for iface in "${ifaces[@]}"; do
    [ -e "$STATE_DIR/$iface.routes-failed" ] || continue
    if ! reason=$(cat "$STATE_DIR/$iface.routes-failed"); then
      log "cannot read route monitor state $STATE_DIR/$iface.routes-failed"
      return 1
    fi
    [ -n "$reason" ] || continue
    content+="$iface $reason"$'\n'
  done
  content=${content%$'\n'}

  if [ -z "$content" ]; then
    remove_state_file "$DEGRADED"
    return
  fi
  if [ -e "$DEGRADED" ]; then
    if ! current=$(cat "$DEGRADED"); then
      log "cannot read route monitor state $DEGRADED"
      return 1
    fi
  fi
  [ "$current" = "$content" ] || write_state_file "$DEGRADED" "$content"
}

clear_failure() {
  remove_state_file "$STATE_DIR/$1.routes-failed" || return
  refresh_degraded
}

mark_failure() {
  local iface=$1 reason=$2 current="" text
  if [ -e "$STATE_DIR/$iface.routes-failed" ]; then
    if ! current=$(cat "$STATE_DIR/$iface.routes-failed"); then
      log "cannot read route monitor state $STATE_DIR/$iface.routes-failed"
      return 1
    fi
  fi
  if [ "$current" != "$reason" ]; then
    write_state_file "$STATE_DIR/$iface.routes-failed" "$reason" || return
    text=$(pending_reason_text "$reason")
    log "$iface: host routes were not ready within ${PENDING_GRACE}s ($text)"
  fi
  refresh_degraded
}

clear_pending() {
  remove_state_file "$STATE_DIR/$1.routes-pending"
}

clear_interface_state() {
  clear_pending "$1" || return
  clear_failure "$1"
}

record_pending() {
  local iface=$1 reason=$2 file line="" since="" previous_reason="" now
  PENDING_STARTED=0
  now=$(date +%s)
  file="$STATE_DIR/$iface.routes-pending"
  if [ -e "$file" ]; then
    if ! line=$(cat "$file"); then
      log "cannot read route monitor state $file"
      return 1
    fi
    read -r since previous_reason <<< "$line"
  fi

  if ! [[ "$since" =~ ^[0-9]+$ ]]; then
    write_state_file "$file" "$now $reason" || return
    PENDING_STARTED=1
    return 0
  fi
  if [ "$previous_reason" != "$reason" ]; then
    write_state_file "$file" "$since $reason" || return
    PENDING_STARTED=1
  fi
  if [ $(( now - since )) -ge "$PENDING_GRACE" ]; then
    return "$PENDING_STATE_EXPIRED"
  fi
  return 0
}

restore_event_iface() {
  local iface=$1 rules=${2-} source=${3:-netlink-event}
  local rc=0 deadline start elapsed_ms reason text pending_rc
  start=${EPOCHREALTIME/./}
  deadline=$(( start + 1000000 ))

  if ! interface_exists "$iface"; then
    clear_interface_state "$iface"
    return
  fi

  if [ "$#" -gt 1 ]; then
    restore_host_routes "$iface" "$rules" || rc=$?
  else
    restore_host_routes "$iface" || rc=$?
  fi

  # Rules, connected routes, and route replacement can all race the move.
  # Retry them within the same one-second event budget.
  if [ "$rc" -eq 1 ] || [ "$rc" -eq "$RESTORE_ROUTES_PENDING" ]; then
    while { [ "$rc" -eq 1 ] || [ "$rc" -eq "$RESTORE_ROUTES_PENDING" ]; } &&
      [ "$deadline" -gt "${EPOCHREALTIME/./}" ]; do
      interface_exists "$iface" || break
      sleep 0.1
      rc=0
      restore_host_routes "$iface" || rc=$?
    done
  fi

  if [ "$rc" -eq 0 ]; then
    clear_interface_state "$iface" || return
    if [ "$RESTORE_CHANGED" -eq 1 ]; then
      elapsed_ms=$(( ( ${EPOCHREALTIME/./} - start ) / 1000 ))
      log "$iface: $source route restore completed in ${elapsed_ms}ms"
    fi
    return 0
  fi
  if ! interface_exists "$iface"; then
    clear_interface_state "$iface"
    return
  fi

  reason=${RESTORE_WAIT_REASON:-restore-error}
  pending_rc=0
  record_pending "$iface" "$reason" || pending_rc=$?
  case "$pending_rc" in
    0)
      if [ "$PENDING_STARTED" -eq 1 ]; then
        text=$(pending_reason_text "$reason")
        log "$iface: waiting for host routes ($text)"
      fi
      clear_failure "$iface"
      ;;
    "$PENDING_STATE_EXPIRED")
      mark_failure "$iface" "$reason"
      ;;
    *)
      return 1
      ;;
  esac
}

restore_all_host_ifaces() {
  local source=${1:-fallback} iface rules fail=0
  if ! rules=$(ip -4 -o rule show); then
    log "cannot read IPv4 policy rules"
    return 1
  fi
  for iface in "${ifaces[@]}"; do
    restore_event_iface "$iface" "$rules" "$source" || fail=1
  done
  return "$fail"
}

restore_netlink_event() {
  local event=$1 iface

  case " $event " in
    *" inet "*)
      case "$event" in
        Deleted*) return 0 ;;
      esac
      ;;
    *" dev "*|*" oif "*) ;;
    *) return 0 ;;
  esac

  for iface in "${ifaces[@]}"; do
    case " $event " in
      *" $iface:"*|*" $iface@"*|*" $iface "*)
        restore_event_iface "$iface" || return 1
        return 0
        ;;
    esac
  done
}

# OCA adds the host address after moving and configuring the PF.
refresh_degraded || exit 1
events=-1
exec {events}< <(ip -4 -o monitor address route rule 2>/dev/null)

# The event watch is already open, so this startup fallback cannot miss an
# event even if the scan overlaps a PF move.
(restore_all_host_ifaces startup || log "initial host route restore failed") &
startup_restore_pid=$!

stop_startup_restore() {
  kill "$startup_restore_pid" 2>/dev/null || true
  wait "$startup_restore_pid" 2>/dev/null || true
  rm -f "$HEARTBEAT" "$HEARTBEAT.tmp"
}

trap stop_startup_restore EXIT
trap 'exit 0' INT TERM

while true; do
  mark_progress
  event=""
  event_rc=0
  read -r -t "$interval" -u "$events" event || event_rc=$?
  if [ "$event_rc" -gt 128 ]; then
    restore_all_host_ifaces || exit 1
    continue
  fi
  if [ "$event_rc" -ne 0 ]; then
    log "host route event watch ended"
    exit 1
  fi
  restore_netlink_event "$event" || exit 1
done
