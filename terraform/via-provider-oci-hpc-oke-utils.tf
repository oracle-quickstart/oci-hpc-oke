# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "oci_hpc_oke_utils" {
  count = alltrue([var.install_oci_hpc_oke_utils, anytrue([var.worker_rdma_enabled, var.worker_gmc_enabled, local.slinky_hostname_annotator_enabled]), local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [
    module.oke,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke
  ]
  namespace        = "kube-system"
  name             = "oci-hpc-oke-utils"
  chart            = "${path.module}/files/oci-hpc-oke-utils"
  create_namespace = false
  wait             = true
  timeout          = 300
  max_history      = 1

  values = [yamlencode({
    labeler = {
      enabled = var.install_rdma_labeler
    }
    # With a public control plane the Slinky charts still deploy via the
    # operator host, but the utilities chart deploys via this provider path,
    # so the annotator must be available here too.
    annotator = {
      enabled = local.slinky_hostname_annotator_enabled
    }
    prepuller = {
      enabled = var.install_image_prepuller
    }
    hostexec = {
      enabled = var.install_hostexec
    }
  })]
}
