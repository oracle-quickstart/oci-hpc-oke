# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  system_node_is_flex    = strcontains(var.worker_ops_shape, "Flex")
  system_node_memory_gib = min(var.worker_ops_memory, var.worker_ops_ocpus * 64)

  # Oracle's OCI Karpenter model, before image-specific rounding:
  # https://github.com/oracle/karpenter-provider-oci/blob/0171a91fdc0ef8c6443c3aed5b987da6047bf70d/pkg/providers/instancetype/provider.go#L646
  # Memory reservation depends on RAM, independently of the vCPU reservation.
  system_node_kube_reserved_gib = (
    local.system_node_memory_gib <= 4 ? 0.25 * local.system_node_memory_gib :
    local.system_node_memory_gib <= 8 ? 1 + 0.20 * (local.system_node_memory_gib - 4) :
    local.system_node_memory_gib <= 16 ? 1.8 + 0.10 * (local.system_node_memory_gib - 8) :
    local.system_node_memory_gib <= 128 ? 2.6 + 0.06 * (local.system_node_memory_gib - 16) :
    9.32 + 0.02 * (local.system_node_memory_gib - 128)
  )

  # 100 MiB each for systemReserved and eviction; 512 MiB for the difference
  # between configured RAM and node capacity; 1 GiB of operational margin.
  # kube-system and other pods consume allocatable memory separately.
  system_node_overhead_mib    = ceil(local.system_node_kube_reserved_gib * 1024) + 100 + 100 + 512 + 1024
  system_node_pods_memory_mib = 2048
  prometheus_required_node_memory_mib = (
    local.prometheus_memory_request_mib +
    local.system_node_overhead_mib +
    local.system_node_pods_memory_mib
  )
}

resource "terraform_data" "validate_prometheus_memory_request" {
  count = alltrue([
    local.system_node_is_flex,
    var.install_monitoring,
    var.install_node_problem_detector_kube_prometheus_stack,
    local.deploy_from_local || local.deploy_from_orm || local.deploy_from_operator,
  ]) ? 1 : 0

  lifecycle {
    precondition {
      condition = (
        var.worker_ops_pool_size > 0 &&
        local.system_node_memory_gib * 1024 >= local.prometheus_required_node_memory_mib
      )
      error_message = format(
        "Prometheus cannot fit in the configured system pool: its request is %d MiB and estimated per-node overhead is %d MiB, including other system pods. Configure at least one system node and increase the system node RAM/OCPUs (effective memory is currently %g GiB, capped at 64 GiB per OCPU). The current estimate requires %.2f GiB per node; reservations also grow with node memory.",
        local.prometheus_memory_request_mib,
        local.system_node_overhead_mib + local.system_node_pods_memory_mib,
        local.system_node_memory_gib,
        local.prometheus_required_node_memory_mib / 1024,
      )
    }
  }
}
