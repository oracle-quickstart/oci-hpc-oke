# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  oke_private_endpoint_ip = trimsuffix(trimprefix(local.cluster_private_endpoint, "https://"), ":6443")
  bastion_service_subnet_cidr = (var.create_oci_bastion_service ?
    (var.custom_subnet_ids ?
      one(data.oci_core_subnet.bastion_service.*.cidr_block) :
      lookup(local.subnets["bastion_service"], "cidr", cidrsubnet(local.vcn_cidr, lookup(local.subnets["bastion_service"], "newbits"), lookup(local.subnets["bastion_service"], "netnum")))
    ) :
    null
  )
  bastion_service_subnet_id = (var.create_oci_bastion_service ?
    (var.custom_subnet_ids ?
      var.bastion_service_sn_id :
      one(oci_core_subnet.bastion_service[*].id)
    ) :
    null
  )
}

data "oci_core_vcn" "bastion_service_vcn" {
  vcn_id = coalesce(var.vcn_id, module.oke.vcn_id)
}

data "oci_core_subnet" "bastion_service" {
  count = var.create_oci_bastion_service && var.custom_subnet_ids ? 1 : 0

  subnet_id = var.bastion_service_sn_id
}

resource "oci_core_subnet" "bastion_service" {
  count = var.create_oci_bastion_service && !var.custom_subnet_ids ? 1 : 0

  cidr_block                 = local.bastion_service_subnet_cidr
  compartment_id             = var.compartment_ocid
  vcn_id                     = coalesce(var.vcn_id, module.oke.vcn_id)
  display_name               = format("bastion_svc-%v", local.state_id)
  route_table_id             = module.oke.nat_route_table_id
  prohibit_public_ip_on_vnic = true

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_default_security_list" "bastion_service_default" {
  count = var.create_oci_bastion_service ? 1 : 0

  manage_default_resource_id = data.oci_core_vcn.bastion_service_vcn.default_security_list_id

  ingress_security_rules {
    protocol    = "6"
    source      = local.bastion_service_subnet_cidr
    source_type = "CIDR_BLOCK"

    tcp_options {
      min = 6443
      max = 6443
    }

    description = "Allow TCP 6443 ingress from bastion service subnet"
  }

  egress_security_rules {
    protocol         = "6"
    destination      = format("%s/32", local.oke_private_endpoint_ip)
    destination_type = "CIDR_BLOCK"

    tcp_options {
      min = 6443
      max = 6443
    }

    description = "Allow TCP 6443 egress to OKE private endpoint"
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}