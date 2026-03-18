# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

module "oci_hpc_oke_utils" {
  count  = alltrue([var.worker_rdma_enabled, local.deploy_from_operator]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name = "oci-hpc-oke-utils"
  namespace       = "kube-system"
  helm_chart_path = "${path.module}/files/oci-hpc-oke-utils"

  pre_deployment_commands = [
    "export PATH=$PATH:/home/${var.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal"
  ]
  deployment_extra_args    = ["--wait", "--timeout 300s", "--history-max 1"]
  post_deployment_commands = []

  helm_template_values_override = yamlencode({
    labeler = {
      enabled = var.install_rdma_labeler
    }
    prepuller = {
      enabled = var.install_image_prepuller
    }
  })
  helm_user_values_override = ""

  depends_on = [module.oke]
}
