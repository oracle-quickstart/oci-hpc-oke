#!/usr/bin/env bash
set -euo pipefail

# Validate Terraform/ORM outputs by topology.
# Usage: assert-outputs.sh <state-file> <prefix>
#   prefix: "" for TF (jq: .key.value), "outputs." for ORM (jq: .outputs.key.value)
# Env: TOPOLOGY

STATE_FILE="${1:?Usage: $0 <state-file> <prefix>}"
PREFIX="${2:-}"

FAILED=0

check_ocid() {
  local key=$1
  local val
  val=$(jq -r ".${PREFIX}${key}.value // empty" "$STATE_FILE")
  if [[ -z "$val" || "$val" == "null" ]]; then
    echo "FAIL: $key is empty"
    FAILED=1; return
  fi
  if [[ "$val" != ocid1.* ]] || [[ $(echo "$val" | tr -cd '.' | wc -c) -lt 4 ]]; then
    echo "FAIL: $key is not a valid OCID: $val"
    FAILED=1; return
  fi
  echo "OK:   $key = $val"
}

# Common checks for all topologies
check_ocid cluster_id
check_ocid vcn_id
check_ocid worker_subnet_id
check_ocid worker_nsg_id
check_ocid control_plane_subnet_id
check_ocid control_plane_nsg_id
check_ocid int_lb_subnet_id
check_ocid int_lb_nsg_id
check_ocid worker_ops_pool_id

PRIVATE_EP=$(jq -r ".${PREFIX}cluster_private_endpoint.value // empty" "$STATE_FILE")
if [[ "$PRIVATE_EP" != https://* ]]; then
  echo "FAIL: cluster_private_endpoint does not start with https://: $PRIVATE_EP"
  FAILED=1
else
  echo "OK:   cluster_private_endpoint = $PRIVATE_EP"
fi

# Public topology checks
if [[ "$TOPOLOGY" == public* ]]; then
  PUBLIC_EP=$(jq -r ".${PREFIX}cluster_public_endpoint.value // empty" "$STATE_FILE")
  if [[ "$PUBLIC_EP" != https://* ]]; then
    echo "FAIL: cluster_public_endpoint does not start with https://: $PUBLIC_EP"
    FAILED=1
  else
    echo "OK:   cluster_public_endpoint = $PUBLIC_EP"
  fi
  check_ocid pub_lb_subnet_id
  check_ocid pub_lb_nsg_id
fi

# Private topology checks
if [[ "$TOPOLOGY" == private* ]]; then
  PUBLIC_EP=$(jq -r ".${PREFIX}cluster_public_endpoint.value // empty" "$STATE_FILE")
  if [ -n "$PUBLIC_EP" ]; then
    echo "FAIL: cluster_public_endpoint should be empty for private topology: $PUBLIC_EP"
    FAILED=1
  else
    echo "OK:   cluster_public_endpoint is empty (private topology)"
  fi
fi

# Determine if this topology can create PVs (used by FSS and Lustre checks).
# ORM deployments always have kubectl access (ORM manages the private endpoint).
# TF public topologies have kubectl access via the Kubernetes provider.
# TF private topologies need an operator node for PV creation.
CAN_CREATE_PV=true
if [[ -z "$PREFIX" && "$TOPOLOGY" == private* ]]; then
  OPERATOR_ID=$(jq -r ".operator_id.value // empty" "$STATE_FILE")
  if [[ -z "$OPERATOR_ID" ]]; then
    CAN_CREATE_PV=false
  fi
fi

# FSS topology checks
if [[ "$TOPOLOGY" == *fss* ]]; then
  check_ocid fss_file_system_id
  check_ocid fss_nsg_id
  check_ocid fss_subnet_id

  FSS_MT_IP=$(jq -r ".${PREFIX}fss_mount_target_ip.value // empty" "$STATE_FILE")
  if [[ -z "$FSS_MT_IP" || ! "$FSS_MT_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "FAIL: fss_mount_target_ip is not a valid IPv4: $FSS_MT_IP"
    FAILED=1
  else
    echo "OK:   fss_mount_target_ip = $FSS_MT_IP"
  fi

  FSS_EXPORT_PATH=$(jq -r ".${PREFIX}fss_export_path.value // empty" "$STATE_FILE")
  if [[ -z "$FSS_EXPORT_PATH" || "$FSS_EXPORT_PATH" != /oke-gpu-* ]]; then
    echo "FAIL: fss_export_path has unexpected format: $FSS_EXPORT_PATH"
    FAILED=1
  else
    echo "OK:   fss_export_path = $FSS_EXPORT_PATH"
  fi

  # Verify FSS PV exists in state.
  if [[ "$CAN_CREATE_PV" == "true" ]]; then
    FSS_PV_FOUND=false
    if [[ -n "$PREFIX" ]]; then
      PV_COUNT=$(jq '[.resources[] | select(
        (.type == "kubernetes_persistent_volume_v1" and .name == "fss") or
        (.type == "null_resource" and .name == "fss_pv_via_operator")
      )] | length' "$STATE_FILE")
      [[ "$PV_COUNT" -ge 1 ]] && FSS_PV_FOUND=true
    else
      TF_STATE=$(terraform -chdir=terraform state list 2>/dev/null || true)
      if echo "$TF_STATE" | grep -q 'kubernetes_persistent_volume_v1.fss' ||
         echo "$TF_STATE" | grep -q 'null_resource.fss_pv_via_operator'; then
        FSS_PV_FOUND=true
      fi
    fi
    if [[ "$FSS_PV_FOUND" != "true" ]]; then
      echo "FAIL: FSS PersistentVolume not found in state"
      FAILED=1
    else
      echo "OK:   FSS PersistentVolume resource found in state"
    fi
  else
    echo "SKIP: private topology without operator, FSS PV not expected"
  fi
fi

# Lustre topology checks
if [[ "$TOPOLOGY" == *lustre* ]]; then
  check_ocid lustre_subnet_id
  check_ocid lustre_nsg_id
  check_ocid lustre_file_system_id

  LUSTRE_MGS=$(jq -r ".${PREFIX}lustre_management_service_address.value // empty" "$STATE_FILE")
  if [[ -z "$LUSTRE_MGS" || ! "$LUSTRE_MGS" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "FAIL: lustre_management_service_address is not a valid IPv4: $LUSTRE_MGS"
    FAILED=1
  else
    echo "OK:   lustre_management_service_address = $LUSTRE_MGS"
  fi

  # Verify Lustre PV exists in state (same CAN_CREATE_PV logic as FSS above).
  if [[ "$CAN_CREATE_PV" == "true" ]]; then
    LUSTRE_PV_FOUND=false
    if [[ -n "$PREFIX" ]]; then
      PV_COUNT=$(jq '[.resources[] | select(
        (.type == "kubectl_manifest" and .name == "lustre_pv") or
        (.type == "null_resource" and .name == "lustre_pv_via_operator")
      )] | length' "$STATE_FILE")
      [[ "$PV_COUNT" -ge 1 ]] && LUSTRE_PV_FOUND=true
    else
      TF_STATE=${TF_STATE:-$(terraform -chdir=terraform state list 2>/dev/null || true)}
      if echo "$TF_STATE" | grep -q 'kubectl_manifest.lustre_pv' ||
         echo "$TF_STATE" | grep -q 'null_resource.lustre_pv_via_operator'; then
        LUSTRE_PV_FOUND=true
      fi
    fi
    if [[ "$LUSTRE_PV_FOUND" != "true" ]]; then
      echo "FAIL: Lustre PersistentVolume not found in state"
      FAILED=1
    else
      echo "OK:   Lustre PersistentVolume resource found in state"
    fi
  else
    echo "SKIP: private topology without operator, Lustre PV not expected"
  fi
fi

# Monitoring topology checks
if [[ "$TOPOLOGY" == *monitoring* ]]; then
  check_ocid pub_lb_subnet_id
  check_ocid pub_lb_nsg_id

  GRAFANA_URL=$(jq -r ".${PREFIX}grafana_url.value // empty" "$STATE_FILE")
  if [[ "$GRAFANA_URL" != http* ]]; then
    echo "FAIL: grafana_url is not a valid URL: $GRAFANA_URL"
    FAILED=1
  else
    echo "OK:   grafana_url = $GRAFANA_URL"
  fi

  GRAFANA_PASS=$(jq -r ".${PREFIX}grafana_admin_password.value // empty" "$STATE_FILE")
  if [ -z "$GRAFANA_PASS" ]; then
    echo "FAIL: grafana_admin_password is empty"
    FAILED=1
  else
    echo "OK:   grafana_admin_password is set"
  fi
fi

[ "$FAILED" -eq 0 ] || exit 1
