# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  slinky_deploy_from_operator = alltrue([var.install_slinky, var.create_bastion, var.create_operator, !var.deploy_to_oke_from_orm])

  slinky_amd_shapes = [
    "BM.GPU.MI300X.8",
    "BM.GPU.MI355X-v1.8",
    "BM.GPU.MI355X.8",
  ]

  slinky_worker_shape     = var.worker_rdma_enabled ? var.worker_rdma_shape : var.worker_gpu_shape
  slinky_worker_pool_size = var.worker_rdma_enabled ? var.worker_rdma_pool_size : (var.worker_gpu_enabled ? var.worker_gpu_pool_size : 0)
  slinky_is_amd           = contains(local.slinky_amd_shapes, local.slinky_worker_shape)
  slinky_gpu_resource     = local.slinky_is_amd ? "amd.com/gpu" : "nvidia.com/gpu"
  slinky_gpu_autodetect   = var.slinky_gpu_autodetect == "auto" ? (local.slinky_is_amd ? "rsmi" : "nvml") : var.slinky_gpu_autodetect
  slinky_gpus_per_node    = coalesce(var.slinky_gpus_per_node, try(tonumber(element(split(".", local.slinky_worker_shape), length(split(".", local.slinky_worker_shape)) - 1)), 1))
  slinky_worker_replicas  = coalesce(var.slinky_worker_replicas, local.slinky_worker_pool_size)
  slinky_openldap_dc      = split(".", var.slinky_openldap_domain)[0]

  slinky_worker_image_tag = var.slinky_worker_image_tag == "auto" ? (
    local.slinky_is_amd ? "slurmd-rocm-rccl-25.11.5-rocm7.1.1-sssd-r2" : "slurmd-nvml-nccl-25.11.5-ubuntu24.04-r2"
  ) : var.slinky_worker_image_tag

  slinky_worker_features = distinct(compact(concat(
    [lower(replace(replace(replace(local.slinky_worker_shape, "BM.GPU.", ""), ".", "-"), "_", "-"))],
    local.slinky_is_amd ? ["amd", "rocm"] : ["nvidia"],
    var.worker_rdma_enabled ? ["rdma"] : [],
    var.slinky_worker_host_network ? ["hostnetwork"] : []
  )))

  slinky_readonly_replica_dns_names = join("\n", [
    for i in range(var.slinky_openldap_readonly_replicas) :
    "    - openldap-readonly-${i}.openldap-headless-readonly.${var.slinky_openldap_namespace}.svc.cluster.local"
  ])

  slinky_login_root_ssh_authorized_keys = jsonencode(trimspace(local.ssh_public_key))
}
