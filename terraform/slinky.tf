# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  slinky_deploy_from_operator = alltrue([var.install_slinky, var.create_bastion, var.create_operator, !var.deploy_to_oke_from_orm])
  slinky_cert_manager_required = alltrue([
    var.install_slinky,
    anytrue([
      var.slinky_identity_enabled,
      var.slinky_operator_cert_manager_enabled,
    ]),
  ])

  # When worker nodes keep their IP node names (hostname_override=false), the
  # oci-hpc-oke-utils annotator writes the slurm-operator 1.2
  # nodeset.slinky.slurm.net/hostname-override node annotation so Slurm node
  # names stay clean hostnames.
  slinky_hostname_annotator_enabled = alltrue([var.install_slinky, var.slinky_install_slurm_cluster, !local.hostname_override_effective])

  slinky_amd_shapes = [
    "BM.GPU.MI300X.8",
    "BM.GPU.MI355X-v1.8",
    "BM.GPU.MI355X.8",
  ]

  slinky_system_pool_name = "oke-system"
  slinky_gpu_is_amd       = contains(local.slinky_amd_shapes, var.worker_gpu_shape)
  slinky_rdma_is_amd      = contains(local.slinky_amd_shapes, var.worker_rdma_shape)
  slinky_enabled_worker_vendors = distinct(compact([
    var.worker_gpu_enabled ? (local.slinky_gpu_is_amd ? "amd" : "nvidia") : "",
    var.worker_rdma_enabled ? (local.slinky_rdma_is_amd ? "amd" : "nvidia") : "",
    var.worker_gmc_enabled ? "nvidia" : "",
  ]))
  # gres.conf is shared by every NodeSet, so the first implementation supports
  # one GPU vendor per Slurm cluster. validation.tf rejects mixed vendors.
  slinky_is_amd         = try(one(local.slinky_enabled_worker_vendors), "nvidia") == "amd"
  slinky_gpu_autodetect = var.slinky_gpu_autodetect == "auto" ? (local.slinky_is_amd ? "rsmi" : "nvml") : var.slinky_gpu_autodetect
  slinky_openldap_dc    = split(".", var.slinky_openldap_domain)[0]

  slinky_image_profiles = {
    "25.11.6-ubuntu24.04" = {
      operator_chart_version = "1.2.0"
      slurm_chart_version    = "1.2.0"
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
      operator_chart_version      = "1.2.0"
      slurm_chart_version         = "1.2.0"
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
      operator_chart_version = "1.2.0"
      slurm_chart_version    = "1.2.0"
      # Whole stack rebuilt from the latest SlinkyProject/containers source
      # into our registry (see slurm-source/README.md for the pinned ref),
      # same one-registry layout as the 25.11.6 profile.
      accounting_image_repository = "iad.ocir.io/idxzjcdglx2s/slurm-operator"
      accounting_image_tag        = "slurmdbd-26.05.1-ubuntu26.04-2026-07-02.0"
      restapi_image_repository    = "iad.ocir.io/idxzjcdglx2s/slurm-operator"
      restapi_image_tag           = "slurmrestd-26.05.1-ubuntu26.04-2026-07-02.0"
      sssd_image_repository       = "iad.ocir.io/idxzjcdglx2s/slurm-operator"
      sssd_image_tag              = "login-26.05.1-ubuntu26.04-2026-07-02.0"
      controller_image_tag        = "slurmctld-pmix-sssd-nss-26.05.1-ubuntu26.04-2026-07-02.0"
      login_image_tag             = "login-pyxis-26.05.1-ubuntu26.04-2026-07-02.0"
      nvidia_worker_tag           = "slurmd-nvml-nccl-pyxis-26.05.1-ubuntu26.04-2026-07-02.0"
      amd_worker_tag              = "slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-pyxis-2026-07-02.0"
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
  # into our registry (build-control-plane-images.sh); their tag tracks the
  # operator chart version. Merged into the operator Helm values so the
  # operator pods also come from our registry.
  slinky_operator_generated_values = <<-EOT
    certManager:
      enabled: ${var.slinky_operator_cert_manager_enabled}
    operator:
      image:
        repository: iad.ocir.io/idxzjcdglx2s/slurm-operator
        tag: "${local.slinky_operator_chart_version}"
    webhook:
      image:
        repository: iad.ocir.io/idxzjcdglx2s/slurm-operator-webhook
        tag: "${local.slinky_operator_chart_version}"
  EOT

  slinky_worker_image_tag = var.slinky_worker_image_tag == "auto" ? (
    local.slinky_is_amd ? local.slinky_image_profile.amd_worker_tag : local.slinky_image_profile.nvidia_worker_tag
  ) : var.slinky_worker_image_tag

  # The NVIDIA Network Operator provisions SR-IOV RDMA VFs for the RDMA pool.
  # Standard GPU workers keep pod networking, while GMC workers use hostNetwork
  # for IMEX and the physical RDMA fabric.
  slinky_rdma_network_mode_effective = var.deploy_nvidia_network_operator ? "virtualFunctions" : var.slinky_worker_network_mode
  slinky_rdma_host_network           = local.slinky_rdma_network_mode_effective == "hostNetwork"

  # Per-shape SR-IOV RDMA VF count. Must match the number of rootDevices the
  # matching policy selects in files/nvidia-network-operator/sriov-network-node-policy.yaml
  # (numVfs is 1, so advertised VFs/node equals the number of RDMA PFs the shape
  # exposes). Single-port shapes (B200, H200, MI300X, MI355X) expose 8; dual-port
  # shapes expose 16. Pods must not request more VFs than this or they stay
  # unschedulable.
  slinky_shape_rdma_vf_count = {
    "BM.GPU4.8"          = 16
    "BM.GPU.A100-v2.8"   = 16
    "BM.GPU.B4.8"        = 16
    "BM.GPU.B200.8"      = 8
    "BM.GPU.H100.8"      = 16
    "BM.GPU.H200.8"      = 8
    "BM.GPU.MI300X.8"    = 8
    "BM.GPU.MI355X-v1.8" = 8
    "BM.GPU.B300.8"      = 16
  }
  # Effective VF request per worker: explicit override, else derive from the
  # shape so the request never exceeds what the Network Operator advertises.
  slinky_rdma_vfs_per_node = coalesce(
    var.slinky_worker_rdma_vfs_per_node,
    lookup(local.slinky_shape_rdma_vf_count, var.worker_rdma_shape, 0)
  )

  slinky_rdma_sriov_enabled = alltrue([
    var.worker_rdma_enabled,
    !local.slinky_rdma_host_network,
    trimspace(coalesce(var.slinky_worker_rdma_network, "")) != "",
    trimspace(coalesce(var.slinky_worker_rdma_resource, "")) != "",
    local.slinky_rdma_vfs_per_node > 0,
  ])
  slinky_rdma_networks_annotation = local.slinky_rdma_sriov_enabled ? join(",", [
    for _ in range(local.slinky_rdma_vfs_per_node) : var.slinky_worker_rdma_network
  ]) : ""

  slinky_gpu_numa_topology_enabled  = contains(["BM.GPU.B4.8"], var.worker_gpu_shape)
  slinky_rdma_numa_topology_enabled = contains(["BM.GPU.B4.8"], var.worker_rdma_shape)

  # A GPU memory pool can fan out into multiple independent GPU memory fabrics.
  # Give each fabric its own NodeSet, partition, ComputeDomain, and IMEX claim so
  # IMEX remains scoped to its NVLink fabric. An aggregate partition separately
  # allows jobs to span fabrics over RDMA.
  slinky_gmc_nodeset_fabrics = var.worker_gmc_enabled ? {
    for fabric_id in local.worker_gmc_gpu_memory_fabric_ids :
    (length(local.worker_gmc_gpu_memory_fabric_ids) == 1 ? var.slinky_gmc_nodeset_name : "${var.slinky_gmc_nodeset_name}-${substr(fabric_id, -11, 11)}") => fabric_id
  } : {}

  slinky_cpu_nodeset_enabled             = alltrue([var.slinky_cpu_worker_enabled, var.worker_cpu_enabled])
  slinky_gmc_aggregate_partition_enabled = length(local.slinky_gmc_nodeset_fabrics) > 1
  slinky_gmc_aggregate_partition_name    = "${var.slinky_gmc_nodeset_name}-all"

  slinky_auto_default_partition_name = (
    var.worker_gpu_enabled ? var.slinky_nodeset_name :
    var.worker_rdma_enabled ? var.slinky_rdma_nodeset_name :
    local.slinky_gmc_aggregate_partition_enabled ? local.slinky_gmc_aggregate_partition_name :
    length(local.slinky_gmc_nodeset_fabrics) == 1 ? try(element(sort(keys(local.slinky_gmc_nodeset_fabrics)), 0), "") :
    local.slinky_cpu_nodeset_enabled ? var.slinky_cpu_nodeset_name : ""
  )
  slinky_default_partition_name = (
    var.slinky_default_partition == "auto" ? local.slinky_auto_default_partition_name :
    var.slinky_default_partition == "gpu" ? var.slinky_nodeset_name :
    var.slinky_default_partition == "rdma" ? var.slinky_rdma_nodeset_name :
    var.slinky_default_partition == "gmc" ? (
      local.slinky_gmc_aggregate_partition_enabled ? local.slinky_gmc_aggregate_partition_name :
      try(element(sort(keys(local.slinky_gmc_nodeset_fabrics)), 0), "")
    ) :
    var.slinky_default_partition == "cpu" ? var.slinky_cpu_nodeset_name : var.slinky_default_partition
  )

  slinky_gpu_worker_nodesets = var.worker_gpu_enabled ? {
    (var.slinky_nodeset_name) = {
      shape               = var.worker_gpu_shape
      pool_name           = "oke-gpu"
      fabric_label        = ""
      replicas            = coalesce(var.slinky_worker_replicas, var.worker_gpu_pool_size)
      image_tag           = local.slinky_worker_image_tag
      gpu_resource        = local.slinky_gpu_is_amd ? "amd.com/gpu" : "nvidia.com/gpu"
      gpus_per_node       = coalesce(var.slinky_gpus_per_node, try(tonumber(element(split(".", var.worker_gpu_shape), length(split(".", var.worker_gpu_shape)) - 1)), 1))
      mount_infiniband    = false
      host_network        = false
      sriov_enabled       = false
      rdma_resource       = ""
      rdma_vfs_per_node   = 0
      rdma_networks       = ""
      slurmd_parameters   = local.slinky_gpu_numa_topology_enabled ? "numa_node_as_socket" : ""
      numa_topology       = local.slinky_gpu_numa_topology_enabled
      features            = distinct(compact(concat([var.worker_gpu_shape], local.slinky_gpu_is_amd ? ["amd", "rocm"] : ["nvidia"])))
      imex_claim_template = ""
    }
  } : {}

  slinky_rdma_worker_nodesets = var.worker_rdma_enabled ? {
    (var.slinky_rdma_nodeset_name) = {
      shape               = var.worker_rdma_shape
      pool_name           = "oke-rdma"
      fabric_label        = ""
      replicas            = coalesce(var.slinky_worker_replicas, var.worker_rdma_pool_size)
      image_tag           = local.slinky_worker_image_tag
      gpu_resource        = local.slinky_rdma_is_amd ? "amd.com/gpu" : "nvidia.com/gpu"
      gpus_per_node       = coalesce(var.slinky_gpus_per_node, try(tonumber(element(split(".", var.worker_rdma_shape), length(split(".", var.worker_rdma_shape)) - 1)), 1))
      mount_infiniband    = var.slinky_worker_mount_infiniband
      host_network        = local.slinky_rdma_host_network
      sriov_enabled       = local.slinky_rdma_sriov_enabled
      rdma_resource       = var.slinky_worker_rdma_resource
      rdma_vfs_per_node   = local.slinky_rdma_vfs_per_node
      rdma_networks       = local.slinky_rdma_networks_annotation
      slurmd_parameters   = local.slinky_rdma_numa_topology_enabled ? "numa_node_as_socket" : ""
      numa_topology       = local.slinky_rdma_numa_topology_enabled
      features            = distinct(compact(concat([var.worker_rdma_shape], local.slinky_rdma_is_amd ? ["amd", "rocm"] : ["nvidia"], ["rdma"], local.slinky_rdma_host_network ? ["hostnetwork"] : [], local.slinky_rdma_sriov_enabled ? ["sriov"] : [])))
      imex_claim_template = ""
    }
  } : {}

  slinky_gmc_worker_nodesets = var.worker_gmc_enabled ? {
    for nodeset_name, fabric_id in local.slinky_gmc_nodeset_fabrics : nodeset_name => {
      shape               = var.worker_gmc_shape
      pool_name           = "oke-gmc"
      fabric_label        = substr(fabric_id, -11, 11)
      replicas            = coalesce(var.slinky_worker_replicas, var.worker_gmc_scale_target_size)
      image_tag           = local.slinky_worker_image_tag
      gpu_resource        = "nvidia.com/gpu"
      gpus_per_node       = coalesce(var.slinky_gpus_per_node, try(tonumber(element(split(".", var.worker_gmc_shape), length(split(".", var.worker_gmc_shape)) - 1)), 1))
      mount_infiniband    = true
      host_network        = true
      sriov_enabled       = false
      rdma_resource       = ""
      rdma_vfs_per_node   = 0
      rdma_networks       = ""
      slurmd_parameters   = ""
      numa_topology       = false
      features            = [var.worker_gmc_shape, "nvidia", "rdma", "gmc", "imex", "hostnetwork"]
      imex_claim_template = "${nodeset_name}-imex-channel"
    }
  } : {}

  slinky_worker_nodesets = merge(local.slinky_gpu_worker_nodesets, local.slinky_rdma_worker_nodesets, local.slinky_gmc_worker_nodesets)

  slinky_gmc_compute_domains = {
    for nodeset_name, nodeset in local.slinky_gmc_worker_nodesets : nodeset_name => {
      apiVersion = "resource.nvidia.com/v1beta1"
      kind       = "ComputeDomain"
      metadata = {
        name      = "${nodeset_name}-imex-compute-domain"
        namespace = var.slinky_slurm_namespace
        labels = {
          "app.kubernetes.io/managed-by" = "terraform"
          "app.kubernetes.io/part-of"    = "slurm"
          "slinky.slurm.net/nodeset"     = nodeset_name
        }
      }
      spec = {
        numNodes = 0
        channel = {
          allocationMode = "All"
          resourceClaimTemplate = {
            name = nodeset.imex_claim_template
          }
        }
      }
    }
  }
  slinky_gmc_compute_domains_yaml = join("\n---\n", [
    for nodeset_name in sort(keys(local.slinky_gmc_compute_domains)) : yamlencode(local.slinky_gmc_compute_domains[nodeset_name])
  ])

  slinky_cpu_worker_image_repository = var.slinky_cpu_worker_image_repository != "" ? var.slinky_cpu_worker_image_repository : var.slinky_worker_image_repository
  slinky_cpu_worker_image_tag        = var.slinky_cpu_worker_image_tag == "auto" ? local.slinky_worker_image_tag : var.slinky_cpu_worker_image_tag

  # The operator adds the nodeset name itself as a feature, so "cpu" is
  # already present and only the shape name is needed here. Slurm accepts
  # dotted feature names, so the OCI shape name is used verbatim.
  slinky_cpu_worker_features = distinct(compact([var.worker_cpu_shape]))

  slinky_readonly_replica_dns_names = join("\n", [
    for i in range(var.slinky_openldap_readonly_replicas) :
    "    - openldap-readonly-${i}.openldap-headless-readonly.${var.slinky_openldap_namespace}.svc.cluster.local"
  ])

  # Explicit non-empty values remain supported for existing deployments. New
  # stacks receive independent passwords that persist in Terraform state.
  slinky_openldap_admin_password = try(coalesce(
    var.slinky_openldap_admin_password,
    one(random_password.slinky_openldap_admin[*].result),
  ), "")
  slinky_openldap_config_password = try(coalesce(
    var.slinky_openldap_config_password,
    one(random_password.slinky_openldap_config[*].result),
  ), "")

  # Slurm workloads receive only this independently generated, read-only bind
  # credential. Administrator credentials stay in the identity namespace.
  slinky_openldap_sssd_bind_dn = "cn=sssd,ou=ServiceAccounts,${var.slinky_openldap_base_dn}"
  slinky_openldap_sssd_bind_password = try(coalesce(
    one(random_password.slinky_openldap_sssd_bind[*].result),
  ), "")
}

resource "random_password" "slinky_openldap_admin" {
  count = var.install_slinky && var.slinky_identity_enabled ? 1 : 0

  length      = 32
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  special     = false
}

resource "random_password" "slinky_openldap_config" {
  count = var.install_slinky && var.slinky_identity_enabled ? 1 : 0

  length      = 32
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  special     = false
}

resource "random_password" "slinky_openldap_sssd_bind" {
  count = var.install_slinky && var.slinky_identity_enabled ? 1 : 0

  length      = 32
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  special     = false
}
