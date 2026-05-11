# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  invalid_desired_load_balancers = !var.create_public_subnets && var.preferred_kubernetes_services == "public"
  invalid_public_ep              = !var.create_public_subnets && var.control_plane_is_public
  invalid_bastion                = !var.create_public_subnets && var.create_bastion
  invalid_worker_rdma_image      = can(regex("(?i)oracle.*linux", one(data.oci_core_image.worker_rdma[*].display_name)))
  invalid_grace_blackwell_shape  = contains(["BM.GPU.GB200.4", "BM.GPU.GB200-v2.4", "BM.GPU.GB200-v3.4", "BM.GPU.GB300.4"], var.worker_rdma_shape)
  invalid_bastion_custom_image = var.create_bastion && local.bastion_image_type == "custom" && (
    var.bastion_image_use_uri ? trimspace(coalesce(var.bastion_image_custom_uri, "none")) == "none" : trimspace(coalesce(var.bastion_image_id, "none")) == "none"
  )
  invalid_operator_custom_image = var.create_operator && local.operator_image_type == "custom" && (
    var.operator_image_use_uri ? trimspace(coalesce(var.operator_image_custom_uri, "none")) == "none" : trimspace(coalesce(var.operator_image_id, "none")) == "none"
  )
  allowed_image_uri_prefixes = ["http://", "https://"]
  image_uri_values = {
    bastion     = lower(trimspace(coalesce(var.bastion_image_custom_uri, "none")))
    operator    = lower(trimspace(coalesce(var.operator_image_custom_uri, "none")))
    worker_ops  = lower(trimspace(coalesce(var.worker_ops_image_custom_uri, "none")))
    worker_cpu  = lower(trimspace(coalesce(var.worker_cpu_image_custom_uri, "none")))
    worker_gpu  = lower(trimspace(coalesce(var.worker_gpu_image_custom_uri, "none")))
    worker_rdma = lower(trimspace(coalesce(var.worker_rdma_image_custom_uri, "none")))
  }
  invalid_image_uri = anytrue([
    var.bastion_image_use_uri && !anytrue([for prefix in local.allowed_image_uri_prefixes : startswith(local.image_uri_values.bastion, prefix)]),
    var.operator_image_use_uri && !anytrue([for prefix in local.allowed_image_uri_prefixes : startswith(local.image_uri_values.operator, prefix)]),
    var.worker_ops_image_use_uri && !anytrue([for prefix in local.allowed_image_uri_prefixes : startswith(local.image_uri_values.worker_ops, prefix)]),
    var.worker_cpu_image_use_uri && !anytrue([for prefix in local.allowed_image_uri_prefixes : startswith(local.image_uri_values.worker_cpu, prefix)]),
    var.worker_gpu_image_use_uri && !anytrue([for prefix in local.allowed_image_uri_prefixes : startswith(local.image_uri_values.worker_gpu, prefix)]),
    var.worker_rdma_image_use_uri && !anytrue([for prefix in local.allowed_image_uri_prefixes : startswith(local.image_uri_values.worker_rdma, prefix)]),
  ])

  # Pods subnet capacity validation
  pods_required_ops  = var.worker_ops_pool_size * local.worker_ops_max_pods_per_node
  pods_required_cpu  = var.worker_cpu_enabled ? var.worker_cpu_pool_size * local.worker_cpu_max_pods_per_node : 0
  pods_required_gpu  = var.worker_gpu_enabled ? var.worker_gpu_pool_size * var.worker_gpu_max_pods_per_node : 0
  pods_required_rdma = var.worker_rdma_enabled ? var.worker_rdma_pool_size * var.worker_rdma_max_pods_per_node : 0
  total_pods_required = (
    local.pods_required_ops +
    local.pods_required_cpu +
    local.pods_required_gpu +
    local.pods_required_rdma
  )

  # Calculate pods subnet capacity (IPs available minus 3 reserved IPs)
  vcn_prefix_length     = tonumber(split("/", var.vcn_cidrs)[1])
  pods_subnet_prefix    = var.pods_sn_cidr != null ? tonumber(split("/", var.pods_sn_cidr)[1]) : local.vcn_prefix_length + 1
  pods_subnet_capacity  = pow(2, 32 - local.pods_subnet_prefix) - 3
  is_vcn_native_cni     = contains(["npn", "VCN-Native Pod Networking"], var.cni_type)
  invalid_pods_capacity = local.is_vcn_native_cni && local.total_pods_required > local.pods_subnet_capacity

  # FSS PV cannot be created when all deploy paths are inactive (private endpoint, no operator, no ORM)
  fss_pv_unreachable = alltrue([
    local.create_fss_effective,
    !local.deploy_from_local,
    !local.deploy_from_orm,
    !local.deploy_from_operator,
  ])

  invalid_slinky_deploy_path = alltrue([
    var.install_slinky,
    !local.slinky_deploy_from_operator,
  ])
  invalid_slinky_workers = alltrue([
    var.install_slinky,
    !var.worker_rdma_enabled,
    !var.worker_gpu_enabled,
  ])
  invalid_slinky_openldap_topology = alltrue([
    var.install_slinky,
    var.slinky_identity_enabled,
    var.slinky_openldap_primary_replicas != 1,
  ])

  # Check if the ssh_public_key has comment
  ssh_public_key_has_comment = can(regex("\\S+\\s+\\S+\\s+\\S+\\s?", var.ssh_public_key))

  invalid_gpu_operator_without_nfd = var.deploy_nvidia_gpu_operator && !var.deploy_node_feature_discovery
  invalid_nvidia_dra_without_nfd   = var.install_nvidia_dra_driver && var.worker_gmc_enabled && !var.deploy_node_feature_discovery
}

data "oci_core_image" "worker_rdma" {
  count    = coalesce(var.worker_rdma_image_custom_id, var.worker_rdma_image_platform_id, "none") != "none" ? 1 : 0
  image_id = coalesce(var.worker_rdma_image_custom_id, var.worker_rdma_image_platform_id, "none")
}

resource "null_resource" "validate_bastion_networking" {
  count = local.invalid_bastion ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Error: Bastion requires public subnets to be created' && exit 1"
  }

  lifecycle {
    precondition {
      condition     = !local.invalid_bastion
      error_message = "Creating a bastion requires public subnets. Please set `create_public_subnets=true` or set `create_bastion=false`."
    }
  }
}

resource "null_resource" "validate_cluster_services" {
  count = local.invalid_desired_load_balancers ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Error: Public Kubernetes services require public subnets to be created' && exit 1"
  }

  lifecycle {
    precondition {
      condition     = !local.invalid_desired_load_balancers
      error_message = "Public Kubernetes services require public subnets. Please set `create_public_subnets=true` or change `preferred_kubernetes_services` to a different value."
    }
  }
}

resource "null_resource" "validate_cluster_endpoint" {
  count = local.invalid_public_ep ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Error: Public cluster endpoint requires public subnets to be created' && exit 1"
  }

  lifecycle {
    precondition {
      condition     = !local.invalid_public_ep
      error_message = "A public cluster endpoint requires public subnets. Please set `create_public_subnets=true` or change `control_plane_is_public=false`."
    }
  }
}

resource "null_resource" "validate_worker_rdma_image" {
  count = coalesce(var.worker_rdma_image_custom_id, var.worker_rdma_image_platform_id, "none") != "none" ? 1 : 0

  lifecycle {
    precondition {
      condition     = !local.invalid_worker_rdma_image
      error_message = "GPU & RDMA worker pools only support Ubuntu images. The selected image '${one(data.oci_core_image.worker_rdma[*].display_name)}' is an Oracle Linux image. Please choose an Ubuntu-based custom image."
    }
  }
}

resource "null_resource" "validate_image_uri" {
  count = anytrue([var.bastion_image_use_uri, var.operator_image_use_uri, var.worker_ops_image_use_uri, var.worker_cpu_image_use_uri, var.worker_gpu_image_use_uri, var.worker_rdma_image_use_uri]) ? 1 : 0

  lifecycle {
    precondition {
      condition     = !local.invalid_image_uri
      error_message = "Error: Invalid image URI detected. Image import URIs must start with http:// or https://."
    }
  }
}

resource "null_resource" "validate_bastion_image_selection" {
  count = local.invalid_bastion_custom_image ? 1 : 0

  lifecycle {
    precondition {
      condition     = !local.invalid_bastion_custom_image
      error_message = "When bastion_image_type is custom, provide either bastion_image_id or enable bastion_image_use_uri with bastion_image_custom_uri."
    }
  }
}

resource "null_resource" "validate_operator_image_selection" {
  count = local.invalid_operator_custom_image ? 1 : 0

  lifecycle {
    precondition {
      condition     = !local.invalid_operator_custom_image
      error_message = "When operator_image_type is custom, provide either operator_image_id or enable operator_image_use_uri with operator_image_custom_uri."
    }
  }
}

resource "null_resource" "validate_grace_blackwell_shape" {
  count = local.invalid_grace_blackwell_shape ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Error: GB200 shapes require a different deployment process' && exit 1"
  }

  lifecycle {
    precondition {
      condition     = !local.invalid_grace_blackwell_shape
      error_message = "GB200/GB300 shapes (BM.GPU.GB200.4, BM.GPU.GB200-v2.4, BM.GPU.GB200-v3.4, BM.GPU.GB300.4) require a different deployment process. Please deploy the OKE cluster without the GPU & RDMA worker pool, then follow the GB200-specific instructions at: https://github.com/oracle-quickstart/oci-hpc-oke/tree/gb200"
    }
  }
}

resource "null_resource" "validate_pods_capacity" {
  count = local.invalid_pods_capacity ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Error: Total required pod IPs exceeds pods subnet capacity' && exit 1"
  }

  lifecycle {
    precondition {
      condition     = !local.invalid_pods_capacity
      error_message = <<-EOT
        Total required pod IPs (${local.total_pods_required}) exceeds pods subnet capacity (${local.pods_subnet_capacity}).
        Breakdown:
          - oke-system: ${local.pods_required_ops} (${var.worker_ops_pool_size} nodes × ${var.worker_ops_max_pods_per_node} pods)
          - oke-cpu: ${local.pods_required_cpu} (${var.worker_cpu_enabled ? var.worker_cpu_pool_size : 0} nodes × ${var.worker_cpu_max_pods_per_node} pods)
          - oke-gpu: ${local.pods_required_gpu} (${var.worker_gpu_enabled ? var.worker_gpu_pool_size : 0} nodes × ${var.worker_gpu_max_pods_per_node} pods)
          - oke-rdma: ${local.pods_required_rdma} (${var.worker_rdma_enabled ? var.worker_rdma_pool_size : 0} nodes × ${var.worker_rdma_max_pods_per_node} pods)
        Consider increasing the pods subnet size or reducing max_pods_per_node/pool_size values.
      EOT
    }
  }
}

resource "null_resource" "warn_fss_pv_unreachable" {
  count = local.fss_pv_unreachable ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Warning: create_fss=true but the Kubernetes API server is unreachable from this context (private endpoint, no operator, no ORM private endpoint). The FSS PersistentVolume will not be created. To resolve, enable the operator (create_operator=true with create_bastion=true), use a public control plane endpoint, or enable deploy_to_oke_from_orm=true when deploying via ORM.'"
  }

  lifecycle {
    precondition {
      condition     = !local.fss_pv_unreachable
      error_message = "create_fss=true but the Kubernetes API server is unreachable from this context (private endpoint, no operator, no ORM private endpoint). The FSS PersistentVolume will not be created. To resolve: enable the operator (create_operator=true with create_bastion=true), use a public control plane endpoint, or enable deploy_to_oke_from_orm=true when deploying via ORM."
    }
  }
}

resource "null_resource" "validate_slinky_deploy_path" {
  count = local.invalid_slinky_deploy_path ? 1 : 0

  lifecycle {
    precondition {
      condition     = !local.invalid_slinky_deploy_path
      error_message = "install_slinky=true currently deploys the full Slurm suite from the operator host. Please set create_bastion=true, create_operator=true, and deploy_to_oke_from_orm=false."
    }
  }
}

resource "null_resource" "validate_slinky_workers" {
  count = local.invalid_slinky_workers ? 1 : 0

  lifecycle {
    precondition {
      condition     = !local.invalid_slinky_workers
      error_message = "install_slinky=true requires either worker_rdma_enabled=true or worker_gpu_enabled=true so the stack can create a shape-specific Slurm worker nodeset."
    }
  }
}

resource "null_resource" "validate_slinky_openldap_topology" {
  count = local.invalid_slinky_openldap_topology ? 1 : 0

  lifecycle {
    precondition {
      condition     = !local.invalid_slinky_openldap_topology
      error_message = "The bundled HA OpenLDAP topology supports exactly one writable primary plus read replicas. Keep slinky_openldap_primary_replicas=1."
    }
  }
}

resource "null_resource" "ssh_public_key_should_have_comment" {
  count = alltrue([local.any_deployments_via_operator, var.ssh_public_key != null]) ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.ssh_public_key_has_comment
      error_message = "Error: SSH public key should have a comment. Please ensure the SSH public key has a comment."
    }
  }
}

resource "null_resource" "validate_gpu_operator_requires_nfd" {
  count = local.invalid_gpu_operator_without_nfd ? 1 : 0

  lifecycle {
    precondition {
      condition     = !local.invalid_gpu_operator_without_nfd
      error_message = "NVIDIA GPU Operator addon requires Node Feature Discovery. Please set `deploy_node_feature_discovery=true` or set `deploy_nvidia_gpu_operator=false`."
    }
  }
}

resource "null_resource" "validate_nvidia_dra_requires_nfd" {
  count = local.invalid_nvidia_dra_without_nfd ? 1 : 0

  lifecycle {
    precondition {
      condition     = !local.invalid_nvidia_dra_without_nfd
      error_message = "NVIDIA DRA driver requires Node Feature Discovery for GPU node selection. Please set `deploy_node_feature_discovery=true` or set `install_nvidia_dra_driver=false`."
    }
  }
}
