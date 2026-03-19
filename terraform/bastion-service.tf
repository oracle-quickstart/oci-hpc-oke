# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "oci_bastion_bastion" "bastion_service" {
  count = var.create_oci_bastion_service ? 1 : 0

  bastion_type     = "STANDARD"
  compartment_id   = var.compartment_ocid
  target_subnet_id = local.bastion_service_subnet_id
  name             = format("oke-bastion-service-%s", local.state_id)
  client_cidr_block_allow_list = var.bastion_service_allowed_cidrs
  max_session_ttl_in_seconds   = 10800

  lifecycle {
    ignore_changes = [defined_tags]
  }
}