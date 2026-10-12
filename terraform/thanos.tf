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

# Prometheus memory per pod. An explicit prometheus_memory always wins. Without
# Thanos the default is no requests or limits, the stack's historical behavior.
# With Thanos it is sized from the worker pools: active series per node,
# measured on a 16 x BM.GPU.B300.8 + 3 x VM.Standard.E5.Flex cluster (449k
# series predicted vs 449k observed), split over the shards.
locals {
  prometheus_series_per_bm_node = 23600 # ~21.9k node-exporter/cAdvisor/kubelet/DCGM + ~1.7k kube-state-metrics and CoreDNS share
  prometheus_series_per_vm_node = 12200 # ~10.5k node-local + ~1.7k share
  prometheus_series_fixed       = 35000 # API server, kube-state-metrics base, Grafana, operators, self-monitoring
  prometheus_bytes_per_series   = 4500  # measured working set ~4.0-4.3 KB per head series
  prometheus_shard_imbalance    = 1.25  # hashmod over few targets is uneven (6 vs 13 nodes on 2 shards at 19 nodes)
  prometheus_headroom           = 2     # queries, WAL replay, head compaction, series churn

  prometheus_sizing_pools = [
    { nodes = var.worker_ops_pool_size, bare_metal = startswith(coalesce(var.worker_ops_shape, ""), "BM.") },
    { nodes = var.worker_cpu_enabled ? var.worker_cpu_pool_size : 0, bare_metal = startswith(coalesce(var.worker_cpu_shape, ""), "BM.") },
    { nodes = var.worker_gpu_enabled ? var.worker_gpu_pool_size : 0, bare_metal = startswith(coalesce(var.worker_gpu_shape, ""), "BM.") },
    { nodes = var.worker_rdma_enabled ? var.worker_rdma_pool_size : 0, bare_metal = true },
    { nodes = var.worker_gmc_enabled ? length(local.worker_gmc_gpu_memory_fabric_ids) * var.worker_gmc_scale_target_size : 0, bare_metal = true },
  ]
  prometheus_estimated_series = local.prometheus_series_fixed + sum([
    for p in local.prometheus_sizing_pools : p.nodes * (p.bare_metal ? local.prometheus_series_per_bm_node : local.prometheus_series_per_vm_node)
  ])
  prometheus_series_per_shard = ceil(local.prometheus_estimated_series / var.prometheus_shards * (var.prometheus_shards > 1 ? local.prometheus_shard_imbalance : 1))
  prometheus_auto_memory_gib = max(2, ceil(
    (local.prometheus_series_per_shard * local.prometheus_bytes_per_series * local.prometheus_headroom + pow(1024, 3)) / pow(1024, 3)
  ))

  prometheus_memory = trimspace(var.prometheus_memory) != "" ? trimspace(var.prometheus_memory) : (
    local.thanos_enabled ? format("%dGi", local.prometheus_auto_memory_gib) : ""
  )
  prometheus_memory_gib = local.prometheus_memory == "" ? 0 : (
    endswith(local.prometheus_memory, "Gi") ? tonumber(trimsuffix(local.prometheus_memory, "Gi")) : tonumber(trimsuffix(local.prometheus_memory, "Mi")) / 1024
  )

  # Prometheus is not tolerated onto the tainted GPU pools, so it lands on the
  # system or CPU pool. Keep each pod (plus its 0.5Gi sidecar) under ~60% of
  # such a node, leaving room for the other system pods.
  prometheus_node_budget_gib = 0.6 * max(var.worker_ops_memory, var.worker_cpu_enabled ? var.worker_cpu_memory : 0)
  prometheus_shards_to_fit = ceil(
    local.prometheus_estimated_series * local.prometheus_shard_imbalance * local.prometheus_bytes_per_series * local.prometheus_headroom /
    max(1, (local.prometheus_node_budget_gib - 1.5) * pow(1024, 3))
  )
}

check "prometheus_fits_system_nodes" {
  assert {
    condition = local.prometheus_memory_gib == 0 || local.prometheus_memory_gib + (local.thanos_enabled ? 0.5 : 0) <= local.prometheus_node_budget_gib
    error_message = format(
      "Each Prometheus pod is sized at %s for ~%d active series per shard, which leaves little room on %v GB system/CPU nodes. Set prometheus_shards to about %d, or raise worker_ops_memory.",
      local.prometheus_memory, local.prometheus_series_per_shard, max(var.worker_ops_memory, var.worker_cpu_enabled ? var.worker_cpu_memory : 0), local.prometheus_shards_to_fit
    )
  }
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
