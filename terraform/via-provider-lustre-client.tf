# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "lustre_client" {
  count = alltrue([var.create_lustre, var.install_lustre_client, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [
    module.oke,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke
  ]
  namespace         = "kube-system"
  name              = "lustre-client-installer"
  chart             = "lustre-client-installer"
  repository        = "https://oci-hpc.github.io/oke-lustre-client/"
  version           = var.lustre_client_helm_chart_version
  values            = []
  create_namespace  = false
  recreate_pods     = true
  force_update      = true
  dependency_update = true
  wait              = false
  max_history       = 1
}

resource "kubectl_manifest" "lustre_pv" {
  count = alltrue([var.create_lustre, var.install_lustre_client, var.create_lustre_pv, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  depends_on = [
    module.oke,
    helm_release.nginx,
    helm_release.lustre_client
  ]

  yaml_body = templatefile(
    "${path.root}/files/lustre/lustre-pv.yaml.tpl",
    {
      lustre_storage_size = floor(var.lustre_size_in_tb),
      lustre_ip           = one(oci_lustre_file_storage_lustre_file_system.lustre.*.management_service_address),
      lustre_fs_name      = var.lustre_file_system_name,
    }
  )
}