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

  # The monitoring pool's nodes carry this label and a NoSchedule taint with the
  # same key; Prometheus, Thanos, Grafana and kube-state-metrics select and
  # tolerate it.
  monitoring_node_key      = "oci.oraclecloud.com/monitoring"
  monitoring_node_selector = local.monitoring_pool_enabled ? { (local.monitoring_node_key) = "true" } : {}
  monitoring_tolerations = local.monitoring_pool_enabled ? [
    { key = local.monitoring_node_key, operator = "Equal", value = "true", effect = "NoSchedule" }
  ] : []

  thanos_chart_values = yamlencode({
    nodeSelector = local.monitoring_node_selector
    tolerations  = local.monitoring_tolerations
    image        = { tag = var.thanos_version }
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

# Prometheus sizing. Explicit prometheus_shards / prometheus_memory always win.
# Without Thanos: one Prometheus with no requests or limits, the stack's
# historical behavior. With Thanos: shards, memory per pod and the monitoring
# pool are derived from the active series the worker pools will produce. The
# per-node constants were measured on a 16 x BM.GPU.B300.8 + 3 x
# VM.Standard.E5.Flex cluster (449k series predicted vs 449k observed).
locals {
  prometheus_series_per_bm_node = 23600 # ~21.9k node-exporter/cAdvisor/kubelet/DCGM + ~1.7k kube-state-metrics and CoreDNS share
  prometheus_series_per_vm_node = 12200 # ~10.5k node-local + ~1.7k share
  prometheus_series_fixed       = 35000 # API server, kube-state-metrics base, Grafana, operators, self-monitoring
  prometheus_bytes_per_series   = 4500  # measured working set ~4.0-4.3 KB per head series
  prometheus_shard_imbalance    = 1.25  # hashmod over few targets is uneven (6 vs 13 nodes on 2 shards at 19 nodes)
  prometheus_headroom           = 2     # queries, WAL replay, head compaction, series churn
  # Besides its Prometheus pod and sidecar, a monitoring node may host the
  # node-level DaemonSets (~1Gi), the Thanos Compactor and Store Gateway
  # (3Gi + 1.5Gi), and a Thanos Query, Grafana or kube-state-metrics pod (~1Gi).
  monitoring_node_overhead_gib = 1 + 4.5 + 1
  node_allocatable_fraction    = 0.84 # 13.48 GiB allocatable on a 16 GB VM.Standard.E5.Flex

  prometheus_sizing_pools = [
    { nodes = var.worker_ops_pool_size, bare_metal = startswith(coalesce(var.worker_ops_shape, ""), "BM.") },
    { nodes = var.worker_cpu_enabled ? var.worker_cpu_pool_size : 0, bare_metal = startswith(coalesce(var.worker_cpu_shape, ""), "BM.") },
    { nodes = var.worker_gpu_enabled ? var.worker_gpu_pool_size : 0, bare_metal = startswith(coalesce(var.worker_gpu_shape, ""), "BM.") },
    { nodes = var.worker_rdma_enabled ? var.worker_rdma_pool_size : 0, bare_metal = true },
    { nodes = var.worker_gmc_enabled ? length(local.worker_gmc_gpu_memory_fabric_ids) * var.worker_gmc_scale_target_size : 0, bare_metal = true },
  ]
  # Without the monitoring pool's own nodes, which depend on the shard count.
  prometheus_workload_series = local.prometheus_series_fixed + sum([
    for p in local.prometheus_sizing_pools : p.nodes * (p.bare_metal ? local.prometheus_series_per_bm_node : local.prometheus_series_per_vm_node)
  ])

  prometheus_shards = !local.thanos_enabled ? 1 : (
    var.prometheus_shards > 0 ? var.prometheus_shards : (
      local.prometheus_workload_series <= var.prometheus_target_series_per_shard ? 1 :
      ceil(local.prometheus_workload_series * local.prometheus_shard_imbalance / var.prometheus_target_series_per_shard)
    )
  )
  prometheus_replicas = local.thanos_enabled ? var.prometheus_replicas : 1
  prometheus_pods     = local.prometheus_shards * local.prometheus_replicas

  # One Prometheus pod per monitoring node (hard anti-affinity) plus a spare,
  # so a shard can reschedule when a node is lost or cycled.
  monitoring_pool_enabled = local.thanos_enabled && var.worker_monitoring_enabled
  monitoring_pool_size = !local.monitoring_pool_enabled ? 0 : (
    var.worker_monitoring_pool_size > 0 ? var.worker_monitoring_pool_size : local.prometheus_pods + 1
  )

  prometheus_estimated_series = local.prometheus_workload_series + local.monitoring_pool_size * local.prometheus_series_per_vm_node
  prometheus_series_per_shard = ceil(local.prometheus_estimated_series / local.prometheus_shards * (local.prometheus_shards > 1 ? local.prometheus_shard_imbalance : 1))
  prometheus_auto_memory_gib = max(2, ceil(
    (local.prometheus_series_per_shard * local.prometheus_bytes_per_series * local.prometheus_headroom + pow(1024, 3)) / pow(1024, 3)
  ))

  prometheus_memory = trimspace(var.prometheus_memory) != "" ? trimspace(var.prometheus_memory) : (
    local.thanos_enabled ? format("%dGi", local.prometheus_auto_memory_gib) : ""
  )
  prometheus_memory_gib = local.prometheus_memory == "" ? 0 : (
    endswith(local.prometheus_memory, "Gi") ? tonumber(trimsuffix(local.prometheus_memory, "Gi")) : tonumber(trimsuffix(local.prometheus_memory, "Mi")) / 1024
  )
  prometheus_pod_gib = local.prometheus_memory_gib + (local.thanos_enabled ? 0.5 : 0) # + Thanos sidecar

  # Monitoring node memory in GB (OCI flex memory is in GiB-sized GB), in 8 GB steps.
  monitoring_node_memory_gb = !local.monitoring_pool_enabled ? 0 : (
    var.worker_monitoring_memory > 0 ? var.worker_monitoring_memory :
    max(16, 8 * ceil((local.prometheus_pod_gib + local.monitoring_node_overhead_gib) / local.node_allocatable_fraction / 8))
  )

  # Without the monitoring pool, Prometheus lands on the system or CPU pool
  # (the GPU pools are tainted). Keep each pod under ~60% of such a node, and all
  # of them plus Thanos (~7Gi) and the other system pods (~2.2Gi per node) under
  # 85% of the pool's allocatable memory.
  system_node_memory_gb      = max(var.worker_ops_memory, var.worker_cpu_enabled ? var.worker_cpu_memory : 0)
  system_pool_nodes          = var.worker_ops_pool_size + (var.worker_cpu_enabled ? var.worker_cpu_pool_size : 0)
  prometheus_node_budget_gib = 0.6 * local.system_node_memory_gb
  system_pool_budget_gib     = 0.85 * local.node_allocatable_fraction * local.system_node_memory_gb * local.system_pool_nodes - 2.2 * local.system_pool_nodes - (local.thanos_enabled ? 7 : 0)
}

check "prometheus_fits_monitoring_nodes" {
  assert {
    condition = !local.monitoring_pool_enabled || local.prometheus_pod_gib + local.monitoring_node_overhead_gib <= local.node_allocatable_fraction * local.monitoring_node_memory_gb
    error_message = format(
      "Each monitoring node (%v GB) is too small for a %s Prometheus pod plus its share of Thanos. Leave worker_monitoring_memory at 0, or set it to at least %d.",
      local.monitoring_node_memory_gb, local.prometheus_memory, 8 * ceil((local.prometheus_pod_gib + local.monitoring_node_overhead_gib) / local.node_allocatable_fraction / 8)
    )
  }
}

check "prometheus_fits_system_nodes" {
  assert {
    condition = local.monitoring_pool_enabled || local.prometheus_memory_gib == 0 || (
      local.prometheus_pod_gib <= local.prometheus_node_budget_gib && local.prometheus_pods * local.prometheus_pod_gib <= local.system_pool_budget_gib
    )
    error_message = format(
      "%d Prometheus pod(s) of %s for ~%d series each don't fit on %d system/CPU node(s) of %v GB next to Thanos and the other system pods; some shards would stay Pending. Enable worker_monitoring_enabled, or grow worker_ops_pool_size / worker_ops_memory.",
      local.prometheus_pods, local.prometheus_memory, local.prometheus_series_per_shard, local.system_pool_nodes, local.system_node_memory_gb
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
