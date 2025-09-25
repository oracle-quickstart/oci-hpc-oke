# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  lustre_subnet_cidr = (var.create_lustre ?
    (var.lustre_sn_id != null ?
      one(data.oci_core_subnet.lustre.*.cidr_block) :
      lookup(local.subnets["lustre"], "cidr", cidrsubnet(local.vcn_cidr, lookup(local.subnets["lustre"], "newbits"), lookup(local.subnets["lustre"], "netnum")))
    ) :
    null
  )
  vcn_cidr = coalesce(data.oci_core_vcn.oke_vcn.cidr_blocks...)
}

data "oci_core_vcn" "oke_vcn" {
  vcn_id = coalesce(var.vcn_id, module.oke.vcn_id)
}

data "oci_core_subnet" "lustre" {
  count = var.create_lustre && var.lustre_sn_id != null ? 1 : 0

  subnet_id = var.lustre_sn_id
}

resource "oci_core_security_list" "lustre_sl" {
  count = var.create_lustre ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = coalesce(var.vcn_id, module.oke.vcn_id)
  display_name   = format("lustre-sl-%v", local.state_id)

  egress_security_rules {
    destination      = local.vcn_cidr
    protocol         = "6"
    description      = "Allow Lustre svc egress to VCN CIDR"
    destination_type = "CIDR_BLOCK"
    stateless        = false
    tcp_options {
      max = 988
      min = 988
      source_port_range {
        max = 1023
        min = 512
      }
    }
  }

  ingress_security_rules {
    protocol    = "1"
    source      = local.lustre_subnet_cidr
    description = "Allow ICMP PMTUD for IPv4"
    icmp_options {
      type = 3
      code = 4
    }
    source_type = "CIDR_BLOCK"
    stateless   = false
  }

  ingress_security_rules {
    protocol    = "6"
    source      = local.vcn_cidr
    description = "Allow Lustre svc ingress from VCN CIDR"
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      max = 988
      min = 988
      source_port_range {
        max = 1023
        min = 512
      }
    }
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_subnet" "lustre_subnet" {
  count = var.create_lustre && var.lustre_sn_id == null ? 1 : 0

  cidr_block                 = local.lustre_subnet_cidr
  compartment_id             = var.compartment_ocid
  vcn_id                     = coalesce(var.vcn_id, module.oke.vcn_id)
  display_name               = format("lustre-subnet-%v", local.state_id)
  route_table_id             = module.oke.nat_route_table_id
  security_list_ids          = [one(oci_core_security_list.lustre_sl[*].id)]
  prohibit_public_ip_on_vnic = true

  lifecycle {
    ignore_changes = [defined_tags]
  }
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
  subnet_id                  = var.lustre_sn_id != null ? var.lustre_sn_id : one(oci_core_subnet.lustre_subnet[*].id)
  cluster_placement_group_id = var.lustre_cluster_placement_group_id
  display_name               = format("lustre-fs-%s", local.state_id)
  # nsg_ids                    = [ module.oke.lustre_nsg_id ]

  lifecycle {
    ignore_changes = [defined_tags]
  }
}