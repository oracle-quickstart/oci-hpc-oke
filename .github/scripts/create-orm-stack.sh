#!/usr/bin/env bash
set -euo pipefail

# Create an ORM stack from stack.zip and variables.json.
# Reads env: OCI_COMPARTMENT_OCID, GITHUB_RUN_ID, TOPOLOGY, GITHUB_ENV
#            STACK_NAME_PREFIX (optional, default: "ci-orm")
# Writes STACK_ID=<ocid> to $GITHUB_ENV.

PREFIX="${STACK_NAME_PREFIX:-ci-orm}"
DISPLAY_NAME="${PREFIX}-${GITHUB_RUN_ID}-${TOPOLOGY}"

STACK_ID=$(oci resource-manager stack create \
  --compartment-id "$OCI_COMPARTMENT_OCID" \
  --display-name "$DISPLAY_NAME" \
  --config-source stack.zip \
  --variables "file://variables.json" \
  --terraform-version "1.5.x" \
  --query 'data.id' \
  --raw-output)

echo "STACK_ID=$STACK_ID" >> "$GITHUB_ENV"
echo "Created stack: $STACK_ID"
