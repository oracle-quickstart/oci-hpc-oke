# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  invalid_desired_load_balancers = !var.create_public_subnets && var.preferred_kubernetes_services == "public"
  invalid_public_ep              = !var.create_public_subnets && var.control_plane_is_public
  invalid_bastion                = !var.create_public_subnets && (var.bastion_is_public && var.create_bastion)
  invalid_worker_rdma_image      = can(regex("(?i)oracle.*linux", data.oci_core_image.worker_rdma[0].display_name))
}

data "oci_core_image" "worker_rdma" {
  count    = coalesce(var.worker_rdma_image_custom_id, var.worker_rdma_image_platform_id, "none") != "none" ? 1 : 0
  image_id = coalesce(var.worker_rdma_image_custom_id, var.worker_rdma_image_platform_id, "none")
}

resource "null_resource" "validate_bastion_networking" {
  count = local.invalid_bastion ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Error: Cannot use public bastion if create_public_subnets is false' && exit 1"
  }

  lifecycle {
    precondition {
      condition     = !local.invalid_bastion
      error_message = "Error: Cannot set `bastion_is_public=true` if `create_public_subnets=false`"
    }
  }
}

resource "null_resource" "validate_cluster_services" {
  count = local.invalid_desired_load_balancers ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Error: Cannot use public load balancers if create_public_subnets is false' && exit 1"
  }

  lifecycle {
    precondition {
      condition     = !local.invalid_desired_load_balancers
      error_message = "Error: Cannot set `preferred_kubernetes_services=public` if `create_public_subnets=false`"
    }
  }
}

resource "null_resource" "validate_cluster_endpoint" {
  count = local.invalid_public_ep ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Error: Cannot use public IP address for the cluster endpoint if create_public_subnets is false' && exit 1"
  }

  lifecycle {
    precondition {
      condition     = !local.invalid_public_ep
      error_message = "Error: Cannot set `control_plane_is_public=true` if `create_public_subnets=false`"
    }
  }
}


resource "null_resource" "validate_worker_rdma_image" {
  count = coalesce(var.worker_rdma_image_custom_id, var.worker_rdma_image_platform_id, "none") != "none" ? 1 : 0

  lifecycle {
    precondition {
      condition     = !local.invalid_worker_rdma_image
      error_message = "Error: Only Ubuntu custom images are supported with GPU & RDMA worker pools. You selected an Oracle Linux image: ${data.oci_core_image.worker_rdma[0].display_name}"
    }
  }
}