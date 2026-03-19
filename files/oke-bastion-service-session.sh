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
#   --session-id <ocid>         Reuse an existing bastion session (skip creation)
#   --non-interactive           Fail fast if required inputs are missing
#
# Notes:
#   - Default kubeconfig path: ~/.kube/oke-bastion/<cluster-ocid>.yaml
#   - The script does NOT start the SSH tunnel automatically. Run the printed
#     SSH command in another terminal before using kubectl.
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
KUBECONFIG_OUT="${KUBECONFIG_OUT:-}"
DEFAULT_KUBECONFIG_DIR="$HOME/.kube/oke-bastion"
DEFAULT_KUBECONFIG_FILE=""

NON_INTERACTIVE=false
CLEANUP_KUBECONFIG=false

KCFG=""
SESSION_ID=""
SESSION_ID_OVERRIDE=""

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

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
  --kubeconfig <path>
  --cleanup-kubeconfig
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

prompt_required() {
  local var_name="$1" prompt="$2" default_value="${3:-}"
  local current_value="${!var_name:-}"

  if [[ -z "$current_value" ]]; then
    if $NON_INTERACTIVE; then
      die "Missing required value: ${var_name}"
    fi

    if [[ -n "$default_value" ]]; then
      read -r -p "${prompt} [${default_value}]: " current_value
      current_value="${current_value:-$default_value}"
    else
      read -r -p "${prompt}: " current_value
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
    read -r -p "${prompt}: " current_value
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
    read -r -p "Enter SSH private key path [${SSH_KEY}]: " SSH_KEY_INPUT
    SSH_KEY_INPUT="${SSH_KEY_INPUT:-$SSH_KEY}"
    SSH_KEY="${SSH_KEY_INPUT/#\~/$HOME}"
  done

  if [[ ! -f "${SSH_KEY}.pub" ]]; then
    if $NON_INTERACTIVE; then
      die "Missing SSH public key: ${SSH_KEY}.pub"
    fi
    require_cmd ssh-keygen
    read -r -p "Public key not found. Generate ${SSH_KEY}.pub from private key? [Y/n]: " reply
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
    --kubeconfig)
      KUBECONFIG_OUT="$2"; shift 2; ;;
    --cleanup-kubeconfig)
      CLEANUP_KUBECONFIG=true; shift; ;;
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
  log "Cleanup mode enabled (--cleanup-kubeconfig); other options are ignored."
  prompt_required CLUSTER_OCID "Enter OKE Cluster OCID"
  DEFAULT_KUBECONFIG_FILE="${DEFAULT_KUBECONFIG_DIR}/${CLUSTER_OCID}.yaml"
  if [[ -f "$DEFAULT_KUBECONFIG_FILE" ]]; then
    rm -f "$DEFAULT_KUBECONFIG_FILE"
    log "Deleted kubeconfig: $DEFAULT_KUBECONFIG_FILE"
  else
    log "No kubeconfig found at: $DEFAULT_KUBECONFIG_FILE"
  fi
  exit 0
fi

require_cmd oci
require_cmd kubectl
require_cmd ssh

prompt_required BASTION_OCID "Enter Bastion OCID"
prompt_required CLUSTER_OCID "Enter OKE Cluster OCID"
prompt_required OKE_ENDPOINT_IP "Enter OKE private endpoint IP (e.g., 10.140.0.6)"

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

if [[ -n "$KUBECONFIG_OUT" ]]; then
  KCFG="$KUBECONFIG_OUT"
  mkdir -p "$(dirname "$KCFG")"
else
  mkdir -p "$DEFAULT_KUBECONFIG_DIR"
  KCFG="$DEFAULT_KUBECONFIG_FILE"
fi

if [[ -n "$SESSION_ID_OVERRIDE" ]]; then
  SESSION_ID="$SESSION_ID_OVERRIDE"
  log "1) Reusing Bastion session: $SESSION_ID"
else
  log "1) Creating Bastion port-forwarding session to ${OKE_ENDPOINT_IP}:6443 ..."
  CREATE_OUTPUT=$(
    oci "${OCI_COMMON_ARGS[@]}" bastion session create-port-forwarding \
      --bastion-id "$BASTION_OCID" \
      --target-private-ip "$OKE_ENDPOINT_IP" \
      --target-port 6443 \
      --ssh-public-key-file "${SSH_KEY}.pub" \
      --session-ttl "$TTL_SECONDS" \
      --query 'data.id' --raw-output 2>&1
  ) || {
    die "Bastion session create failed:\n${CREATE_OUTPUT}"
  }
  SESSION_ID="$CREATE_OUTPUT"
fi

if [[ -z "$SESSION_ID" || "$SESSION_ID" == "null" ]]; then
  die "Failed to create bastion session. Check OCI CLI output and permissions."
fi

log "   Session OCID: $SESSION_ID"

log "2) Checking session state..."
SESSION_STATE=""
SESSION_TIMEOUT=300
START_TIME=$SECONDS
while (( SECONDS - START_TIME < SESSION_TIMEOUT )); do
  SESSION_STATE_OUT=$(
    oci "${OCI_COMMON_ARGS[@]}" bastion session get \
      --session-id "$SESSION_ID" \
      --query 'data."lifecycle-state"' --raw-output 2>&1
  ) || {
    die "Failed to read bastion session state:\n${SESSION_STATE_OUT}"
  }
  SESSION_STATE="$SESSION_STATE_OUT"
  log "   Session state: $SESSION_STATE"
  if [[ "$SESSION_STATE" == "ACTIVE" ]]; then
    break
  fi
  if [[ "$SESSION_STATE" == "FAILED" || "$SESSION_STATE" == "DELETED" ]]; then
    die "Bastion session is in state: $SESSION_STATE"
  fi
  if [[ -n "$SESSION_ID_OVERRIDE" && "$SESSION_STATE" != "CREATING" ]]; then
    die "Bastion session is not ACTIVE. Current state: $SESSION_STATE"
  fi
  sleep 2
done

if [[ "$SESSION_STATE" != "ACTIVE" ]]; then
  die "Bastion session did not become ACTIVE in ${SESSION_TIMEOUT}s"
fi

log "3) Fetching SSH command for the session..."
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
SSH_CMD="${SSH_CMD//<targetPort>/6443}"
SSH_CMD="${SSH_CMD//<targetHost>/$OKE_ENDPOINT_IP}"
SSH_CMD="${SSH_CMD//<targetPrivateIp>/$OKE_ENDPOINT_IP}"

if ! grep -qE '(^| )-i ' <<<"$SSH_CMD"; then
  SSH_CMD="$SSH_CMD -i $SSH_KEY"
fi
if ! grep -qE '(^| )-L ' <<<"$SSH_CMD"; then
  SSH_CMD="$SSH_CMD -N -L ${LOCAL_PORT}:${OKE_ENDPOINT_IP}:6443"
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

log "4) SSH tunnel command (run this in another terminal):"
log "   $SSH_CMD"

log "5) Generating kubeconfig: $KCFG"
oci "${OCI_COMMON_ARGS[@]}" ce cluster create-kubeconfig \
  --cluster-id "$CLUSTER_OCID" \
  --token-version 2.0.0 \
  --kube-endpoint PRIVATE_ENDPOINT \
  --file "$KCFG"

log "6) Pointing kubeconfig server to localhost tunnel..."
CLUSTER_NAME="$(kubectl config view --kubeconfig "$KCFG" -o jsonpath='{.clusters[0].name}' 2>/dev/null || true)"
if [[ -z "$CLUSTER_NAME" ]]; then
  die "Failed to detect cluster name in kubeconfig."
fi
kubectl config set-cluster "$CLUSTER_NAME" --server "https://127.0.0.1:${LOCAL_PORT}" --kubeconfig "$KCFG" >/dev/null

log "Kubeconfig written to: $KCFG"
log "Next steps:"
log "  1) Run the SSH tunnel command above in a terminal"
log "  2) In a separate terminal, run the below two commands"
log "  a) export KUBECONFIG=$KCFG"
log "  b) kubectl get nodes"
log "To delete this kubeconfig, re-run with: --cleanup-kubeconfig"