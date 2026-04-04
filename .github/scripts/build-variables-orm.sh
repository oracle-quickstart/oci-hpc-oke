#!/usr/bin/env bash
set -euo pipefail

TFVARS_FILE="test/tfvars/orm/${TOPOLOGY}.json"
if [ ! -f "$TFVARS_FILE" ]; then
  echo "Unknown topology: $TOPOLOGY (no file at $TFVARS_FILE)" && exit 1
fi

jq -n \
  --arg tenancy_ocid               "$OCI_TENANCY_OCID" \
  --arg region                     "$OCI_REGION" \
  --arg home_region                "$OCI_REGION" \
  --arg compartment_ocid           "$OCI_COMPARTMENT_OCID" \
  --arg current_user_ocid          "$OCI_USER_OCID" \
  --arg worker_ops_ad              "$WORKER_OPS_AD" \
  --arg worker_ops_image_custom_id "$WORKER_OPS_IMAGE_CUSTOM_ID" \
  --arg ssh_public_key             "$SSH_PUBLIC_KEY" \
  '{
    tenancy_ocid:               $tenancy_ocid,
    region:                     $region,
    home_region:                $home_region,
    compartment_ocid:           $compartment_ocid,
    current_user_ocid:          $current_user_ocid,
    worker_ops_ad:              $worker_ops_ad,
    worker_ops_image_custom_id: $worker_ops_image_custom_id,
    ssh_public_key:             $ssh_public_key
  }' > secrets.json

echo "$OVERRIDES_JSON" > overrides.json
jq -s '.[0] * .[1] * .[2]' "$TFVARS_FILE" secrets.json overrides.json > variables.json
echo "Variables for topology '$TOPOLOGY' (secrets redacted):"
jq 'del(.ssh_public_key, .tenancy_ocid, .compartment_ocid, .current_user_ocid)' variables.json
