# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

data "oci_identity_availability_domains" "all" {
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
  state_id             = random_string.state_id.id
  service_account_name = format("oke-%s-svcacct", local.state_id)
  group_name           = format("oke-gpu-%v", local.state_id)
  fss_group_name       = format("oke-gpu-%v-fss", local.state_id)
  compartment_matches  = format("instance.compartment.id = '%v'", var.compartment_ocid)
  compartment_rule     = format("ANY {%v}", join(", ", [local.compartment_matches]))

  rule_templates = [
    "Allow dynamic-group %v to manage cluster-node-pools in compartment id %v",
    "Allow dynamic-group %v to manage cluster-family in compartment id %v",
    "Allow dynamic-group %v to manage file-family in compartment id %v",
    "Allow dynamic-group %v to manage compute-management-family in compartment id %v",
    "Allow dynamic-group %v to manage instance-family in compartment id %v",
    "Allow dynamic-group %v to manage volume-family in compartment id %v",
    "Allow dynamic-group %v to use subnets in compartment id %v",
    "Allow dynamic-group %v to use virtual-network-family in compartment id %v",
    "Allow dynamic-group %v to use vnics in compartment id %v",
    "Allow dynamic-group %v to use network-security-groups in compartment id %v",
    "Allow dynamic-group %v to inspect compartments in compartment id %v",
    "Allow dynamic-group %v to {CLUSTER_JOIN} in compartment id %v"
  ]

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
  count          = var.create_policies ? 1 : 0
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
  name           = local.group_name
  description    = format("Policies for OKE Terraform state %v", local.state_id)
  statements     = local.policy_statements
  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "oke_quickstart_fss" {
  provider       = oci.home
  count          = var.create_fss ? 1 : 0
  compartment_id = var.compartment_ocid
  name           = local.fss_group_name
  description    = format("FSS policies for OKE Terraform state %v", local.state_id)
  statements = [
    "Allow any-user to manage file-family in compartment id ${var.compartment_ocid} where request.principal.type = 'cluster'",
    "Allow any-user to use virtual-network-family in compartment id ${var.compartment_ocid} where request.principal.type = 'cluster'",
  ]
  lifecycle {
    ignore_changes = [defined_tags]
  }
}
