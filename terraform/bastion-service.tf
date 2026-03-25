# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  oke_private_endpoint_ip = trimsuffix(trimprefix(local.cluster_private_endpoint, "https://"), ":6443")
  workers_subnet_cidr = (var.create_oci_bastion_service && var.bastion_service_allow_worker_ssh ?
    (var.custom_subnet_ids ?
      one(data.oci_core_subnet.workers_bastion_svc[*].cidr_block) :
      lookup(local.subnets["workers"], "cidr", cidrsubnet(local.vcn_cidr, lookup(local.subnets["workers"], "newbits"), lookup(local.subnets["workers"], "netnum")))
    ) :
    null
  )
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
  count = var.create_oci_bastion_service ? 1 : 0

  vcn_id = coalesce(var.vcn_id, module.oke.vcn_id)
}

data "oci_core_subnet" "bastion_service" {
  count = var.create_oci_bastion_service && var.custom_subnet_ids ? 1 : 0

  subnet_id = var.bastion_service_sn_id
}

data "oci_core_subnet" "workers_bastion_svc" {
  count = var.create_oci_bastion_service && var.bastion_service_allow_worker_ssh && var.custom_subnet_ids ? 1 : 0

  subnet_id = var.workers_sn_id
}

resource "oci_core_subnet" "bastion_service" {
  count = var.create_oci_bastion_service && !var.custom_subnet_ids ? 1 : 0

  cidr_block                 = local.bastion_service_subnet_cidr
  compartment_id             = var.compartment_ocid
  vcn_id                     = coalesce(var.vcn_id, module.oke.vcn_id)
  display_name               = format("bastion_svc-%v", local.state_id)
  route_table_id             = module.oke.nat_route_table_id
  prohibit_public_ip_on_vnic = true
  security_list_ids          = [one(oci_core_security_list.bastion_service[*].id)]

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_security_list" "bastion_service" {
  count = var.create_oci_bastion_service ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = one(data.oci_core_vcn.bastion_service_vcn[*].id)
  display_name   = format("bastion_svc-%v", local.state_id)

  ingress_security_rules {
    protocol    = "6"
    source      = local.bastion_service_subnet_cidr
    source_type = "CIDR_BLOCK"

    tcp_options {
      min = 6443
      max = 6443
    }

    description = "Allow TCP 6443 ingress for bastion service internal communication"
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

  dynamic "egress_security_rules" {
    for_each = var.bastion_service_allow_worker_ssh ? [1] : []
    content {
      protocol         = "6"
      destination      = local.workers_subnet_cidr
      destination_type = "CIDR_BLOCK"

      tcp_options {
        min = 22
        max = 22
      }

      description = "Allow SSH egress to worker nodes"
    }
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_network_security_group_security_rule" "bastion_service_worker_ssh" {
  count = var.create_oci_bastion_service && var.bastion_service_allow_worker_ssh ? 1 : 0

  network_security_group_id = module.oke.worker_nsg_id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = local.bastion_service_subnet_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }

  description = "Allow SSH ingress to workers from OCI Bastion Service subnet"
}

resource "oci_bastion_bastion" "bastion_service" {
  count = var.create_oci_bastion_service ? 1 : 0

  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_ocid
  target_subnet_id             = local.bastion_service_subnet_id
  name                         = format("oke-bastion-service-%s", local.state_id)
  client_cidr_block_allow_list = var.bastion_service_allowed_cidrs
  max_session_ttl_in_seconds   = var.bastion_service_max_session_ttl

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
