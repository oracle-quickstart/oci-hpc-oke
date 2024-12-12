# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  create_workers = true
  ssh_authorized_keys = compact([
    trimspace(var.ssh_public_key),
  ])

  worker_ops_image_id    = coalesce(var.worker_ops_image_custom_id, "none")
  worker_cpu_image_type  = contains(["platform", "custom"], lower(var.worker_cpu_image_type)) ? "custom" : "oke"
  worker_cpu_image_id    = coalesce(var.worker_cpu_image_custom_id, var.worker_cpu_image_platform_id, "none")
  worker_gpu_image_type  = contains(["platform", "custom"], lower(var.worker_gpu_image_type)) ? "custom" : "oke"
  worker_gpu_image_id    = coalesce(var.worker_gpu_image_custom_id, var.worker_gpu_image_platform_id, "none")
  worker_rdma_image_type = contains(["platform", "custom"], lower(var.worker_rdma_image_type)) ? "custom" : "oke"
  worker_rdma_image_id   = coalesce(var.worker_rdma_image_custom_id, var.worker_rdma_image_platform_id, "none")

  runcmd_bootstrap = local.create_workers ? format(
    "curl -sL -o /var/run/oke-ubuntu-cloud-init.sh https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/files/oke-ubuntu-cloud-init.sh && (bash /var/run/oke-ubuntu-cloud-init.sh '%v' || echo 'Error bootstrapping OKE' >&2)",
    var.kubernetes_version,
  ) : ""

  runcmd_nvme_raid = var.nvme_raid_enabled ? format(
    "curl -sL -o /var/run/oke-nvme-raid.sh https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/files/oke-nvme-raid.sh && (bash /var/run/oke-nvme-raid.sh '%v' || echo 'Error initializing RAID' >&2)",
    var.nvme_raid_level,
  ) : ""

  write_files = [
    {
      content = local.cluster_apiserver,
      path    = "/etc/oke/oke-apiserver",
    },
    {
      encoding    = "b64",
      content     = local.cluster_ca_cert,
      owner       = "root:root",
      path        = "/etc/kubernetes/ca.crt",
      permissions = "0644",
    }
  ]
  cloud_init = {
    ssh_authorized_keys = local.ssh_authorized_keys
    runcmd = compact([
      local.runcmd_nvme_raid,
      local.runcmd_bootstrap,
    ])
    write_files = local.write_files
  }

  worker_pools = {
    "oke-ops" = {
      create           = local.create_workers
      description      = "OKE-managed VM Node Pool for cluster operations and monitoring"
      placement_ads    = [substr(var.worker_ops_ad, -1, 0)]
      size             = var.worker_ops_pool_size
      shape            = var.worker_ops_shape
      ocpus            = var.worker_ops_ocpus
      memory           = var.worker_ops_memory
      boot_volume_size = var.worker_ops_boot_volume_size
      image_type       = "custom"
      image_id         = local.worker_ops_image_id
      cloud_init       = [{ content_type = "text/cloud-config", content = yamlencode(local.cloud_init) }]
    }
    "oke-cpu" = {
      create           = local.create_workers && var.worker_cpu_enabled
      description      = "OKE-managed CPU Node Pool"
      placement_ads    = [substr(var.worker_cpu_ad, -1, 0)]
      size             = var.worker_cpu_pool_size
      shape            = var.worker_cpu_shape
      ocpus            = var.worker_cpu_ocpus
      memory           = var.worker_cpu_memory
      boot_volume_size = var.worker_cpu_boot_volume_size
      image_type       = "custom"
      image_id         = local.worker_cpu_image_id
      cloud_init       = [{ content_type = "text/cloud-config", content = yamlencode(local.cloud_init) }]
    }
    "oke-gpu" = {
      create           = local.create_workers && var.worker_gpu_enabled
      description      = "OKE-managed GPU Node Pool"
      placement_ads    = [substr(var.worker_gpu_ad, -1, 0)]
      size             = var.worker_gpu_pool_size
      shape            = var.worker_gpu_shape
      boot_volume_size = var.worker_gpu_boot_volume_size
      image_type       = "custom"
      image_id         = local.worker_gpu_image_id
      cloud_init       = [{ content_type = "text/cloud-config", content = yamlencode(local.cloud_init) }]
      node_labels      = { "oci.oraclecloud.com/disable-gpu-device-plugin" : var.disable_gpu_device_plugin ? "true" : "false" },
    }
    "oke-rdma" = {
      create                  = local.create_workers && var.worker_rdma_enabled
      description             = "Self-managed Cluster Network with RDMA"
      placement_ads           = [substr(var.worker_rdma_ad, -1, 0)]
      mode                    = "cluster-network"
      size                    = var.worker_rdma_pool_size
      shape                   = var.worker_rdma_shape
      boot_volume_size        = var.worker_rdma_boot_volume_size
      boot_volume_vpus_per_gb = var.worker_rdma_boot_volume_vpus_per_gb
      image_type              = "custom"
      image_id                = local.worker_rdma_image_id
      cloud_init              = [{ content_type = "text/cloud-config", content = yamlencode(local.cloud_init) }]
      node_labels             = { "oci.oraclecloud.com/disable-gpu-device-plugin" : var.disable_gpu_device_plugin ? "true" : "false" },
      agent_config = {
        are_all_plugins_disabled = false
        is_management_disabled   = false
        is_monitoring_disabled   = false
        plugins_config = {
          "Bastion"                             = "DISABLED"
          "Block Volume Management"             = "DISABLED"
          "Compute HPC RDMA Authentication"     = "ENABLED"
          "Compute HPC RDMA Auto-Configuration" = "ENABLED"
          "Compute Instance Monitoring"         = "ENABLED"
          "Compute Instance Run Command"        = "ENABLED"
          "Compute RDMA GPU Monitoring"         = "ENABLED"
          "Custom Logs Monitoring"              = "ENABLED"
          "Management Agent"                    = "ENABLED"
          "Oracle Autonomous Linux"             = "DISABLED"
          "OS Management Service Agent"         = "DISABLED"
        }
      }
    }
  }
}
