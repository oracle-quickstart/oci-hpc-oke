#!/usr/bin/env bash
set -euo pipefail

mkdir -p ~/.oci
printf '[DEFAULT]\nuser=%s\nfingerprint=%s\ntenancy=%s\nregion=%s\nkey_file=%s\n' \
  "$OCI_USER_OCID" \
  "$OCI_API_KEY_FINGERPRINT" \
  "$OCI_TENANCY_OCID" \
  "$OCI_REGION" \
  "$HOME/.oci/oci_api_key.pem" > ~/.oci/config
printf '%s' "$OCI_API_KEY_PRIVATE_KEY" > ~/.oci/oci_api_key.pem
chmod 600 ~/.oci/oci_api_key.pem ~/.oci/config
