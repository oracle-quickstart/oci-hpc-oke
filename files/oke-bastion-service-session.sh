#!/usr/bin/env bash
# =============================================================================
# OKE Private Endpoint Access via OCI Bastion (Port Forwarding)
# =============================================================================
# README
# -----
# This script creates (or reuses) an OCI Bastion port-forwarding session to an
# OKE private endpoint, prints the SSH tunnel command to run manually, and
# generates a kubeconfig that points to https://127.0.0.1:<LOCAL_PORT>.
#
# Input precedence:
#   1) CLI flags
#   2) Environment variables
#   3) Interactive prompts (unless --non-interactive)
#
# Requirements:
#   - oci CLI, kubectl, ssh
#   - An SSH keypair authorized for the bastion session
#
# Usage (interactive prompts for missing values):
#   ./files/oke-bastion-service-session.sh
#
# Usage example (fully non-interactive):
#   ./files/oke-bastion-service-session.sh \
#     --bastion-ocid ocid1.bastion... \
#     --cluster-ocid ocid1.cluster... \
#     --oke-endpoint-ip 10.140.0.6 \
#     --region us-ashburn-1 \
#     --profile DEFAULT \
#     --ssh-key ~/.ssh/id_rsa \
#     --local-port 6443 \
#     --target-port 6443 \
#     --ttl-seconds 10800 \
#     --non-interactive
#
# Usage example (env vars + prompt for missing):
#   export BASTION_OCID=ocid1.bastion...
#   export CLUSTER_OCID=ocid1.cluster...
#   export OKE_ENDPOINT_IP=10.140.0.6
#   export REGION=us-ashburn-1
#   export PROFILE=DEFAULT
#   ./files/oke-bastion-service-session.sh
#
# Optional flags:
#   --kubeconfig <path>         Persist kubeconfig at a custom path
#   --cleanup-kubeconfig        Delete the default kubeconfig for this cluster
#   --cleanup-session <ocid>    Delete a bastion session (and kill its auto-tunnel)
#   --auto-tunnel               Start the SSH tunnel in the background automatically
#   --session-id <ocid>         Reuse an existing bastion session (skip creation)
#   --non-interactive           Fail fast if required inputs are missing
#
# Notes:
#   - Default kubeconfig path: ~/.kube/oke-bastion/<cluster-ocid>.yaml
#   - By default the script does NOT start the SSH tunnel automatically.
#     Run the printed SSH command in another terminal before using kubectl.
#   - Use --auto-tunnel to start the SSH tunnel in the background automatically.
#   - The script prints the KUBECONFIG path. To persist in your shell:
#       export KUBECONFIG=<path>
#   - Use --cleanup-kubeconfig to delete the default kubeconfig file for the cluster and exit.
# =============================================================================

set -euo pipefail

# Defaults (can be overridden by env or flags)
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
LOCAL_PORT="${LOCAL_PORT:-6443}"
TTL_SECONDS="${TTL_SECONDS:-10800}"
REGION="${REGION:-}"
PROFILE="${PROFILE:-}"
BASTION_OCID="${BASTION_OCID:-}"
CLUSTER_OCID="${CLUSTER_OCID:-}"
OKE_ENDPOINT_IP="${OKE_ENDPOINT_IP:-}"
TARGET_PORT="${TARGET_PORT:-6443}"
KUBECONFIG_OUT="${KUBECONFIG_OUT:-}"
DEFAULT_KUBECONFIG_DIR="$HOME/.kube/oke-bastion"
DEFAULT_KUBECONFIG_FILE=""

NON_INTERACTIVE=false
CLEANUP_KUBECONFIG=false
CLEANUP_SESSION=false
AUTO_TUNNEL=false
TUNNEL_PID=""

KCFG=""
SESSION_ID=""
SESSION_ID_OVERRIDE=""

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

cleanup_on_exit() {
  local exit_code=$?
  if [[ $exit_code -ne 0 && -n "$SESSION_ID" ]]; then
    local hint="$0 --cleanup-session $SESSION_ID"
    [[ -n "$REGION" ]] && hint="$hint --region $REGION"
    [[ -n "$PROFILE" ]] && hint="$hint --profile $PROFILE"
    printf '\nScript exited unexpectedly. To clean up the bastion session:\n' >&2
    printf '  %s\n' "$hint" >&2
  fi
}
trap cleanup_on_exit EXIT
section() { printf '\n── %s ──\n' "$*"; }
banner() {
  local width=60
  local border
  border=$(printf '═%.0s' $(seq 1 "$width"))
  printf '\n%s\n' "$border"
  for line in "$@"; do
    printf '  %s\n' "$line"
  done
  printf '%s\n' "$border"
}

usage() {
  cat <<'USAGE'
Usage:
  oke-bastion-service-session.sh [options]

Required (can be flags, env, or prompts):
  --bastion-ocid <ocid>
  --cluster-ocid <ocid>
  --oke-endpoint-ip <ip>

Optional:
  --region <region>
  --profile <profile>
  --ssh-key <path>
  --local-port <port>
  --ttl-seconds <seconds>
  --target-port <port>
  --kubeconfig <path>
  --cleanup-kubeconfig
  --cleanup-session <ocid>
  --auto-tunnel
  --session-id <ocid>
  --non-interactive
  -h, --help

Examples:
  ./files/oke-bastion-service-session.sh --bastion-ocid ... --cluster-ocid ... --oke-endpoint-ip 10.140.0.6
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

validate_ocid() {
  local value="$1" expected_type="$2"
  [[ "$value" =~ ^ocid1\."$expected_type"\. ]] || die "Invalid OCID for type '${expected_type}': ${value}"
}

validate_ip() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "Invalid IPv4 address: ${ip}"
  local IFS='.'
  read -r -a octets <<< "$ip"
  for octet in "${octets[@]}"; do
    (( octet <= 255 )) || die "Invalid IPv4 address (octet > 255): ${ip}"
  done
}

validate_ttl() {
  [[ "$TTL_SECONDS" =~ ^[0-9]+$ ]] || die "TTL_SECONDS must be a number: ${TTL_SECONDS}"
  if (( TTL_SECONDS > 10800 )); then
    log "WARNING: TTL_SECONDS=${TTL_SECONDS} exceeds max 10800s. Setting to 10800."
    TTL_SECONDS=10800
  fi
  if (( TTL_SECONDS < 1 )); then
    die "TTL_SECONDS must be at least 1: ${TTL_SECONDS}"
  fi
}

validate_local_port() {
  [[ "$LOCAL_PORT" =~ ^[0-9]+$ ]] || die "LOCAL_PORT must be a number: ${LOCAL_PORT}"
  (( LOCAL_PORT >= 1 && LOCAL_PORT <= 65535 )) || die "LOCAL_PORT must be between 1 and 65535: ${LOCAL_PORT}"
  if command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:"$LOCAL_PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
      die "Port ${LOCAL_PORT} is already in use"
    fi
  elif command -v ss >/dev/null 2>&1; then
    if ss -tlnH "sport = :${LOCAL_PORT}" 2>/dev/null | grep -q .; then
      die "Port ${LOCAL_PORT} is already in use"
    fi
  fi
}

prompt_required() {
  local var_name="$1" prompt="$2" default_value="${3:-}"
  local current_value="${!var_name:-}"

  if [[ -z "$current_value" ]]; then
    if $NON_INTERACTIVE; then
      die "Missing required value: ${var_name}"
    fi

    if [[ -n "$default_value" ]]; then
      read -r -p "${prompt} [${default_value}]: " current_value || true
      current_value="${current_value:-$default_value}"
    else
      read -r -p "${prompt}: " current_value || true
    fi

    if [[ -z "$current_value" ]]; then
      die "Missing required value: ${var_name}"
    fi
    printf -v "$var_name" '%s' "$current_value"
  fi
}

prompt_optional() {
  local var_name="$1" prompt="$2"
  local current_value="${!var_name:-}"

  if [[ -z "$current_value" && $NON_INTERACTIVE == false ]]; then
    read -r -p "${prompt}: " current_value || true
    if [[ -n "$current_value" ]]; then
      printf -v "$var_name" '%s' "$current_value"
    fi
  fi
}

ensure_ssh_key() {
  SSH_KEY="${SSH_KEY/#\~/$HOME}"
  while [[ ! -f "$SSH_KEY" ]]; do
    if $NON_INTERACTIVE; then
      die "Missing SSH private key: $SSH_KEY"
    fi
    read -r -p "Enter SSH private key path [${SSH_KEY}]: " SSH_KEY_INPUT || true
    SSH_KEY_INPUT="${SSH_KEY_INPUT:-$SSH_KEY}"
    SSH_KEY="${SSH_KEY_INPUT/#\~/$HOME}"
  done

  if [[ ! -f "${SSH_KEY}.pub" ]]; then
    if $NON_INTERACTIVE; then
      die "Missing SSH public key: ${SSH_KEY}.pub"
    fi
    require_cmd ssh-keygen
    read -r -p "Public key not found. Generate ${SSH_KEY}.pub from private key? [Y/n]: " reply || true
    reply="${reply:-Y}"
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      ssh-keygen -y -f "$SSH_KEY" > "${SSH_KEY}.pub"
      log "Generated ${SSH_KEY}.pub"
    else
      die "SSH public key is required: ${SSH_KEY}.pub"
    fi
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bastion-ocid)
      BASTION_OCID="$2"; shift 2; ;;
    --cluster-ocid)
      CLUSTER_OCID="$2"; shift 2; ;;
    --oke-endpoint-ip|--endpoint-ip)
      OKE_ENDPOINT_IP="$2"; shift 2; ;;
    --region)
      REGION="$2"; shift 2; ;;
    --profile)
      PROFILE="$2"; shift 2; ;;
    --ssh-key)
      SSH_KEY="$2"; shift 2; ;;
    --local-port)
      LOCAL_PORT="$2"; shift 2; ;;
    --ttl-seconds)
      TTL_SECONDS="$2"; shift 2; ;;
    --target-port)
      TARGET_PORT="$2"; shift 2; ;;
    --kubeconfig)
      KUBECONFIG_OUT="$2"; shift 2; ;;
    --cleanup-kubeconfig)
      CLEANUP_KUBECONFIG=true; shift; ;;
    --cleanup-session)
      CLEANUP_SESSION=true; SESSION_ID_OVERRIDE="$2"; shift 2; ;;
    --auto-tunnel)
      AUTO_TUNNEL=true; shift; ;;
    --session-id)
      SESSION_ID_OVERRIDE="$2"; shift 2; ;;
    --non-interactive)
      NON_INTERACTIVE=true; shift; ;;
    -h|--help)
      usage; exit 0; ;;
    *)
      die "Unknown argument: $1"; ;;
  esac
done

if $CLEANUP_KUBECONFIG; then
  section "Cleanup: Kubeconfig"
  prompt_required CLUSTER_OCID "Enter OKE Cluster OCID"
  validate_ocid "$CLUSTER_OCID" "cluster"
  DEFAULT_KUBECONFIG_FILE="${DEFAULT_KUBECONFIG_DIR}/${CLUSTER_OCID}.yaml"
  if [[ -f "$DEFAULT_KUBECONFIG_FILE" ]]; then
    rm -f "$DEFAULT_KUBECONFIG_FILE"
    log "Deleted: $DEFAULT_KUBECONFIG_FILE"
  else
    log "No kubeconfig found at: $DEFAULT_KUBECONFIG_FILE"
  fi
  exit 0
fi

if $CLEANUP_SESSION; then
  section "Cleanup: Bastion session"
  [[ -n "$SESSION_ID_OVERRIDE" ]] || die "Missing session OCID for --cleanup-session"
  validate_ocid "$SESSION_ID_OVERRIDE" "bastionsession"
  command -v oci >/dev/null 2>&1 || die "OCI CLI not found. Install and configure it first:
  https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm"
  prompt_optional REGION "Enter OCI region (leave blank for CLI default)"
  prompt_optional PROFILE "Enter OCI CLI profile (leave blank for default)"
  OCI_CLEANUP_ARGS=()
  if [[ -n "$REGION" ]]; then
    OCI_CLEANUP_ARGS+=(--region "$REGION")
  fi
  if [[ -n "$PROFILE" ]]; then
    OCI_CLEANUP_ARGS+=(--profile "$PROFILE")
  fi
  TUNNEL_PID_FILE="/tmp/oke-bastion-tunnel-${SESSION_ID_OVERRIDE}.pid"
  if [[ -f "$TUNNEL_PID_FILE" ]]; then
    TUNNEL_PID="$(cat "$TUNNEL_PID_FILE")"
    if kill -0 "$TUNNEL_PID" 2>/dev/null; then
      kill "$TUNNEL_PID"
      log "Stopped SSH tunnel (PID: $TUNNEL_PID)"
      for _i in 1 2 3 4 5; do
        kill -0 "$TUNNEL_PID" 2>/dev/null || break
        sleep 1
      done
    fi
    rm -f "$TUNNEL_PID_FILE"
  fi
  log "Deleting bastion session: $SESSION_ID_OVERRIDE"
  oci "${OCI_CLEANUP_ARGS[@]}" bastion session delete \
    --session-id "$SESSION_ID_OVERRIDE" --force 2>&1 || die "Failed to delete bastion session"
  log "Bastion session deleted."
  exit 0
fi

command -v oci >/dev/null 2>&1 || die "OCI CLI not found. Install and configure it first:
  https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm"
command -v kubectl >/dev/null 2>&1 || die "kubectl not found. Install it first:
  https://kubernetes.io/docs/tasks/tools/#kubectl"
require_cmd ssh
command -v lsof >/dev/null 2>&1 || command -v ss >/dev/null 2>&1 || \
  die "Neither 'lsof' nor 'ss' is installed. At least one is required to check port availability."

validate_local_port
validate_ttl

prompt_required BASTION_OCID "Enter Bastion OCID"
validate_ocid "$BASTION_OCID" "bastion"
prompt_required CLUSTER_OCID "Enter OKE Cluster OCID"
validate_ocid "$CLUSTER_OCID" "cluster"
prompt_required OKE_ENDPOINT_IP "Enter OKE private endpoint IP (e.g., 10.140.0.6)"
validate_ip "$OKE_ENDPOINT_IP"

DEFAULT_KUBECONFIG_FILE="${DEFAULT_KUBECONFIG_DIR}/${CLUSTER_OCID}.yaml"

prompt_optional REGION "Enter OCI region (leave blank for CLI default)"
prompt_optional PROFILE "Enter OCI CLI profile (leave blank for default)"

ensure_ssh_key

OCI_COMMON_ARGS=()
if [[ -n "$REGION" ]]; then
  OCI_COMMON_ARGS+=(--region "$REGION")
fi
if [[ -n "$PROFILE" ]]; then
  OCI_COMMON_ARGS+=(--profile "$PROFILE")
fi

section "Validating OCI CLI configuration"
REGION_CHECK_OUT=$(oci "${OCI_COMMON_ARGS[@]}" iam region list --output table 2>&1) || {
  die "OCI CLI authentication failed. Check your credentials or profile:
  https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm
Details: ${REGION_CHECK_OUT}"
}
log "OCI CLI configuration OK"

section "Validating kubectl"
KUBECTL_CHECK_OUT=$(kubectl version --client 2>&1) || {
  die "kubectl is not working correctly. Reinstall or check your PATH:
  https://kubernetes.io/docs/tasks/tools/#kubectl
Details: ${KUBECTL_CHECK_OUT}"
}
log "kubectl OK"

if [[ -n "$KUBECONFIG_OUT" ]]; then
  KCFG="$KUBECONFIG_OUT"
  mkdir -p "$(dirname "$KCFG")"
else
  mkdir -p "$DEFAULT_KUBECONFIG_DIR"
  KCFG="$DEFAULT_KUBECONFIG_FILE"
fi

if [[ -n "$SESSION_ID_OVERRIDE" ]]; then
  SESSION_ID="$SESSION_ID_OVERRIDE"
  section "Reusing existing Bastion session"
  log "Session: $SESSION_ID"
else
  section "Creating Bastion port-forwarding session"
  log "Target: ${OKE_ENDPOINT_IP}:${TARGET_PORT}"
  CREATE_OUTPUT=$(
    oci "${OCI_COMMON_ARGS[@]}" bastion session create-port-forwarding \
      --bastion-id "$BASTION_OCID" \
      --target-private-ip "$OKE_ENDPOINT_IP" \
      --target-port "$TARGET_PORT" \
      --ssh-public-key-file "${SSH_KEY}.pub" \
      --session-ttl "$TTL_SECONDS" \
      --query 'data.id' --raw-output 2>&1
  ) || {
    die "Bastion session create failed:"$'\n'"${CREATE_OUTPUT}"
  }
  SESSION_ID="$CREATE_OUTPUT"
fi

if [[ -z "$SESSION_ID" || "$SESSION_ID" == "null" ]]; then
  die "Failed to create bastion session. Check OCI CLI output and permissions."
fi

log "Session OCID: $SESSION_ID"

section "Waiting for session to become active"
SESSION_STATE=""
SESSION_TIMEOUT=300
POLL_INTERVAL=2
START_TIME=$SECONDS
while (( SECONDS - START_TIME < SESSION_TIMEOUT )); do
  SESSION_STATE_OUT=$(
    oci "${OCI_COMMON_ARGS[@]}" bastion session get \
      --session-id "$SESSION_ID" \
      --query 'data."lifecycle-state"' --raw-output 2>&1
  ) || {
    die "Failed to read bastion session state:"$'\n'"${SESSION_STATE_OUT}"
  }
  SESSION_STATE="$SESSION_STATE_OUT"
  log "State: $SESSION_STATE"
  if [[ "$SESSION_STATE" == "ACTIVE" ]]; then
    break
  fi
  if [[ "$SESSION_STATE" == "FAILED" || "$SESSION_STATE" == "DELETED" ]]; then
    die "Bastion session is in state: $SESSION_STATE"
  fi
  if [[ -n "$SESSION_ID_OVERRIDE" && "$SESSION_STATE" != "CREATING" ]]; then
    die "Bastion session is not ACTIVE. Current state: $SESSION_STATE"
  fi
  sleep "$POLL_INTERVAL"
  if (( POLL_INTERVAL < 15 )); then
    POLL_INTERVAL=$(( POLL_INTERVAL + POLL_INTERVAL ))
    if (( POLL_INTERVAL > 15 )); then
      POLL_INTERVAL=15
    fi
  fi
done

if [[ "$SESSION_STATE" != "ACTIVE" ]]; then
  die "Bastion session did not become ACTIVE in ${SESSION_TIMEOUT}s"
fi

section "Fetching SSH command"
SSH_CMD="$(oci "${OCI_COMMON_ARGS[@]}" bastion session get --session-id "$SESSION_ID" --query 'data."ssh-metadata".command' --raw-output 2>/dev/null || true)"
if [[ -z "${SSH_CMD}" || "${SSH_CMD}" == "null" ]]; then
  SSH_CMD="$(oci "${OCI_COMMON_ARGS[@]}" bastion session get --session-id "$SESSION_ID" --query 'data.sshMetadata.command' --raw-output 2>/dev/null || true)"
fi

if [[ -z "${SSH_CMD}" || "${SSH_CMD}" == "null" ]]; then
  die "Could not extract SSH command. Inspect: oci bastion session get --session-id $SESSION_ID"
fi

# Replace common placeholders with actual key path
SSH_CMD="${SSH_CMD//<privateKey>/$SSH_KEY}"
SSH_CMD="${SSH_CMD//<privateKeyPath>/$SSH_KEY}"
SSH_CMD="${SSH_CMD//<private_key_path>/$SSH_KEY}"
SSH_CMD="${SSH_CMD//<private_key>/$SSH_KEY}"
SSH_CMD="${SSH_CMD//<keyfile>/$SSH_KEY}"
SSH_CMD="${SSH_CMD//<localPort>/$LOCAL_PORT}"
SSH_CMD="${SSH_CMD//<targetPort>/$TARGET_PORT}"
SSH_CMD="${SSH_CMD//<targetHost>/$OKE_ENDPOINT_IP}"
SSH_CMD="${SSH_CMD//<targetPrivateIp>/$OKE_ENDPOINT_IP}"

if [[ "$SSH_CMD" =~ \<[a-zA-Z_]+\> ]]; then
  log "WARNING: Unresolved placeholder(s) in SSH command: $(grep -oE '<[a-zA-Z_]+>' <<<"$SSH_CMD" | tr '\n' ' ')"
fi

if ! grep -qE '(^| )-i ' <<<"$SSH_CMD"; then
  SSH_CMD="$SSH_CMD -i '$SSH_KEY'"
fi
if ! grep -qE '(^| )-L ' <<<"$SSH_CMD"; then
  SSH_CMD="$SSH_CMD -N -L ${LOCAL_PORT}:${OKE_ENDPOINT_IP}:${TARGET_PORT}"
elif ! grep -qE '(^| )-N( |$)' <<<"$SSH_CMD"; then
  SSH_CMD="$SSH_CMD -N"
fi
if ! grep -qE 'ExitOnForwardFailure' <<<"$SSH_CMD"; then
  SSH_CMD="$SSH_CMD -o ExitOnForwardFailure=yes"
fi
if ! grep -qE 'ServerAliveInterval' <<<"$SSH_CMD"; then
  SSH_CMD="$SSH_CMD -o ServerAliveInterval=30"
fi
if ! grep -qE 'ServerAliveCountMax' <<<"$SSH_CMD"; then
  SSH_CMD="$SSH_CMD -o ServerAliveCountMax=6"
fi
if ! grep -qE 'TCPKeepAlive' <<<"$SSH_CMD"; then
  SSH_CMD="$SSH_CMD -o TCPKeepAlive=yes"
fi

if $AUTO_TUNNEL; then
  section "Starting SSH tunnel"
  SSH_PID=""
  SSH_MAX_RETRIES=3
  SSH_RETRY_DELAY=10
  for _ssh_attempt in 1 2 3 4; do
    bash -c "exec $SSH_CMD" &
    SSH_PID=$!
    TUNNEL_WAIT=0
    TUNNEL_TIMEOUT=15
    while (( TUNNEL_WAIT < TUNNEL_TIMEOUT )); do
      if ! kill -0 "$SSH_PID" 2>/dev/null; then
        break
      fi
      if lsof -iTCP:"$LOCAL_PORT" -sTCP:LISTEN -t >/dev/null 2>&1 || \
         ss -tlnH "sport = :${LOCAL_PORT}" 2>/dev/null | grep -q .; then
        break 2
      fi
      sleep 1
      (( TUNNEL_WAIT++ )) || true
    done
    if (( _ssh_attempt <= SSH_MAX_RETRIES )); then
      log "SSH tunnel attempt ${_ssh_attempt} failed, retrying in ${SSH_RETRY_DELAY}s..."
      sleep "$SSH_RETRY_DELAY"
    fi
  done
  if ! lsof -iTCP:"$LOCAL_PORT" -sTCP:LISTEN -t >/dev/null 2>&1 && \
     ! ss -tlnH "sport = :${LOCAL_PORT}" 2>/dev/null | grep -q .; then
    die "SSH tunnel failed to start after $((SSH_MAX_RETRIES + 1)) attempts"
  fi
  TUNNEL_PID_FILE="/tmp/oke-bastion-tunnel-${SESSION_ID}.pid"
  echo "$SSH_PID" > "$TUNNEL_PID_FILE"
  log "Tunnel running (PID: $SSH_PID), forwarding localhost:${LOCAL_PORT} -> ${OKE_ENDPOINT_IP}:${TARGET_PORT}"
else
  section "SSH tunnel command"
  log "Run the following command in another terminal to start the tunnel:"
  log ""
  log "  $SSH_CMD"
  log ""
fi

section "Generating kubeconfig"
oci "${OCI_COMMON_ARGS[@]}" ce cluster create-kubeconfig \
  --cluster-id "$CLUSTER_OCID" \
  --token-version 2.0.0 \
  --kube-endpoint PRIVATE_ENDPOINT \
  --file "$KCFG"

log "Rewriting server address to use localhost tunnel..."
CLUSTER_NAME="$(kubectl config view --kubeconfig "$KCFG" -o jsonpath='{.clusters[0].name}' 2>/dev/null || true)"
if [[ -z "$CLUSTER_NAME" ]]; then
  die "Failed to detect cluster name in kubeconfig."
fi
kubectl config set-cluster "$CLUSTER_NAME" --server "https://127.0.0.1:${LOCAL_PORT}" --kubeconfig "$KCFG" >/dev/null
log "Kubeconfig ready: $KCFG"

CLEANUP_CMD="$0 --cleanup-session $SESSION_ID"
[[ -n "$REGION" ]] && CLEANUP_CMD="$CLEANUP_CMD --region $REGION"
[[ -n "$PROFILE" ]] && CLEANUP_CMD="$CLEANUP_CMD --profile $PROFILE"

if $AUTO_TUNNEL; then
  banner \
    "Setup complete" \
    "" \
    "Tunnel:     localhost:${LOCAL_PORT} -> ${OKE_ENDPOINT_IP}:${TARGET_PORT} (PID: $SSH_PID)" \
    "Kubeconfig: $KCFG" \
    "Session:    $SESSION_ID" \
    "" \
    "Next steps:" \
    "  1. Set the kubeconfig for your shell:" \
    "     export KUBECONFIG=$KCFG" \
    "  2. Verify cluster access:" \
    "     kubectl get nodes" \
    "" \
    "Cleanup:" \
    "  Stop tunnel + delete session:" \
    "    $CLEANUP_CMD" \
    "  Delete kubeconfig only:" \
    "    $0 --cleanup-kubeconfig --cluster-ocid $CLUSTER_OCID"
else
  banner \
    "Setup complete" \
    "" \
    "Kubeconfig: $KCFG" \
    "Session:    $SESSION_ID" \
    "" \
    "Next steps:" \
    "  1. Start the SSH tunnel (in another terminal):" \
    "     $SSH_CMD" \
    "  2. Set the kubeconfig for your shell:" \
    "     export KUBECONFIG=$KCFG" \
    "  3. Verify cluster access:" \
    "     kubectl get nodes" \
    "" \
    "Cleanup:" \
    "  Delete session:" \
    "    $CLEANUP_CMD" \
    "  Delete kubeconfig only:" \
    "    $0 --cleanup-kubeconfig --cluster-ocid $CLUSTER_OCID"
fi