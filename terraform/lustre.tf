# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  default_lustre_nsg_rules = merge(var.allow_rules_lustre, {
    "Ingress from Lustre 512-1023 to Lustre 988" = {
      protocol             = local.tcp_protocol
      source               = "lustre"
      source_type          = local.rule_type_nsg
      source_port_min      = 512
      source_port_max      = 1023
      destination_port_min = 988
      destination_port_max = 988
    }
    "Egress from Lustre 512-1023 to Lustre 988" = {
      protocol             = local.tcp_protocol
      destination          = "lustre"
      destination_type     = local.rule_type_nsg
      source_port_min      = 512
      source_port_max      = 1023
      destination_port_min = 988
      destination_port_max = 988
    }
    "Ingress from OKE Workers 512-1023 to Lustre 988" = {
      protocol             = local.tcp_protocol
      source               = "workers"
      source_type          = local.rule_type_nsg
      source_port_min      = 512
      source_port_max      = 1023
      destination_port_min = 988
      destination_port_max = 988
    }
    "Egress from Lustre 512-1023 to OKE Workers 988" = {
      protocol             = local.tcp_protocol
      destination          = "workers"
      destination_type     = local.rule_type_nsg
      source_port_min      = 512
      source_port_max      = 1023
      destination_port_min = 988
      destination_port_max = 988
    }
  }, var.create_operator ? {
    "Ingress from OKE Operator 512-1023 to Lustre 988" = {
      protocol             = local.tcp_protocol
      source               = "operator"
      source_type          = local.rule_type_nsg
      source_port_min      = 512
      source_port_max      = 1023
      destination_port_min = 988
      destination_port_max = 988
    }
    "Egress from Lustre 512-1023 to Operator 988" = {
      protocol             = local.tcp_protocol
      destination          = "operator"
      destination_type     = local.rule_type_nsg
      source_port_min      = 512
      source_port_max      = 1023
      destination_port_min = 988
      destination_port_max = 988
    }
  } : {})
}

resource "time_sleep" "wait_for_lustre_prerequisites" {
  count = var.create_lustre ? 1 : 0

  depends_on = [
    oci_identity_policy.lustre_service_network,
  ]

  create_duration = "75s"
}

resource "oci_lustre_file_storage_lustre_file_system" "lustre" {
  count = var.create_lustre ? 1 : 0

  availability_domain = coalesce(var.lustre_ad, var.worker_ops_ad)
  capacity_in_gbs     = var.lustre_size_in_tb * 1000
  compartment_id      = var.compartment_ocid
  file_system_name    = var.lustre_file_system_name
  performance_tier    = format("MBPS_PER_TB_%d", var.lustre_performance_tier)
  root_squash_configuration {
    identity_squash = "NONE"

    # client_exceptions = var.lustre_file_system_root_squash_configuration_client_exceptions
    # squash_gid = var.lustre_file_system_root_squash_configuration_squash_gid
    # squash_uid = var.lustre_file_system_root_squash_configuration_squash_uid
  }
  subnet_id                  = var.lustre_sn_id != null ? var.lustre_sn_id : lookup(module.oke.subnet_ids, "lustre", null)
  cluster_placement_group_id = var.lustre_cluster_placement_group_id
  display_name               = format("lustre-fs-%s", local.state_id)
  nsg_ids                    = compact([lookup(module.oke.custom_nsg_ids, "lustre", null)])

  depends_on = [time_sleep.wait_for_lustre_prerequisites]

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
