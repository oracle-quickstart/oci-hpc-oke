# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

data "kubectl_file_documents" "mpi_operator" {
  content = file("${path.module}/files/mpi-operator/mpi-operator.yaml")
}

resource "kubectl_manifest" "mpi_operator" {
  for_each = alltrue([var.install_mpi_operator, local.deploy_from_local || local.deploy_from_orm]) ? data.kubectl_file_documents.mpi_operator.manifests : {}

  yaml_body         = each.value
  server_side_apply = true

  depends_on = [
    module.oke,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke
  ]
}
