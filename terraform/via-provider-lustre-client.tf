# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "kubectl_manifest" "lustre_pv" {
  count = alltrue([var.create_lustre, var.create_lustre_pv, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  depends_on = [
    module.oke,
    helm_release.ingress,
  ]

  yaml_body = templatefile(
    "${path.module}/files/lustre/lustre-pv.yaml.tpl",
    {
      lustre_storage_size = floor(var.lustre_size_in_tb),
      lustre_ip           = one(oci_lustre_file_storage_lustre_file_system.lustre.*.management_service_address),
      lustre_fs_name      = var.lustre_file_system_name,
    }
  )
}
