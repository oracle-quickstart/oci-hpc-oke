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

  slinky_image_profiles = {
    "25.11.6-ubuntu24.04" = {
      operator_chart_version = "1.1.1"
      slurm_chart_version    = "1.1.1"
      # Custom slurmdbd/slurmrestd/login (SSSD) built from upstream source into
      # our registry (build-control-plane-images.sh), so the whole stack comes
      # from one registry.
      accounting_image_repository = "iad.ocir.io/idxzjcdglx2s/slurm-operator"
      accounting_image_tag        = "slurmdbd-25.11.6-ubuntu24.04-2026-06-19.0"
      restapi_image_repository    = "iad.ocir.io/idxzjcdglx2s/slurm-operator"
      restapi_image_tag           = "slurmrestd-25.11.6-ubuntu24.04-2026-06-19.0"
      sssd_image_repository       = "iad.ocir.io/idxzjcdglx2s/slurm-operator"
      sssd_image_tag              = "login-25.11.6-ubuntu24.04-2026-06-19.0"
      # Controller, login, and NVIDIA worker rebuilt FROM our from-source bases
      # (build-base-images.sh) instead of ghcr.io/slinkyproject. AMD already
      # builds from source, so its tag date is unchanged.
      controller_image_tag = "slurmctld-pmix-sssd-nss-25.11.6-ubuntu24.04-2026-06-19.0"
      login_image_tag      = "login-pyxis-25.11.6-ubuntu24.04-2026-06-19.0"
      nvidia_worker_tag    = "slurmd-nvml-nccl-pyxis-25.11.6-ubuntu24.04-2026-06-19.0"
      amd_worker_tag       = "slurmd-rocm-rccl-25.11.6-rocm7.1.1-sssd-pyxis-2026-06-16.0"
    }
    "26.05-ubuntu24.04" = {
      operator_chart_version      = "1.1.1"
      slurm_chart_version         = "1.1.1"
      accounting_image_repository = "ghcr.io/slinkyproject/slurmdbd"
      accounting_image_tag        = "26.05-ubuntu24.04"
      restapi_image_repository    = "ghcr.io/slinkyproject/slurmrestd"
      restapi_image_tag           = "26.05-ubuntu24.04"
      sssd_image_repository       = "ghcr.io/slinkyproject/login"
      sssd_image_tag              = "26.05-ubuntu24.04"
      controller_image_tag        = "slurmctld-pmix-sssd-nss-26.05-ubuntu24.04-2026-06-15.0"
      login_image_tag             = "login-pyxis-26.05-ubuntu24.04-2026-06-15.0"
      nvidia_worker_tag           = "slurmd-nvml-nccl-pyxis-26.05-ubuntu24.04-2026-06-15.0"
      amd_worker_tag              = "slurmd-rocm-rccl-26.05-rocm7.1.1-sssd-pyxis-2026-06-15.0"
    }
    "26.05.1-ubuntu26.04" = {
      operator_chart_version      = "1.1.1"
      slurm_chart_version         = "1.1.1"
      accounting_image_repository = "ghcr.io/slinkyproject/slurmdbd"
      accounting_image_tag        = "26.05-ubuntu24.04"
      restapi_image_repository    = "ghcr.io/slinkyproject/slurmrestd"
      restapi_image_tag           = "26.05-ubuntu24.04"
      sssd_image_repository       = "ghcr.io/slinkyproject/login"
      sssd_image_tag              = "26.05-ubuntu24.04"
      controller_image_tag        = "slurmctld-pmix-sssd-nss-26.05.1-ubuntu26.04-2026-06-16.1"
      login_image_tag             = "login-pyxis-26.05.1-ubuntu26.04-2026-06-16.1"
      nvidia_worker_tag           = "slurmd-nvml-nccl-pyxis-26.05.1-ubuntu26.04-2026-06-16.2"
      amd_worker_tag              = "slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-pyxis-2026-06-16.1"
    }
  }

  slinky_image_profile = local.slinky_image_profiles[var.slinky_image_profile]

  slinky_operator_chart_version = var.slinky_operator_chart_version == "auto" ? local.slinky_image_profile.operator_chart_version : var.slinky_operator_chart_version
  slinky_slurm_chart_version    = var.slinky_slurm_chart_version == "auto" ? local.slinky_image_profile.slurm_chart_version : var.slinky_slurm_chart_version
  slinky_accounting_image_tag   = var.slinky_accounting_image_tag == "auto" ? local.slinky_image_profile.accounting_image_tag : var.slinky_accounting_image_tag
  slinky_restapi_image_tag      = var.slinky_restapi_image_tag == "auto" ? local.slinky_image_profile.restapi_image_tag : var.slinky_restapi_image_tag
  slinky_controller_image_tag   = var.slinky_controller_image_tag == "auto" ? local.slinky_image_profile.controller_image_tag : var.slinky_controller_image_tag
  slinky_login_image_tag        = var.slinky_login_image_tag == "auto" ? local.slinky_image_profile.login_image_tag : var.slinky_login_image_tag
  slinky_sssd_image_tag         = var.slinky_sssd_image_tag == "auto" ? local.slinky_image_profile.sssd_image_tag : var.slinky_sssd_image_tag

  slinky_accounting_image_repository = var.slinky_accounting_image_repository == "auto" ? local.slinky_image_profile.accounting_image_repository : var.slinky_accounting_image_repository
  slinky_restapi_image_repository    = var.slinky_restapi_image_repository == "auto" ? local.slinky_image_profile.restapi_image_repository : var.slinky_restapi_image_repository
  slinky_sssd_image_repository       = var.slinky_sssd_image_repository == "auto" ? local.slinky_image_profile.sssd_image_repository : var.slinky_sssd_image_repository

  # Operator + webhook images custom-built from SlinkyProject/slurm-operator
  # v1.1.1 into our registry (build-control-plane-images.sh). Merged into the
  # operator Helm values so the operator pods also come from our registry.
  slinky_operator_image_values = <<-EOT
    operator:
      image:
        repository: iad.ocir.io/idxzjcdglx2s/slurm-operator
        tag: "1.1.1"
    webhook:
      image:
        repository: iad.ocir.io/idxzjcdglx2s/slurm-operator-webhook
        tag: "1.1.1"
  EOT

  slinky_worker_image_tag = var.slinky_worker_image_tag == "auto" ? (
    local.slinky_is_amd ? local.slinky_image_profile.amd_worker_tag : local.slinky_image_profile.nvidia_worker_tag
  ) : var.slinky_worker_image_tag

  slinky_worker_host_network = var.slinky_worker_network_mode == "hostNetwork"

  slinky_worker_sriov_enabled = alltrue([
    !local.slinky_worker_host_network,
    trimspace(coalesce(var.slinky_worker_rdma_network, "")) != "",
    trimspace(coalesce(var.slinky_worker_rdma_resource, "")) != "",
    coalesce(var.slinky_worker_rdma_vfs_per_node, 0) > 0,
  ])
  slinky_worker_rdma_networks_annotation = local.slinky_worker_sriov_enabled ? join(",", [
    for _ in range(coalesce(var.slinky_worker_rdma_vfs_per_node, 0)) : var.slinky_worker_rdma_network
  ]) : ""

  slinky_worker_numa_topology_enabled = contains(["BM.GPU.B4.8"], local.slinky_worker_shape)
  slinky_worker_slurmd_parameters     = local.slinky_worker_numa_topology_enabled ? "numa_node_as_socket" : ""

  slinky_worker_features = distinct(compact(concat(
    [lower(replace(replace(replace(local.slinky_worker_shape, "BM.GPU.", ""), ".", "-"), "_", "-"))],
    local.slinky_is_amd ? ["amd", "rocm"] : ["nvidia"],
    var.worker_rdma_enabled ? ["rdma"] : [],
    local.slinky_worker_host_network ? ["hostnetwork"] : [],
    local.slinky_worker_sriov_enabled ? ["sriov"] : []
  )))

  slinky_gpu_nodeset_enabled = anytrue([var.worker_rdma_enabled, var.worker_gpu_enabled])
  slinky_cpu_nodeset_enabled = alltrue([var.slinky_cpu_worker_enabled, var.worker_cpu_enabled])

  slinky_cpu_worker_image_repository = var.slinky_cpu_worker_image_repository != "" ? var.slinky_cpu_worker_image_repository : var.slinky_worker_image_repository
  slinky_cpu_worker_image_tag        = var.slinky_cpu_worker_image_tag == "auto" ? local.slinky_worker_image_tag : var.slinky_cpu_worker_image_tag

  # The operator adds the nodeset name itself as a feature, so "cpu" is
  # already present and only the shape slug is needed here.
  slinky_cpu_worker_features = distinct(compact([
    lower(replace(replace(var.worker_cpu_shape, ".", "-"), "_", "-")),
  ]))

  slinky_readonly_replica_dns_names = join("\n", [
    for i in range(var.slinky_openldap_readonly_replicas) :
    "    - openldap-readonly-${i}.openldap-headless-readonly.${var.slinky_openldap_namespace}.svc.cluster.local"
  ])

  slinky_login_root_ssh_authorized_keys = jsonencode(trimspace(local.ssh_public_key))
}
