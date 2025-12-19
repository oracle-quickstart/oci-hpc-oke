# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl


resource "oci_resourcemanager_private_endpoint" "oke" {
  count = var.create_cluster && local.deploy_from_orm ? 1 : 0

  compartment_id = var.compartment_ocid
  display_name   = format("oke-private-endpoint-%v", local.state_id)
  subnet_id      = module.oke.control_plane_subnet_id
  vcn_id         = module.oke.vcn_id

  description                                = "ORM Endpoint used to access the OKE cluster control plane"
  is_used_with_configuration_source_provider = false
  nsg_id_list                                = [module.oke.control_plane_nsg_id]

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

data "oci_resourcemanager_private_endpoint_reachable_ip" "oke" {
  count = var.create_cluster && local.deploy_from_orm ? 1 : 0

  private_endpoint_id = one(oci_resourcemanager_private_endpoint.oke.*.id)
  private_ip          = trimsuffix(trimprefix(local.cluster_private_endpoint, "https://"), ":6443")
}