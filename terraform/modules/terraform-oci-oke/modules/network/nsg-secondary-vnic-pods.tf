# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  secondary_vnic_pod_subnet_keys = toset([
    for key, subnet in var.subnets : key
    if alltrue([
      var.create_cluster,
      var.cni_type == "npn",
      try(tobool(subnet.secondary_vnic_pod_subnet), false),
    ])
  ])

  secondary_vnic_pod_nsg_ids = {
    for key, nsg in oci_core_network_security_group.secondary_vnic_pods : key => nsg.id
  }

  secondary_vnic_pod_nsg_rules = merge(
    length(local.secondary_vnic_pod_nsg_ids) > 0 ? merge([
      for pod_key, pod_nsg_id in local.secondary_vnic_pod_nsg_ids : {
        "Allow TCP egress from secondary VNIC pods ${pod_key} to Kubernetes API server" = {
          nsg_id = pod_nsg_id, protocol = local.tcp_protocol, port = local.apiserver_port, destination = local.control_plane_nsg_id, destination_type = local.rule_type_nsg,
        }
        "Allow ALL ingress to secondary VNIC pods ${pod_key} from Kubernetes control plane for webhooks served by pods" = {
          nsg_id = pod_nsg_id, protocol = local.all_protocols, port = local.all_ports, source = local.control_plane_nsg_id, source_type = local.rule_type_nsg,
        }
        "Allow ALL egress from secondary VNIC pods ${pod_key} to workers" = {
          nsg_id = pod_nsg_id, protocol = local.all_protocols, port = local.all_ports, destination = local.worker_nsg_id, destination_type = local.rule_type_nsg,
        }
        "Allow ALL ingress to secondary VNIC pods ${pod_key} from workers" = {
          nsg_id = pod_nsg_id, protocol = local.all_protocols, port = local.all_ports, source = local.worker_nsg_id, source_type = local.rule_type_nsg,
        }
        "Allow ICMP egress from secondary VNIC pods ${pod_key} for path discovery" = {
          nsg_id = pod_nsg_id, protocol = local.icmp_protocol, port = local.all_ports, destination = local.anywhere, destination_type = local.rule_type_cidr,
        }
        "Allow ICMP ingress to secondary VNIC pods ${pod_key} for path discovery" = {
          nsg_id = pod_nsg_id, protocol = local.icmp_protocol, port = local.all_ports, source = local.anywhere, source_type = local.rule_type_cidr,
        }
      }
    ]...) : {},

    length(local.secondary_vnic_pod_nsg_ids) > 0 ? merge(flatten([
      for source_key, source_nsg_id in local.secondary_vnic_pod_nsg_ids : [
        for destination_key, destination_nsg_id in local.secondary_vnic_pod_nsg_ids : {
          "Allow ALL egress from secondary VNIC pods ${source_key} to secondary VNIC pods ${destination_key}" = {
            nsg_id = source_nsg_id, protocol = local.all_protocols, port = local.all_ports, destination = destination_nsg_id, destination_type = local.rule_type_nsg,
          }
          "Allow ALL ingress to secondary VNIC pods ${destination_key} from secondary VNIC pods ${source_key}" = {
            nsg_id = destination_nsg_id, protocol = local.all_protocols, port = local.all_ports, source = source_nsg_id, source_type = local.rule_type_nsg,
          }
        }
      ]
    ])...) : {},

    length(local.secondary_vnic_pod_nsg_ids) > 0 ? merge([
      for pod_key, pod_nsg_id in local.secondary_vnic_pod_nsg_ids : {
        "Allow TCP ingress to kube-apiserver from secondary VNIC pods ${pod_key}" = {
          nsg_id = local.control_plane_nsg_id, protocol = local.tcp_protocol, port = local.apiserver_port, source = pod_nsg_id, source_type = local.rule_type_nsg,
        }
        "Allow TCP ingress to OKE control plane from secondary VNIC pods ${pod_key}" = {
          nsg_id = local.control_plane_nsg_id, protocol = local.tcp_protocol, port = local.oke_port, source = pod_nsg_id, source_type = local.rule_type_nsg,
        }
        "Allow TCP egress from OKE control plane to secondary VNIC pods ${pod_key}" = {
          nsg_id = local.control_plane_nsg_id, protocol = local.tcp_protocol, port = local.all_ports, destination = pod_nsg_id, destination_type = local.rule_type_nsg,
        }
        "Allow ALL ingress to workers from secondary VNIC pods ${pod_key}" = {
          nsg_id = local.worker_nsg_id, protocol = local.all_protocols, port = local.all_ports, source = pod_nsg_id, source_type = local.rule_type_nsg,
        }
        "Allow ALL egress from workers to secondary VNIC pods ${pod_key}" = {
          nsg_id = local.worker_nsg_id, protocol = local.all_protocols, port = local.all_ports, destination = pod_nsg_id, destination_type = local.rule_type_nsg,
        }
      }
    ]...) : {},

    var.enable_ipv6 && length(local.secondary_vnic_pod_nsg_ids) > 0 ? merge([
      for pod_key, pod_nsg_id in local.secondary_vnic_pod_nsg_ids : {
        "Allow ICMPv6 ingress to secondary VNIC pods ${pod_key} for path discovery" = {
          nsg_id = pod_nsg_id, protocol = local.icmpv6_protocol, port = local.all_ports, source = local.anywhere_ipv6, source_type = local.rule_type_cidr,
        }
        "Allow ICMPv6 egress from secondary VNIC pods ${pod_key} for path discovery" = {
          nsg_id = pod_nsg_id, protocol = local.icmpv6_protocol, port = local.all_ports, destination = local.anywhere_ipv6, destination_type = local.rule_type_cidr,
        }
      }
    ]...) : {}
  )
}

resource "oci_core_network_security_group" "secondary_vnic_pods" {
  for_each = local.secondary_vnic_pod_subnet_keys

  compartment_id = var.compartment_id
  display_name   = "${each.key}-pods-${var.state_id}"
  vcn_id         = var.vcn_id
  defined_tags   = var.defined_tags
  freeform_tags  = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags, display_name, vcn_id]
  }
}

output "secondary_vnic_pod_nsg_ids" {
  value = local.secondary_vnic_pod_nsg_ids
}
