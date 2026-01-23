# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

data "oci_identity_availability_domains" "all" {
  compartment_id = var.tenancy_ocid
}

data "oci_identity_dynamic_groups" "all" {
  compartment_id = var.tenancy_ocid
}

resource "random_string" "state_id" {
  length  = 6
  lower   = true
  numeric = false
  special = false
  upper   = false
}


locals {
  dynamic_groups_list = data.oci_identity_dynamic_groups.all.dynamic_groups
  state_id             = random_string.state_id.id
  service_account_name = format("oke-%s-svcacct", local.state_id)
  
  group_name = var.dynamic_group_id == null ? format("oke-gpu-%v", local.state_id) : local.dynamic_groups_list[index(local.dynamic_groups_list[*].id, var.dynamic_group_id)]["name"]
 
  storage_group_name   = format("oke-gpu-%v-storage", local.state_id)
  compartment_matches  = format("instance.compartment.id = '%v'", var.compartment_ocid)
  compartment_rule     = format("ANY {%v}", join(", ", [local.compartment_matches]))

  rule_templates = compact([
    "Allow dynamic-group %v to manage cluster-node-pools in compartment id %v",
    "Allow dynamic-group %v to manage cluster-family in compartment id %v",
    "Allow dynamic-group %v to manage file-family in compartment id %v",
    "Allow dynamic-group %v to manage compute-management-family in compartment id %v",
    "Allow dynamic-group %v to manage instance-family in compartment id %v",
    "Allow dynamic-group %v to manage volume-family in compartment id %v",
    "Allow dynamic-group %v to use ons-topics in compartment id %v",
    "Allow dynamic-group %v to use subnets in compartment id %v",
    "Allow dynamic-group %v to use virtual-network-family in compartment id %v",
    "Allow dynamic-group %v to use vnics in compartment id %v",
    "Allow dynamic-group %v to use network-security-groups in compartment id %v",
    "Allow dynamic-group %v to inspect compartments in compartment id %v",
    "Allow dynamic-group %v to {CLUSTER_JOIN} in compartment id %v",
    "Allow dynamic-group %v to read metrics in compartment id %v",
    "Allow dynamic-group %v to use metrics in compartment id %v where target.metrics.namespace='gpu_infrastructure_health'",
    "Allow dynamic-group %v to use metrics in compartment id %v where target.metrics.namespace='rdma_infrastructure_health'",
    var.setup_credential_provider_for_ocir ? "Allow dynamic-group %v to read repos in compartment id %v" : ""
  ])

  wris_template = [
    "request.principal.type = 'workload'",
    format("request.principal.service_account = '%v'", local.service_account_name),
    format("request.principal.cluster_id = '%v'", one(module.oke[*].cluster_id))
  ]
  wris = one(module.oke[*].cluster_id) == null ? null : format("{ %v }", join(", ", local.wris_template))

  wris_ca_template = [
    "request.principal.type = 'workload'",
    "request.principal.service_account = 'cluster-autoscaler'",
    format("request.principal.cluster_id = '%v'", one(module.oke[*].cluster_id))
  ]
  wris_ca = one(module.oke[*].cluster_id) == null ? null : format("{ %v }", join(", ", local.wris_ca_template))

  wris_statement = format("Allow any-user to manage all-resources in compartment id %v where all %v",
  var.compartment_ocid, local.wris)
  wris_ca_statement = format("Allow any-user to manage all-resources in compartment id %v where all %v",
  var.compartment_ocid, local.wris_ca)

  policy_statements = compact(concat(
    [for s in local.rule_templates : format(s, local.group_name, var.compartment_ocid)],
    [local.wris_statement, local.wris_ca_statement]
  ))
}

resource "oci_identity_dynamic_group" "oke_quickstart_all" {
  provider       = oci.home
  count          = var.create_policies && var.dynamic_group_id == null ? 1 : 0
  compartment_id = var.tenancy_ocid # dynamic groups exist in root compartment (tenancy)
  name           = local.group_name
  description    = format("Dynamic group of instances for OKE Terraform state %v", local.state_id)
  matching_rule  = local.compartment_rule
  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "oke_quickstart_all" {
  provider       = oci.home
  count          = var.create_policies ? 1 : 0
  compartment_id = var.compartment_ocid
  name           = format("oke-gpu-%v-policy", local.state_id)
  description    = format("Policies for OKE Terraform state %v", local.state_id)
  statements     = local.policy_statements
  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "oke_quickstart_storage" {
  provider       = oci.home
  count          = alltrue([var.create_policies, anytrue([var.create_fss, var.create_lustre])]) ? 1 : 0
  compartment_id = var.compartment_ocid
  name           = local.storage_group_name
  description    = format("FSS and Lustre FS policies for OKE Terraform state %v", local.state_id)
  statements = flatten([
    var.create_fss ? [
      "Allow any-user to manage file-family in compartment id ${var.compartment_ocid} where request.principal.type = 'cluster'",
      "Allow any-user to use virtual-network-family in compartment id ${var.compartment_ocid} where request.principal.type = 'cluster'",
    ] : [],
    var.create_lustre ? [
      "Allow service lustrefs to use virtual-network-family in compartment id ${var.compartment_ocid}",
    ] : [],
  ])
  lifecycle {
    ignore_changes = [defined_tags]
  }
}