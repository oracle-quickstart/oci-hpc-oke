#!/usr/bin/env bash
# Runs 802.1X for RDMA PFs that Dranet moved into pod netns: the OCA
# supplicant stays on the host and cannot answer the switch reauth there.
# One idempotent pass per invocation, on the host.
#
# Exit 0 clean, 1 the runner itself failed, 2 supplicants are running but
# the fabric will not authorize them. The caller keeps the node Ready on 2:
# a RADIUS outage hits every node at once and is not a runner fault.
set -uo pipefail

# Everything below assumes the host filesystem, so fail closed if the
# namespace entry did not happen.
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

# The OCA units are the authoritative list of managed PFs. The bare
# template name would expand to an empty interface, so skip it.
ifaces=()
for unit in /etc/systemd/system/wpa_supplicant-wired@*.service; do
  [ -e "$unit" ] || continue
  unit=${unit##*/wpa_supplicant-wired@}
  unit=${unit%.service}
  [ -n "$unit" ] && ifaces+=("$unit")
done

# Nothing to manage here. Checked before the tools below, so a node without
# the RDMA auth stack is a clean no-op rather than permanently NotReady.
if [ ${#ifaces[@]} -eq 0 ]; then
  exit 0
fi

# On a node that does have PFs, these are required: without them the runner
# cannot authenticate or tell whether it did.
for tool in wpa_supplicant wpa_cli nsenter ip; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    log "required tool $tool not found, refusing to run"
    exit 1
  fi
done

mkdir -p "$STATE_DIR"
# Holds config copies carrying the EAP-TLS key password.
chmod 700 "$STATE_DIR"

host_ns=$(readlink /proc/1/ns/net)

have_ethtool=yes
if ! command -v ethtool >/dev/null 2>&1; then
  have_ethtool=no
  log "ethtool not found, renamed interfaces cannot be matched by PCI address"
fi

bus_info() {
  nsenter --net="$1" ethtool -i "$2" 2>/dev/null | awk '/^bus-info:/ {print $2}'
}

# Namespace state, built at most once per pass and only when a PF is
# actually missing. Forking readlink per process costs seconds on a node
# with thousands of them, and this used to run per interface.
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

# Prints "<pid> <current-name>". A claim can rename a PF to another PF's
# name, so a name match only counts when the PCI address agrees.
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

# Pidfiles outlive their supplicants, so check the pid is still ours before
# trusting or killing it. The config path is unique per interface; the netns
# test also keeps the host's OCA supplicants safe.
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

# A supplicant whose pidfile was lost can never be found by runner_pid
# again, and it would pin the pod netns forever. Its argv still names this
# interface's config, so recover it from the namespace map.
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

# Waits for the process to go before deleting its state, so the caller can
# start a replacement without racing the old one for the control socket.
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

# Kept out of stop_runner: the window must measure how long the port has
# been failing, or a rejected port looks healthy by restarting inside it.
clear_auth_state() {
  rm -f "$STATE_DIR/$1.unauth" "$STATE_DIR/$1.restart" "$STATE_DIR/$1.missing"
}

# Interfaces go briefly missing while a pod is torn down, so only report a
# failure once one has been undiscoverable for longer than that.
missing_too_long() {
  local iface=$1 since now
  now=$(date +%s)
  since=$(cat "$STATE_DIR/$iface.missing" 2>/dev/null || echo "")
  if [ -z "$since" ]; then
    echo "$now" > "$STATE_DIR/$iface.missing"
    return 1
  fi
  [ $(( now - since )) -ge "$AUTH_GRACE" ]
}

# A live pod always keeps its sandbox process here, so "only ours" means the
# pod is gone. A netns releases its interfaces only when its last process
# exits, so staying would strand the PF off the host. Only the pids in this
# one namespace are examined, and the comm check also catches an orphan of
# ours whose pidfile was lost.
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

# A live daemon proves nothing: EAP can be rejected while it keeps running.
supplicant_authorized() {
  local iface=$1 podname=$2
  wpa_cli -p "$STATE_DIR/ctrl/$iface" -i "$podname" status 2>/dev/null | grep -q '^suppPortStatus=Authorized'
}

# Private control socket per interface: in-pod names are only unique per
# netns, so a shared directory can collide.
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

  # PF is on the host: the OCA plugin owns authentication again.
  if [ -e "/sys/class/net/$iface" ]; then
    [ -f "$pidfile" ] && stop_runner "$iface"
    clear_auth_state "$iface"
    # Record the PCI address now, while the name still maps to the device.
    pci=$(basename "$(readlink -f "/sys/class/net/$iface/device" 2>/dev/null)")
    if [ -n "$pci" ] && [ "$pci" != "/" ]; then
      echo "$pci" > "$STATE_DIR/$iface.pci"
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
      if supplicant_authorized "$iface" "$podname"; then
        clear_auth_state "$iface"
        running+=("$iface")
        continue
      fi

      unauth_since=$(cat "$STATE_DIR/$iface.unauth" 2>/dev/null || echo "")
      if [ -z "$unauth_since" ]; then
        unauth_since=$now
        echo "$unauth_since" > "$STATE_DIR/$iface.unauth"
      fi
      if [ $(( now - unauth_since )) -lt "$AUTH_GRACE" ]; then
        # Initial handshake or a brief reauth flap.
        running+=("$iface")
        continue
      fi

      # Reported but not a runner fault: the supplicant is running and the
      # fabric is refusing it, which during a RADIUS outage is true on every
      # node at once. Summarised at the end of the pass.
      unauthorized+=("$iface")
      last_restart=$(cat "$STATE_DIR/$iface.restart" 2>/dev/null || echo 0)
      if [ $(( now - last_restart )) -lt "$AUTH_GRACE" ]; then
        running+=("$iface")
        continue
      fi
      log "$iface unauthorized for $(( now - unauth_since ))s, restarting its supplicant"
      echo "$now" > "$STATE_DIR/$iface.restart"
      stop_runner "$iface"
    else
      # Pod is gone or the PF moved to a different claim.
      stop_runner "$iface"
      clear_auth_state "$iface"
    fi
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
    # -s or a daemonized supplicant logs nowhere.
    if nsenter --net="/proc/$target/ns/net" \
      wpa_supplicant -B -s -Dwired -i "$podname" -c "$STATE_DIR/$iface.conf" -P "$pidfile"; then
      echo "$podname" > "$STATE_DIR/$iface.podname"
      rm -f "$STATE_DIR/$iface.missing"
      running+=("$iface")
    else
      log "failed to start supplicant for $iface"
      rm -f "$pidfile"
      fail=1
    fi
  elif missing_too_long "$iface"; then
    # Claimed but undiscoverable well past a teardown: report it rather
    # than looking healthy while the port is unauthenticated.
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
# Recorded only after the rotation was acted on, so a pass that dies partway
# retries instead of marking the new certificate as handled.
[ "$p12_mtime" != missing ] && echo "$p12_mtime" > "$STATE_DIR/p12.mtime"

if [ ${#unauthorized[@]} -gt 0 ]; then
  log "UNAUTHORIZED: ${#unauthorized[@]} of ${#ifaces[@]} interfaces rejected by the fabric: ${unauthorized[*]}"
fi

[ "$fail" -ne 0 ] && exit 1
[ ${#unauthorized[@]} -gt 0 ] && exit 2
exit 0
