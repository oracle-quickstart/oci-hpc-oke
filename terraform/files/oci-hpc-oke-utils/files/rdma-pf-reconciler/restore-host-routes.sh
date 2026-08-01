#!/usr/bin/env bash

# Restores the two OCA policy-table routes after an RDMA PF returns to the host.
# The caller provides log().

RESTORE_ROUTES_PENDING=3
RESTORE_ROUTES_INVALID=4

read_policy_table() {
  local iface=$1 rules=$2 field index table="" oif=""
  local -a fields
  local -A tables=()

  POLICY_TABLE=""
  POLICY_ERROR=""

  while read -r -a fields; do
    table=""
    oif=""
    for (( index = 0; index < ${#fields[@]}; index++ )); do
      field=${fields[$index]}
      case "$field" in
        oif)
          oif=${fields[$(( index + 1 ))]:-}
          ;;
        lookup|table)
          table=${fields[$(( index + 1 ))]:-}
          ;;
      esac
    done

    if [ "$oif" = "$iface" ] && [ -n "$table" ]; then
      tables["$table"]=1
    fi
  done <<< "$rules"

  if [ ${#tables[@]} -eq 0 ]; then
    RESTORE_WAIT_REASON="policy-rule-missing"
    return "$RESTORE_ROUTES_PENDING"
  fi
  if [ ${#tables[@]} -ne 1 ]; then
    POLICY_ERROR="found more than one policy table: ${!tables[*]}"
    RESTORE_WAIT_REASON="multiple-policy-tables"
    return "$RESTORE_ROUTES_INVALID"
  fi
  for POLICY_TABLE in "${!tables[@]}"; do :; done
}

read_connected_route() {
  local routes=$1 line field index source destination key
  local -a fields
  local -A connected=()

  CONNECTED_NETWORK=""
  CONNECTED_ADDRESS=""
  CONNECTED_ERROR=""
  while IFS= read -r line; do
    read -r -a fields <<< "$line"
    [ ${#fields[@]} -gt 0 ] || continue
    destination=${fields[0]}
    source=""
    for (( index = 0; index < ${#fields[@]}; index++ )); do
      field=${fields[$index]}
      if [ "$field" = src ]; then
        source=${fields[$(( index + 1 ))]:-}
      fi
    done
    if [ -n "$source" ] && [ "$destination" != default ]; then
      connected["$destination|$source"]=1
    fi
  done <<< "$routes"

  if [ ${#connected[@]} -eq 0 ]; then
    RESTORE_WAIT_REASON="connected-main-route-missing"
    return "$RESTORE_ROUTES_PENDING"
  fi
  if [ ${#connected[@]} -ne 1 ]; then
    CONNECTED_ERROR="found more than one connected route: ${!connected[*]}"
    RESTORE_WAIT_REASON="multiple-connected-routes"
    return 1
  fi
  for key in "${!connected[@]}"; do :; done
  CONNECTED_NETWORK=${key%%|*}
  CONNECTED_ADDRESS=${key#*|}
}

count_matching_routes() {
  local iface=$1 address=$2 network=$3 routes=$4
  local line field destination route_type dev source index
  local connected_route=0 local_route=0
  local -a fields

  MATCHING_ROUTE_COUNT=0
  while IFS= read -r line; do
    read -r -a fields <<< "$line"
    [ ${#fields[@]} -gt 0 ] || continue

    destination=${fields[0]}
    route_type=unicast
    if [ "$destination" = local ]; then
      route_type=local
      destination=${fields[1]:-}
      destination=${destination%/32}
    fi
    dev=""
    source=""
    for (( index = 0; index < ${#fields[@]}; index++ )); do
      field=${fields[$index]}
      case "$field" in
        dev)
          dev=${fields[$(( index + 1 ))]:-}
          ;;
        src)
          source=${fields[$(( index + 1 ))]:-}
          ;;
      esac
    done

    if [ "$dev" != "$iface" ] || [ "$source" != "$address" ]; then
      continue
    fi
    if [ "$route_type" = unicast ] && [ "$destination" = "$network" ]; then
      connected_route=1
    fi
    if [ "$route_type" = local ] && [ "$destination" = "$address" ]; then
      local_route=1
    fi
  done <<< "$routes"
  MATCHING_ROUTE_COUNT=$(( connected_route + local_route ))
}

# These outputs are read by restore-host-routes-monitor.sh.
# shellcheck disable=SC2034
restore_host_routes() {
  local iface=$1 rules=${2-} main_routes routes policy_rc connected_rc

  RESTORE_CHANGED=0
  RESTORE_WAIT_REASON=""

  if [ "$#" -lt 2 ]; then
    if ! rules=$(ip -4 -o rule show); then
      RESTORE_WAIT_REASON="policy-rule-read-failed"
      log "$iface: cannot read IPv4 policy rules"
      return 1
    fi
  fi

  policy_rc=0
  read_policy_table "$iface" "$rules" || policy_rc=$?
  if [ "$policy_rc" -ne 0 ]; then
    [ -n "$POLICY_ERROR" ] && log "$iface: $POLICY_ERROR"
    return "$policy_rc"
  fi

  if ! main_routes=$(ip -4 -o route show table main dev "$iface" proto kernel scope link); then
    RESTORE_WAIT_REASON="connected-main-route-read-failed"
    log "$iface: cannot read the main routing table"
    return 1
  fi
  connected_rc=0
  read_connected_route "$main_routes" || connected_rc=$?
  if [ "$connected_rc" -ne 0 ]; then
    [ -n "$CONNECTED_ERROR" ] && log "$iface: $CONNECTED_ERROR"
    return "$connected_rc"
  fi

  if ! routes=$(ip -4 -o route show table "$POLICY_TABLE"); then
    RESTORE_WAIT_REASON="policy-table-read-failed"
    log "$iface: cannot read policy table $POLICY_TABLE"
    return 1
  fi
  count_matching_routes "$iface" "$CONNECTED_ADDRESS" "$CONNECTED_NETWORK" "$routes"
  if [ "$MATCHING_ROUTE_COUNT" -eq 2 ]; then
    return 0
  fi

  if ! ip -4 route replace "$CONNECTED_NETWORK" dev "$iface" src "$CONNECTED_ADDRESS" table "$POLICY_TABLE"; then
    RESTORE_WAIT_REASON="connected-route-replace-failed"
    log "$iface: failed to restore connected route in table $POLICY_TABLE"
    return 1
  fi
  if ! ip -4 route replace local "$CONNECTED_ADDRESS" dev "$iface" src "$CONNECTED_ADDRESS" table "$POLICY_TABLE"; then
    RESTORE_WAIT_REASON="local-route-replace-failed"
    log "$iface: failed to restore local route in table $POLICY_TABLE"
    return 1
  fi

  if ! routes=$(ip -4 -o route show table "$POLICY_TABLE"); then
    RESTORE_WAIT_REASON="policy-table-verify-read-failed"
    log "$iface: cannot verify policy table $POLICY_TABLE"
    return 1
  fi
  count_matching_routes "$iface" "$CONNECTED_ADDRESS" "$CONNECTED_NETWORK" "$routes"
  if [ "$MATCHING_ROUTE_COUNT" -ne 2 ]; then
    RESTORE_WAIT_REASON="route-verification-failed"
    log "$iface: host route restore verification failed (table=$POLICY_TABLE routes=$MATCHING_ROUTE_COUNT)"
    return 1
  fi

  RESTORE_CHANGED=1
  log "$iface: restored host policy routes (table=$POLICY_TABLE network=$CONNECTED_NETWORK routes=$MATCHING_ROUTE_COUNT)"
}
