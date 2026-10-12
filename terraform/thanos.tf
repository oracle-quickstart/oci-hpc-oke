# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

# Thanos for the sharded kube-prometheus-stack Prometheus: an OCI Object Storage
# bucket, an IAM policy that grants it to the Thanos and Prometheus
# ServiceAccounts through OKE workload identity (no keys), and the shared values
# for the files/thanos chart. Install order: bucket + policy -> thanos chart
# (creates the objstore Secret) -> kube-prometheus-stack (sidecars, Thanos Ruler,
# and Grafana pointed at Thanos Query).

locals {
  thanos_enabled       = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.install_thanos])
  thanos_create_bucket = local.thanos_enabled && trimspace(var.thanos_bucket_name) == ""
  thanos_bucket_name   = local.thanos_create_bucket ? format("oke-gpu-%v-thanos", local.state_id) : trimspace(var.thanos_bucket_name)

  # The sidecars run as the Prometheus pods' ServiceAccount; the store gateway,
  # the compactor and the Thanos Ruler use the chart's "thanos" ServiceAccount.
  thanos_service_accounts = ["thanos", "kube-prometheus-stack-prometheus"]
  thanos_policy_statements = [
    for sa in local.thanos_service_accounts : format(
      "Allow any-user to manage objects in compartment id %v where all {request.principal.type = 'workload', request.principal.namespace = '%v', request.principal.service_account = '%v', request.principal.cluster_id = '%v', target.bucket.name = '%v'}",
      var.compartment_ocid, var.monitoring_namespace, sa, module.oke.cluster_id, local.thanos_bucket_name
    )
  ]

  thanos_chart_values = yamlencode({
    image = { tag = var.thanos_version }
    objstore = {
      bucket = local.thanos_bucket_name
      region = var.region
    }
    compact = {
      retention = {
        raw         = var.thanos_retention_raw
        fiveMinutes = var.thanos_retention_5m
        oneHour     = var.thanos_retention_1h
      }
    }
  })
}

data "oci_objectstorage_namespace" "thanos" {
  count          = local.thanos_enabled ? 1 : 0
  compartment_id = var.tenancy_ocid
}

resource "oci_objectstorage_bucket" "thanos" {
  count          = local.thanos_create_bucket ? 1 : 0
  compartment_id = var.compartment_ocid
  namespace      = one(data.oci_objectstorage_namespace.thanos[*].namespace)
  name           = local.thanos_bucket_name
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = "Disabled"
  freeform_tags  = { "state_id" = local.state_id, "application" = "thanos" }
}

resource "oci_identity_policy" "thanos_objstore" {
  provider       = oci.home
  count          = alltrue([local.thanos_enabled, var.create_policies]) ? 1 : 0
  compartment_id = var.compartment_ocid
  name           = format("oke-gpu-%v-thanos-policy", local.state_id)
  description    = format("Thanos access to bucket %v via OKE workload identity for Terraform state %v", local.thanos_bucket_name, local.state_id)
  statements     = local.thanos_policy_statements
}

# IAM changes take a few minutes to reach the cluster's region (about 4 minutes
# observed in ap-tokyo-1 for a policy created in the home region). Until then
# the first uploads fail with BucketNotFound and the components retry.
resource "time_sleep" "wait_for_thanos_policy" {
  count           = alltrue([local.thanos_enabled, var.create_policies]) ? 1 : 0
  create_duration = "300s"
  depends_on      = [oci_identity_policy.thanos_objstore]
}
