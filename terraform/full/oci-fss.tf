# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  fss_export_path = format("/oke-gpu-%v", local.state_id)
}

data "oci_file_storage_mount_targets" "fss" {
  count               = var.create_fss ? 1 : 0
  availability_domain = var.fss_ad
  compartment_id      = var.compartment_ocid
  id                  = oci_file_storage_mount_target.fss_mt.0.id
}

data "oci_file_storage_exports" "fss" {
  count          = var.create_fss ? 1 : 0
  compartment_id = var.compartment_ocid
  export_set_id  = oci_file_storage_mount_target.fss_mt.0.export_set_id
}

data "oci_core_private_ip" "fss_mt_ip" {
  count         = var.create_fss ? 1 : 0
  private_ip_id = data.oci_file_storage_mount_targets.fss.0.mount_targets[0].private_ip_ids[0]
}

resource "oci_file_storage_file_system" "fss" {
  count               = var.create_fss ? 1 : 0
  availability_domain = var.fss_ad
  compartment_id      = var.compartment_ocid
  display_name        = "${local.cluster_name}-fss"
}

resource "oci_file_storage_mount_target" "fss_mt" {
  count               = var.create_fss ? 1 : 0
  availability_domain = var.fss_ad
  compartment_id      = var.compartment_ocid
  subnet_id           = module.oke.fss_subnet_id
  display_name        = "${local.cluster_name}-mt"
  nsg_ids             = [module.oke.fss_nsg_id]
}

resource "oci_file_storage_export" "FSSExport" {
  count          = var.create_fss ? 1 : 0
  export_set_id  = oci_file_storage_mount_target.fss_mt.0.export_set_id
  file_system_id = oci_file_storage_file_system.fss.0.id
  path           = local.fss_export_path
}

resource "kubernetes_persistent_volume_v1" "fss" {
  count      = var.create_fss ? 1 : 0
  depends_on = [oci_file_storage_mount_target.fss_mt]
  metadata {
    name = "fss-pv"
  }
  spec {
    capacity = {
      storage = "50Gi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      csi {
        driver        = "fss.csi.oraclecloud.com"
        volume_handle = format("%v:%v:%s", oci_file_storage_file_system.fss.0.id, data.oci_core_private_ip.fss_mt_ip.0.ip_address, local.fss_export_path)
      }
    }
  }
}