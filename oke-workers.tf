# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  create_workers = true
  ssh_authorized_keys = compact([
    trimspace(var.ssh_public_key),
  ])

  # TODO Use newer config w/ optional raid, input vars
  fs_setup = [
    { device = "/dev/nvme0n1", filesystem = "ext4", label = "nvme0n1" },
  ]
  disk_setup = {
    "/dev/nvme0n1" = { layout = true, overwrite = true, table_type = "gpt" }
  }
  mounts = [
    ["/dev/nvme0n1", "/var/lib/oke-crio"],
  ]

  # TODO update/configure
  #worker_default_image_id = "ocid1.image.oc1.ap-osaka-1.aaaaaaaak5tn6dovo6deu53p6ydzs66y4kvagqsgtcqumr4hgpouejo6jila"
  worker_ops_image_id     = coalesce(var.worker_ops_image_custom_id, "none")
  worker_cpu_image_type   = contains(["platform", "custom"], lower(var.worker_cpu_image_type)) ? "custom" : "oke"
  worker_cpu_image_id     = coalesce(var.worker_cpu_image_custom_id, var.worker_cpu_image_platform_id, "none")
  worker_gpu_image_type   = contains(["platform", "custom"], lower(var.worker_gpu_image_type)) ? "custom" : "oke"
  worker_gpu_image_id     = coalesce(var.worker_gpu_image_custom_id, var.worker_gpu_image_platform_id, "none")
  worker_rdma_image_type  = contains(["platform", "custom"], lower(var.worker_rdma_image_type)) ? "custom" : "oke"
  worker_rdma_image_id    = coalesce(var.worker_rdma_image_custom_id, var.worker_rdma_image_platform_id, "none")

  # TODO update/configure
  repo_uri = "https://objectstorage.us-ashburn-1.oraclecloud.com/p/1_NbjfnPPmyyklGibGM-qEpujw9jEpWSLa9mXEIUFCFYqqHdUh5cFAWbj870h-g0/n/hpc_limited_availability/b/oke_node_packages"
  yum_repos = {
    oke-node = {
      name     = "Oracle Container Engine for Kubernetes Nodes"
      baseurl  = "${local.repo_uri}/o/el/$releasever/$basearch"
      gpgcheck = false
    }
  }
  apt = {
    sources = {
      oke-node = {
        source = "deb [trusted=yes] ${local.repo_uri}/o/1.29.1/ubuntu stable main"
      }
    }
  }
  packages = [
    ["oci-oke-node-all", "1.29.1*"],
  ]

  runcmd_bootstrap_cpu = <<-EOT
    oke bootstrap \
        --manage-gpu-services \
        --crio-extra-args "--root /var/lib/oke-crio" \
      || echo "Error starting OKE worker node" >&2
  EOT

   runcmd_bootstrap_gpu = <<-EOT
    oke bootstrap \
        --manage-gpu-services \
        --crio-extra-args "--root /var/lib/oke-crio" \
      || echo "Error starting OKE worker node" >&2
  EOT 

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
  cloud_init_gpu = {
    ssh_authorized_keys = local.ssh_authorized_keys
    yum_repos           = local.yum_repos
    apt                 = local.apt
    packages            = local.packages
    runcmd              = [local.runcmd_bootstrap_gpu]
    write_files         = local.write_files
    fs_setup            = local.fs_setup
    disk_setup          = local.disk_setup
    mounts              = local.mounts
  }

  cloud_init_cpu = {
  ssh_authorized_keys = local.ssh_authorized_keys
  yum_repos           = local.yum_repos
  apt                 = local.apt
  packages            = local.packages
  runcmd              = [local.runcmd_bootstrap_cpu]
  write_files         = local.write_files
  fs_setup            = local.fs_setup
  disk_setup          = local.disk_setup
  mounts              = local.mounts
  }

  worker_cloud_init_cpu = [{ content_type = "text/cloud-config", content = yamlencode(local.cloud_init_cpu) }]
  worker_cloud_init_gpu = [{ content_type = "text/cloud-config", content = yamlencode(local.cloud_init_gpu) }]

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
      image_type              = "custom"
      image_id         = local.worker_ops_image_id
      cloud_init       = [{ content_type = "text/cloud-config", content = yamlencode(local.cloud_init_cpu) }]
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
      cloud_init       = [{ content_type = "text/cloud-config", content = yamlencode(local.cloud_init_cpu) }]
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
      cloud_init       = [{ content_type = "text/cloud-config", content = yamlencode(local.cloud_init_gpu) }]
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
      cloud_init              = [{ content_type = "text/cloud-config", content = yamlencode(local.cloud_init_gpu) }]
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
