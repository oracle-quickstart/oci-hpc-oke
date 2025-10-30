# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  invalid_desired_load_balancers = !var.create_public_subnets && var.preferred_kubernetes_services == "public"
  invalid_public_ep              = !var.create_public_subnets && var.control_plane_is_public
  invalid_bastion                = !var.create_public_subnets && (var.bastion_is_public && var.create_bastion)
  invalid_worker_rdma_image      = can(regex("(?i)oracle.*linux", data.oci_core_image.worker_rdma[0].display_name))
  invalid_gb200_shape            = contains(["BM.GPU.GB200.4", "BM.GPU.GB200-v2.4"], var.worker_rdma_shape)
}

data "oci_core_image" "worker_rdma" {
  count    = coalesce(var.worker_rdma_image_custom_id, var.worker_rdma_image_platform_id, "none") != "none" ? 1 : 0
  image_id = coalesce(var.worker_rdma_image_custom_id, var.worker_rdma_image_platform_id, "none")
}

resource "null_resource" "validate_bastion_networking" {
  count = local.invalid_bastion ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Error: Public bastion requires public subnets to be created' && exit 1"
  }

  lifecycle {
    precondition {
      condition     = !local.invalid_bastion
      error_message = "A public bastion requires public subnets. Please set `create_public_subnets=true` or change `bastion_is_public=false`."
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
      error_message = "GPU & RDMA worker pools only support Ubuntu images. The selected image '${data.oci_core_image.worker_rdma[0].display_name}' is an Oracle Linux image. Please choose an Ubuntu-based custom image."
    }
  }
}

resource "null_resource" "validate_gb200_shape" {
  count = local.invalid_gb200_shape ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Error: GB200 shapes require a different deployment process' && exit 1"
  }

  lifecycle {
    precondition {
      condition     = !local.invalid_gb200_shape
      error_message = "GB200 shapes (BM.GPU.GB200.4, BM.GPU.GB200-v2.4) require a different deployment process. Please deploy the OKE cluster without the GPU & RDMA worker pool, then follow the GB200-specific instructions at: https://github.com/oracle-quickstart/oci-hpc-oke/tree/gb200"
    }
  }
}