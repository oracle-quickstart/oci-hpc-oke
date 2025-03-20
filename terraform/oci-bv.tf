# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "kubernetes_storage_class_v1" "oci_high_vpu_20" {
  count      = var.create_bv_high ? 1 : 0
  depends_on = [module.oke]
  metadata { name = "oci-bv-high" }
  allow_volume_expansion = true
  reclaim_policy         = "Delete"
  storage_provisioner    = "blockvolume.csi.oraclecloud.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    vpusPerGB = "20"
  }
}