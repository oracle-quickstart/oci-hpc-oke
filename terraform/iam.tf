# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

data "oci_identity_availability_domains" "all" {
  compartment_id = var.tenancy_ocid
}

data "oci_identity_dynamic_groups" "all" {
  count          = var.create_policies && local.existing_dg_id != null ? 1 : 0
  compartment_id = var.tenancy_ocid
}

data "oci_identity_domains" "default" {
  count          = local.lookup_default_identity_domain ? 1 : 0
  compartment_id = var.tenancy_ocid
  display_name   = "Default"
  type           = "DEFAULT"
  state          = "ACTIVE"
}

data "oci_identity_domain" "selected" {
  count     = local.lookup_identity_domain_id ? 1 : 0
  domain_id = local.selected_identity_domain_id
}

resource "random_string" "state_id" {
  length  = 6
  lower   = true
  numeric = false
  special = false
  upper   = false
}


locals {
  dynamic_groups_list            = coalesce(one(data.oci_identity_dynamic_groups.all[*].dynamic_groups), [])
  state_id                       = random_string.state_id.id
  service_account_name           = format("oke-%s-svcacct", local.state_id)
  existing_dg_id                 = try(coalesce(var.dynamic_group_id, var.dynamic_group_id_input), null)
  should_create_dg               = var.create_dynamic_group && !var.use_existing_dynamic_group && local.existing_dg_id == null
  lookup_identity_domain         = var.create_policies || local.should_create_dg
  lookup_default_identity_domain = local.lookup_identity_domain && (var.use_default_identity_domain || var.identity_domain_id == null)
  selected_identity_domain_id = try(
    var.identity_domain_id != null ? var.identity_domain_id : one(data.oci_identity_domains.default[0].domains[*].id),
    null
  )
  lookup_identity_domain_id = local.lookup_identity_domain && local.selected_identity_domain_id != null
  idcs_endpoint = try(coalesce(
    try(one(data.oci_identity_domain.selected[*].url), null),
    try(one(data.oci_identity_domains.default[0].domains[*].url), null),
  ), null)

  # Some Oracle tenancies do not expose a default identity domain, or do not
  # expose an IDCS endpoint for it. Fall back to the classic tenancy
  # dynamic-group path in those cases.
  use_identity_domain = local.lookup_identity_domain_id && local.idcs_endpoint != null

  domain_name = try(one(data.oci_identity_domain.selected[*].display_name), null)

  group_name = coalesce(
    try(one([for dg in local.dynamic_groups_list : dg.name if dg.id == local.existing_dg_id]), null),
    local.use_identity_domain ? one(oci_identity_domains_dynamic_resource_group.oke_quickstart_all[*].display_name) : null,
    format("oke-gpu-%v", local.state_id)
  )

  # For IAM policies, domain-scoped dynamic groups must be referenced as '<domain-name>'/'<group-name>'
  policy_group_ref = local.use_identity_domain ? format("'%v'/'%v'", local.domain_name, local.group_name) : local.group_name

  storage_group_name  = format("oke-gpu-%v-storage", local.state_id)
  compartment_matches = format("instance.compartment.id = '%v'", var.compartment_ocid)
  compartment_rule    = format("ANY {%v}", join(", ", [local.compartment_matches]))

  rule_templates = compact(concat(
    [
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
    ],
    var.setup_credential_provider_for_ocir ? [
      "Allow dynamic-group %v to read repos in compartment id %v"
    ] : [],
    var.setup_oci_metrics_exporter ? [
      "Allow dynamic-group %v to read all-resources in compartment id %v",
      "Allow dynamic-group %v to use stream-family in compartment id %v"
    ] : [],
    var.worker_gmc_enabled ? [
      "Allow dynamic-group %v to manage compute-clusters in compartment id %v",
      "Allow dynamic-group %v to manage compute-gpu-memory-clusters in compartment id %v"
    ] : []
  ))

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
    [for s in local.rule_templates : format(s, local.policy_group_ref, var.compartment_ocid)],
    [local.wris_statement, local.wris_ca_statement]
  ))
}

resource "oci_identity_dynamic_group" "oke_quickstart_all" {
  provider       = oci.home
  count          = local.should_create_dg && !local.use_identity_domain ? 1 : 0
  compartment_id = var.tenancy_ocid # dynamic groups exist in root compartment (tenancy)
  name           = format("oke-gpu-%v", local.state_id)
  description    = format("Dynamic group of instances for OKE Terraform state %v", local.state_id)
  matching_rule  = local.compartment_rule
  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_domains_dynamic_resource_group" "oke_quickstart_all" {
  count         = local.should_create_dg && local.use_identity_domain ? 1 : 0
  idcs_endpoint = local.idcs_endpoint
  display_name  = format("oke-gpu-%v", local.state_id)
  description   = format("Dynamic group of instances for OKE Terraform state %v", local.state_id)
  matching_rule = local.compartment_rule
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:DynamicResourceGroup"]
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

resource "oci_identity_policy" "services_policies" {
  provider       = oci.home
  count          = alltrue([
    var.create_policies,
    anytrue([
      local.create_fss_effective,
      var.worker_rdma_use_compute_cluster,
      var.worker_rdma_host_group_id != ""
    ])
  ]) ? 1 : 0

  compartment_id = var.compartment_ocid
  name           = format("oke-service-policies-%v", local.state_id)
  description    = format("OKE service policies for OKE Terraform state %v", local.state_id)
  statements = compact(concat(
    local.create_fss_effective ? [
      "Allow any-user to manage file-family in compartment id ${var.compartment_ocid} where request.principal.type = 'cluster'",
      "Allow any-user to use virtual-network-family in compartment id ${var.compartment_ocid} where request.principal.type = 'cluster'",
    ] : [],
    var.worker_rdma_use_compute_cluster ? [
      "Allow any-user to {COMPUTE_CLUSTER_LAUNCH_INSTANCE} in compartment id ${var.compartment_ocid} where request.principal.type = 'nodepool'"
    ] : [],
    var.worker_rdma_host_group_id != "" ? [
      "Allow any-user to {HOST_GROUP_LAUNCH_INSTANCE} in compartment id ${var.compartment_ocid} where request.principal.type = 'nodepool'"
    ] : [],
    []
  ))
  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "gmc_tenancy" {
  provider       = oci.home
  count          = alltrue([var.create_policies, var.worker_gmc_enabled]) ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = format("oke-gmc-tenancy-%v", local.state_id)
  description    = format("GPU Memory Cluster tenancy policies for OKE Terraform state %v", local.state_id)
  statements = [
    format("Allow dynamic-group %v to read compute-gpu-memory-fabrics in tenancy", local.policy_group_ref),
    "Allow any-user to manage instance-family in tenancy where all {request.principal.type = 'compute-gpu-memory-clusters'}",
    "Allow any-user to use virtual-network-family in tenancy where all {request.principal.type = 'compute-gpu-memory-clusters'}",
    "Allow any-user to read compute-management-family in tenancy where all {request.principal.type = 'compute-gpu-memory-clusters'}",
    "Allow any-user to use volume-family in tenancy where all {request.principal.type = 'compute-gpu-memory-clusters'}"
  ]
  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "lustre_service_network" {
  provider       = oci.home
  count          = alltrue([var.create_policies, anytrue([var.create_lustre, var.setup_oci_metrics_exporter])]) ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = format("oci-services-policies-%v", local.state_id)
  description    = format("OCI services policies for OKE Terraform state %v", local.state_id)
  statements = compact(concat(
    var.create_lustre ? [
      "Allow service lustrefs to use virtual-network-family in tenancy",
    ] : [],
    var.setup_oci_metrics_exporter ? [
      "Allow any-user to read metrics in tenancy where all {request.principal.type = 'serviceconnector', request.principal.compartment.id = '${var.compartment_ocid}'}",
      "Allow any-user to use stream-push in compartment id ${var.compartment_ocid} where all {request.principal.type='serviceconnector', request.principal.compartment.id='${var.compartment_ocid}'}"
    ] : []
  ))
  lifecycle {
    ignore_changes = [defined_tags]
  }
}
