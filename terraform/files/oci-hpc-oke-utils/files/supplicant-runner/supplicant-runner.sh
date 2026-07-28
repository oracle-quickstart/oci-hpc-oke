#!/usr/bin/env bash
# Keeps 802.1X alive for RDMA PFs that Dranet moved into a pod netns.
# The agent's supplicant stays behind on the host and cannot reach them,
# so this starts a replacement inside the pod.
#
# Runs on the host. One pass per invocation, safe to repeat.
#
# Exit codes:
#   0  all managed interfaces are authorized
#   1  the runner failed at something it owns, so the node goes NotReady
#   2  supplicants are up but the fabric is rejecting them. The caller
#      keeps the node Ready, since a fabric outage hits every node at once
set -uo pipefail

# Everything below assumes host paths, so bail out if nsenter did not work.
if [ "$(readlink /proc/self/ns/mnt 2>/dev/null)" != "$(readlink /proc/1/ns/mnt 2>/dev/null)" ]; then
  echo "supplicant-runner: not in the host mount namespace, refusing to run"
  exit 1
fi

# Paths used by the OCA oci-rdma-authentication plugin on OCI GPU images.
WPA_CONF=/etc/wpa_supplicant/wpa_supplicant-wired-8021x.conf
WPA_P12=/run/wpa_supplicant/client.p12
STATE_DIR=/run/oke-supplicant-runner

# Longer than an EAP-TLS handshake and wpa_supplicant's HELD back-off.
AUTH_GRACE=90

fail=0
unauthorized=()

log() { echo "supplicant-runner: $*"; }

# The OCA units are the authoritative list of managed PFs.
# The bare template name expands to an empty interface, so skip it.
ifaces=()
for unit in /etc/systemd/system/wpa_supplicant-wired@*.service; do
  [ -e "$unit" ] || continue
  unit=${unit##*/wpa_supplicant-wired@}
  unit=${unit%.service}
  [ -n "$unit" ] && ifaces+=("$unit")
done

# Checked before the tool list, so a node without RDMA is a clean no-op.
if [ ${#ifaces[@]} -eq 0 ]; then
  exit 0
fi

# Required once a node has PFs.
# Without them the runner cannot authenticate, or tell whether it did.
for tool in wpa_supplicant wpa_cli nsenter ip; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    log "required tool $tool not found, refusing to run"
    exit 1
  fi
done

# The failure windows below live in these files, so a state directory we
# cannot write would silently reset them every pass and hide a dead port.
if ! mkdir -p "$STATE_DIR" 2>/dev/null || ! : > "$STATE_DIR/.probe" 2>/dev/null; then
  log "cannot write $STATE_DIR, refusing to run"
  exit 1
fi
rm -f "$STATE_DIR/.probe"
# Holds config copies carrying the EAP-TLS key password.
chmod 700 "$STATE_DIR"

# Same reasoning per file, since a full filesystem fails writes one at a time.
write_state() {
  if ! echo "$2" > "$STATE_DIR/$1" 2>/dev/null; then
    log "cannot write $STATE_DIR/$1"
    fail=1
    return 1
  fi
}

host_ns=$(readlink /proc/1/ns/net)

have_ethtool=yes
if ! command -v ethtool >/dev/null 2>&1; then
  have_ethtool=no
  log "ethtool not found, renamed interfaces cannot be matched by PCI address"
fi

bus_info() {
  nsenter --net="$1" ethtool -i "$2" 2>/dev/null | awk '/^bus-info:/ {print $2}'
}

# Built at most once per pass, and only when a PF is missing.
# Forking readlink per process costs seconds on a busy node.
declare -A NS_PIDS=()
declare -A NS_IFACES=()
declare -A OUR_PIDS=()
proc_map_built=no

build_proc_map() {
  [ "$proc_map_built" = yes ] && return
  proc_map_built=yes
  local dir ns pid f p
  while read -r dir ns; do
    [ -n "$ns" ] || continue
    [ "$ns" = "$host_ns" ] && continue
    pid=${dir#/proc/}
    pid=${pid%/ns}
    NS_PIDS[$ns]="${NS_PIDS[$ns]:-}$pid "
  done < <(find /proc/[0-9]*/ns/net -maxdepth 0 -printf '%h %l\n' 2>/dev/null)
  for f in "$STATE_DIR"/*.pid; do
    [ -e "$f" ] || continue
    read -r p < "$f" 2>/dev/null || continue
    [ -n "$p" ] && OUR_PIDS[$p]=1
  done
}

# One nsenter per namespace, not one per interface per namespace.
netns_ifaces() {
  local ns=$1 pid
  if [ -z "${NS_IFACES[$ns]+set}" ]; then
    pid=${NS_PIDS[$ns]%% *}
    NS_IFACES[$ns]=$(nsenter --net="/proc/$pid/ns/net" ip -o link show 2>/dev/null |
      awk -F': ' '{sub(/@.*/, "", $2); print $2}' | tr '\n' ' ')
  fi
  echo "${NS_IFACES[$ns]}"
}

netns_has_iface() {
  case " $(netns_ifaces "$1") " in *" $2 "*) return 0 ;; esac
  return 1
}

# Prints "<pid> <current-name>". A claim can rename a PF to another PF's name,
# so a name match is only trusted when the PCI address agrees.
find_in_netns() {
  local iface=$1 pci=$2 ns pid name
  build_proc_map
  for ns in "${!NS_PIDS[@]}"; do
    pid=${NS_PIDS[$ns]%% *}
    if netns_has_iface "$ns" "$iface"; then
      if [ -z "$pci" ] || [ "$have_ethtool" != yes ] || [ "$(bus_info "/proc/$pid/ns/net" "$iface")" = "$pci" ]; then
        echo "$pid $iface"
        return 0
      fi
    fi
  done
  # Nothing matched by name, so look for the device itself.
  if [ -z "$pci" ] || [ "$have_ethtool" != yes ]; then
    return 1
  fi
  for ns in "${!NS_PIDS[@]}"; do
    pid=${NS_PIDS[$ns]%% *}
    for name in $(netns_ifaces "$ns"); do
      [ "$name" = "lo" ] && continue
      if [ "$(bus_info "/proc/$pid/ns/net" "$name")" = "$pci" ]; then
        echo "$pid $name"
        return 0
      fi
    done
  done
  return 1
}

# Pidfiles outlive their supplicants. The config path is unique per interface,
# and the netns test spares the agent's own supplicants.
runner_pid() {
  local iface=$1 pidfile="$STATE_DIR/$1.pid" pid
  [ -f "$pidfile" ] || return 1
  pid=$(cat "$pidfile" 2>/dev/null) || return 1
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    return 1
  fi
  if [ "$(cat "/proc/$pid/comm" 2>/dev/null)" != "wpa_supplicant" ]; then
    return 1
  fi
  if [ "$(readlink "/proc/$pid/ns/net" 2>/dev/null)" = "$host_ns" ]; then
    return 1
  fi
  if ! tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | grep -qxF "$STATE_DIR/$iface.conf"; then
    return 1
  fi
  echo "$pid"
}

# A supplicant whose pidfile was lost is invisible to runner_pid.
# It would pin the pod netns forever, but its argv still names our config.
adopt_orphan() {
  local iface=$1 ns pid
  build_proc_map
  for ns in "${!NS_PIDS[@]}"; do
    for pid in ${NS_PIDS[$ns]}; do
      [ -n "${OUR_PIDS[$pid]:-}" ] && continue
      [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = "wpa_supplicant" ] || continue
      if tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | grep -qxF "$STATE_DIR/$iface.conf"; then
        echo "$pid"
        return 0
      fi
    done
  done
  return 1
}

# Waits for the process to exit before deleting its state.
# A replacement would otherwise race it for the control socket.
stop_runner() {
  local iface=$1 pid waited
  if ! pid=$(runner_pid "$iface"); then
    pid=$(adopt_orphan "$iface") && log "$iface: adopting orphaned supplicant (pid $pid)"
  fi
  if [ -n "${pid:-}" ]; then
    log "stopping supplicant for $iface (pid $pid)"
    kill "$pid" 2>/dev/null || true
    waited=0
    while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 10 ]; do
      sleep 0.2
      waited=$((waited + 1))
    done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    unset "OUR_PIDS[$pid]"
  fi
  rm -f "$STATE_DIR/$iface.pid" "$STATE_DIR/$iface.podname" "$STATE_DIR/$iface.conf"
  rm -rf "$STATE_DIR/ctrl/$iface"
}

# Kept out of stop_runner so the window tracks the port, not the process.
# Otherwise a rejected port looks healthy by restarting inside its grace.
clear_auth_state() {
  rm -f "$STATE_DIR/$1.unauth" "$STATE_DIR/$1.restart" "$STATE_DIR/$1.missing"
}

# Interfaces go briefly missing while a pod is torn down.
# Only report one that stays undiscoverable for longer than that.
missing_too_long() {
  local iface=$1 since now
  now=$(date +%s)
  since=$(cat "$STATE_DIR/$iface.missing" 2>/dev/null || echo "")
  if [ -z "$since" ]; then
    write_state "$iface.missing" "$now"
    return 1
  fi
  [ $(( now - since )) -ge "$AUTH_GRACE" ]
}

# A live pod keeps its sandbox process here, so "only ours" means it is gone.
# A netns releases its interfaces only when its last process exits.
# A supplicant left behind would strand the PF off the host.
netns_has_other_procs() {
  local ns=$1 pid
  build_proc_map
  for pid in ${NS_PIDS[$ns]:-}; do
    [ -n "${OUR_PIDS[$pid]:-}" ] && continue
    if [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = "wpa_supplicant" ] &&
      tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "^$STATE_DIR/"; then
      continue
    fi
    return 0
  done
  return 1
}

# A live daemon proves nothing. EAP can be rejected while it keeps running.
# Returns 0 authorized, 1 the fabric rejected it, 2 it did not answer.
# The caller must keep 1 and 2 apart. A port the fabric refuses is not our
# problem, but a supplicant we cannot reach on its own control socket is.
supplicant_status() {
  local iface=$1 podname=$2 out
  out=$(wpa_cli -p "$STATE_DIR/ctrl/$iface" -i "$podname" status 2>/dev/null) || return 2
  case "$out" in
    *suppPortStatus=Authorized*) return 0 ;;
    *suppPortStatus=*) return 1 ;;
  esac
  return 2
}

# Private control socket per interface.
# In-pod names are only unique per netns, so a shared directory can collide.
make_conf() {
  local iface=$1
  local conf="$STATE_DIR/$iface.conf"
  [ -f "$WPA_CONF" ] || return 1
  mkdir -p "$STATE_DIR/ctrl/$iface" || return 1
  chmod 700 "$STATE_DIR/ctrl/$iface" || return 1
  # umask before the redirect so the key password is never world-readable.
  (umask 077 && sed "s|^ctrl_interface=.*|ctrl_interface=$STATE_DIR/ctrl/$iface|" "$WPA_CONF" > "$conf") || return 1
  if ! grep -q '^ctrl_interface=' "$conf"; then
    echo "ctrl_interface=$STATE_DIR/ctrl/$iface" >> "$conf" || return 1
  fi
  # A truncated copy would start a supplicant that never authenticates.
  grep -q '^network=' "$conf"
}

running=()
for iface in "${ifaces[@]}"; do
  pidfile="$STATE_DIR/$iface.pid"

  # PF is on the host, so the OCA plugin owns authentication again.
  if [ -e "/sys/class/net/$iface" ]; then
    [ -f "$pidfile" ] && stop_runner "$iface"
    clear_auth_state "$iface"
    # Record the PCI address now, while the name still maps to the device.
    pci=$(basename "$(readlink -f "/sys/class/net/$iface/device" 2>/dev/null)")
    if [ -n "$pci" ] && [ "$pci" != "/" ]; then
      write_state "$iface.pci" "$pci"
    fi
    continue
  fi

  podname=$(cat "$STATE_DIR/$iface.podname" 2>/dev/null || echo "$iface")
  if pid=$(runner_pid "$iface"); then
    build_proc_map
    sup_ns=$(readlink "/proc/$pid/ns/net" 2>/dev/null)
    if [ -n "$sup_ns" ] && netns_has_iface "$sup_ns" "$podname"; then
      if ! netns_has_other_procs "$sup_ns"; then
        log "$iface: claiming pod is gone, releasing the interface"
        stop_runner "$iface"
        clear_auth_state "$iface"
        continue
      fi
      now=$(date +%s)
      supplicant_status "$iface" "$podname" && sup=0 || sup=$?
      if [ "$sup" -eq 0 ]; then
        clear_auth_state "$iface"
        running+=("$iface")
        continue
      fi

      unauth_since=$(cat "$STATE_DIR/$iface.unauth" 2>/dev/null || echo "")
      if [ -z "$unauth_since" ]; then
        unauth_since=$now
        write_state "$iface.unauth" "$unauth_since"
      fi
      if [ $(( now - unauth_since )) -lt "$AUTH_GRACE" ]; then
        # Initial handshake or a brief reauth flap.
        running+=("$iface")
        continue
      fi

      if [ "$sup" -eq 2 ]; then
        # We cannot reach a supplicant we started, which is ours to fix.
        log "$iface supplicant has not answered its control socket for $(( now - unauth_since ))s"
        fail=1
      else
        # Reported, but not a runner fault.
        # The supplicant is up and the fabric is refusing it.
        unauthorized+=("$iface")
      fi
      last_restart=$(cat "$STATE_DIR/$iface.restart" 2>/dev/null || echo 0)
      if [ $(( now - last_restart )) -lt "$AUTH_GRACE" ]; then
        running+=("$iface")
        continue
      fi
      log "$iface unauthorized for $(( now - unauth_since ))s, restarting its supplicant"
      write_state "$iface.restart" "$now"
      stop_runner "$iface"
    else
      # Pod is gone or the PF moved to a different claim.
      stop_runner "$iface"
      clear_auth_state "$iface"
    fi
  elif adopt_orphan "$iface" >/dev/null; then
    # Pidfile lost, but the process is still out there holding the control
    # socket and the pod netns. Nothing can replace it until it is gone.
    stop_runner "$iface"
  fi

  pci=$(cat "$STATE_DIR/$iface.pci" 2>/dev/null || true)
  if found=$(find_in_netns "$iface" "$pci"); then
    target=${found%% *}
    podname=${found##* }
    if ! make_conf "$iface"; then
      log "cannot create supplicant config for $iface ($WPA_CONF missing)"
      fail=1
      continue
    fi
    log "starting supplicant for $iface (pod interface $podname) in netns of pid $target"
    # Without -s a daemonized supplicant discards its log output.
    if nsenter --net="/proc/$target/ns/net" \
      wpa_supplicant -B -s -Dwired -i "$podname" -c "$STATE_DIR/$iface.conf" -P "$pidfile"; then
      write_state "$iface.podname" "$podname"
      rm -f "$STATE_DIR/$iface.missing"
      running+=("$iface")
    else
      log "failed to start supplicant for $iface"
      rm -f "$pidfile"
      fail=1
    fi
  elif missing_too_long "$iface"; then
    # Claimed but undiscoverable long after any teardown.
    # Report it rather than looking healthy on an unauthenticated port.
    log "$iface not found in host netns or any pod netns"
    fail=1
  fi
done

# The OCA cannot reach these supplicants, so forward cert rotations here.
p12_mtime=$(stat -c %Y "$WPA_P12" 2>/dev/null || echo missing)
last_mtime=$(cat "$STATE_DIR/p12.mtime" 2>/dev/null || echo none)
if [ "$last_mtime" != "none" ] && [ "$p12_mtime" != "$last_mtime" ] && [ "$p12_mtime" != missing ]; then
  for iface in "${running[@]}"; do
    podname=$(cat "$STATE_DIR/$iface.podname" 2>/dev/null || echo "$iface")
    log "certificate rotated, reconfiguring supplicant for $iface"
    # In case the OCA rewrote its own config.
    if ! make_conf "$iface"; then
      log "cannot refresh config for $iface"
      fail=1
    fi
    if ! wpa_cli -p "$STATE_DIR/ctrl/$iface" -i "$podname" reconfigure 2>/dev/null | grep -q '^OK'; then
      # Next pass restarts it with the new certificate.
      fail=1
      stop_runner "$iface"
    fi
  done
fi
# Recorded only after acting on the rotation.
# A pass that dies partway then retries instead of marking it handled.
[ "$p12_mtime" != missing ] && write_state p12.mtime "$p12_mtime"

if [ ${#unauthorized[@]} -gt 0 ]; then
  log "UNAUTHORIZED: ${#unauthorized[@]} of ${#ifaces[@]} interfaces rejected by the fabric: ${unauthorized[*]}"
fi

[ "$fail" -ne 0 ] && exit 1
[ ${#unauthorized[@]} -gt 0 ] && exit 2
exit 0
