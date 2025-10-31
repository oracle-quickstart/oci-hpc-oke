# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  unique_image_urls = distinct(compact([var.worker_ops_image_custom_uri, var.worker_cpu_image_custom_uri, var.worker_gpu_image_custom_uri, var.worker_rdma_image_custom_uri]))
}

resource "oci_core_image" "imported_image" {
  for_each = toset(local.unique_image_urls)

  compartment_id = var.compartment_ocid
  display_name   = format("%v-%v", element(split("/", each.value), length(split("/", each.value))-1), local.state_id) 

  image_source_details {
    source_type = "objectStorageUri"
    source_uri  = each.value
  }
}