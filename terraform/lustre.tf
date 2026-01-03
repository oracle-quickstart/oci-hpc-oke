# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  lustre_subnet_cidr = (var.create_lustre ?
    ( var.custom_subnet_ids ?
      one(data.oci_core_subnet.lustre.*.cidr_block) :
      lookup(local.subnets["lustre"], "cidr", cidrsubnet(local.vcn_cidr, lookup(local.subnets["lustre"], "newbits"), lookup(local.subnets["lustre"], "netnum")))
    ) :
    null
  )
  vcn_cidr = coalesce(data.oci_core_vcn.oke_vcn.cidr_blocks...)

  default_lustre_nsg_rules = {
    "Ingress from Lustre 512-1023 to Lustre 988" = {
      protocol             = local.tcp_protocol
      source               = one(oci_core_network_security_group.lustre_nsg[*].id)
      source_type          = local.rule_type_nsg
      source_port_min      = 512
      source_port_max      = 1023
      destination_port_min = 988
      destination_port_max = 988
    }
    "Egress from Lustre 512-1023 to Lustre 988" = {
      protocol             = local.tcp_protocol
      destination          = one(oci_core_network_security_group.lustre_nsg[*].id)
      destination_type     = local.rule_type_nsg
      source_port_min      = 512
      source_port_max      = 1023
      destination_port_min = 988
      destination_port_max = 988
    }
    "Ingress from OKE Workers 512-1023 to Lustre 988" = {
      protocol             = local.tcp_protocol
      source               = local.all_nsg_ids["workers"]
      source_type          = local.rule_type_nsg
      source_port_min      = 512
      source_port_max      = 1023
      destination_port_min = 988
      destination_port_max = 988
    }
    "Egress from Lustre 512-1023 to OKE Workers 988" = {
      protocol             = local.tcp_protocol
      destination          = local.all_nsg_ids["workers"]
      destination_type     = local.rule_type_nsg
      source_port_min      = 512
      source_port_max      = 1023
      destination_port_min = 988
      destination_port_max = 988
    }
  }

  all_nsg_ids = {
    bastion  = module.oke.bastion_nsg_id
    operator = module.oke.operator_nsg_id
    cp       = module.oke.control_plane_nsg_id
    int_lb   = module.oke.int_lb_nsg_id
    pub_lb   = module.oke.pub_lb_nsg_id
    workers  = module.oke.worker_nsg_id
    pods     = module.oke.pod_nsg_id
    fss      = module.oke.fss_nsg_id
  }

  all_lustre_rules = { for x, y in merge(
      local.default_lustre_nsg_rules,
      var.allow_rules_lustre
    ) : x => merge(y, {
      description               = x
      stateless                 = lookup(y, "stateless", false)
      direction                 = contains(keys(y), "source") ? "INGRESS" : "EGRESS"
      protocol                  = lookup(y, "protocol", "16")
      source = (
        alltrue([
          upper(lookup(y, "source_type", "")) == local.rule_type_nsg,
        length(regexall("ocid\\d+\\.networksecuritygroup", lower(lookup(y, "source", "")))) == 0]) ?
        lookup(local.all_nsg_ids, lower(lookup(y, "source", "")), null) :
        lookup(y, "source", null)
      )
      source_type = lookup(y, "source_type", null)
      destination = (
        alltrue([
          upper(lookup(y, "destination_type", "")) == local.rule_type_nsg,
        length(regexall("ocid\\d+\\.networksecuritygroup", lower(lookup(y, "destination", "")))) == 0]) ?
        lookup(local.all_nsg_ids, lower(lookup(y, "destination", "")), null) :
        lookup(y, "destination", null)
      )
      destination_type = lookup(y, "destination_type", null)
  }) }

}

data "oci_core_vcn" "oke_vcn" {
  vcn_id = coalesce(var.vcn_id, module.oke.vcn_id)
}

data "oci_core_subnet" "lustre" {
  count = var.create_lustre && var.custom_subnet_ids ? 1 : 0

  subnet_id = var.lustre_sn_id
}

resource "oci_core_network_security_group" "lustre_nsg" {
  count = var.create_lustre ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = coalesce(var.vcn_id, module.oke.vcn_id)
  display_name   = format("lustre-nsg-%v", local.state_id)

  lifecycle {
    ignore_changes = [defined_tags]
  }
}


resource "oci_core_network_security_group_security_rule" "lustre_rules" {
  for_each                  = var.create_lustre ? local.all_lustre_rules : {}

  network_security_group_id = one(oci_core_network_security_group.lustre_nsg[*].id)

  stateless                 = each.value.stateless
  description               = each.value.description
  destination               = each.value.destination
  destination_type          = each.value.destination_type
  direction                 = each.value.direction
  protocol                  = each.value.protocol
  source                    = each.value.source
  source_type               = each.value.source_type

  dynamic "tcp_options" {
    for_each = (tostring(each.value.protocol) == tostring(local.tcp_protocol) &&
      tonumber(lookup(each.value, "port", 0)) != local.all_ports ? [each.value] : []
    )
    content {
      dynamic "destination_port_range" {
        for_each = (
          (contains(keys(tcp_options.value), "destination_port_min") &&
          contains(keys(tcp_options.value), "destination_port_max")) ||
          (contains(keys(tcp_options.value), "source_port_min") &&
          contains(keys(tcp_options.value), "source_port_max"))
        ) ? [] : [tcp_options.value]
        content {
          min = tonumber(lookup(destination_port_range.value, "port_min", lookup(destination_port_range.value, "port", 0)))
          max = tonumber(lookup(destination_port_range.value, "port_max", lookup(destination_port_range.value, "port", 0)))
        }
      }
      dynamic "destination_port_range" {
        for_each = (contains(keys(tcp_options.value), "destination_port_min") &&
        contains(keys(tcp_options.value), "destination_port_max")) ? [tcp_options.value] : []
        content {
          min = tonumber(lookup(destination_port_range.value, "destination_port_min", 0))
          max = tonumber(lookup(destination_port_range.value, "destination_port_max", 0))
        }
      }
      dynamic "source_port_range" {
        for_each = (contains(keys(tcp_options.value), "source_port_min") &&
        contains(keys(tcp_options.value), "source_port_max")) ? [tcp_options.value] : []
        content {
          min = tonumber(lookup(source_port_range.value, "source_port_min", 0))
          max = tonumber(lookup(source_port_range.value, "source_port_max", 0))
        }
      }
    }
  }

  dynamic "udp_options" {
    for_each = (tostring(each.value.protocol) == tostring(local.udp_protocol) &&
      tonumber(lookup(each.value, "port", 0)) != local.all_ports ? [each.value] : []
    )
    content {
      dynamic "destination_port_range" {
        for_each = (
          (contains(keys(udp_options.value), "destination_port_min") &&
          contains(keys(udp_options.value), "destination_port_max")) ||
          (contains(keys(udp_options.value), "source_port_min") &&
          contains(keys(udp_options.value), "source_port_max"))
        ) ? [] : [udp_options.value]
        content {
          min = tonumber(lookup(destination_port_range.value, "port_min", lookup(destination_port_range.value, "port", 0)))
          max = tonumber(lookup(destination_port_range.value, "port_max", lookup(destination_port_range.value, "port", 0)))
        }
      }
      dynamic "destination_port_range" {
        for_each = (contains(keys(udp_options.value), "destination_port_min") &&
        contains(keys(udp_options.value), "destination_port_max")) ? [udp_options.value] : []
        content {
          min = tonumber(lookup(destination_port_range.value, "destination_port_min", 0))
          max = tonumber(lookup(destination_port_range.value, "destination_port_max", 0))
        }
      }
      dynamic "source_port_range" {
        for_each = (contains(keys(udp_options.value), "source_port_min") &&
        contains(keys(udp_options.value), "source_port_max")) ? [udp_options.value] : []
        content {
          min = tonumber(lookup(source_port_range.value, "source_port_min", 0))
          max = tonumber(lookup(source_port_range.value, "source_port_max", 0))
        }
      }
    }
  }

  dynamic "icmp_options" {
    for_each = tostring(each.value.protocol) == tostring(local.icmp_protocol) ? [1] : []
    content {
      type = 3
      code = 4
    }
  }

  dynamic "icmp_options" {
    for_each = tostring(each.value.protocol) == tostring(local.icmpv6_protocol) ? [1] : []
    content {
      type = 2
      code = 0
    }
  }

  lifecycle {
    precondition {
      condition = contains([tostring(local.icmp_protocol), tostring(local.icmpv6_protocol)], tostring(each.value.protocol)) || contains(keys(each.value), "port") || (
        contains(keys(each.value), "port_min") && contains(keys(each.value), "port_max")) || (
        contains(keys(each.value), "source_port_min") && contains(keys(each.value), "source_port_max") || (
          contains(keys(each.value), "destination_port_min") && contains(keys(each.value), "destination_port_max")
        )
      )
      error_message = "TCP/UDP rule must contain a port or port range: '${each.key}'"
    }

    precondition {
      condition = (
        contains([tostring(local.icmp_protocol), tostring(local.icmpv6_protocol)], tostring(each.value.protocol))
        || can(tonumber(each.value.port))
        || (can(tonumber(each.value.port_min)) && can(tonumber(each.value.port_max)))
        || (can(tonumber(each.value.source_port_min)) && can(tonumber(each.value.source_port_max)))
        || (can(tonumber(each.value.destination_port_min)) && can(tonumber(each.value.destination_port_max)))
      )

      error_message = "TCP/UDP ports must be numeric: '${each.key}'"
    }

    precondition {
      condition     = each.value.direction == "EGRESS" || coalesce(each.value.source, "none") != "none"
      error_message = "Ingress rule must have a source: '${each.key}'"
    }

    precondition {
      condition     = each.value.direction == "INGRESS" || coalesce(each.value.destination, "none") != "none"
      error_message = "Egress rule must have a destination: '${each.key}'"
    }
  }
}

resource "oci_core_subnet" "lustre_subnet" {
  count = var.create_lustre && !var.custom_subnet_ids ? 1 : 0

  cidr_block                 = local.lustre_subnet_cidr
  compartment_id             = var.compartment_ocid
  vcn_id                     = coalesce(var.vcn_id, module.oke.vcn_id)
  display_name               = format("lustre-subnet-%v", local.state_id)
  route_table_id             = module.oke.nat_route_table_id
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
  nsg_ids                    = [one(oci_core_network_security_group.lustre_nsg[*].id)]

  lifecycle {
    ignore_changes = [defined_tags]
  }
}