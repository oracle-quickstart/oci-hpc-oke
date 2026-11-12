# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

module "kube_fledged" {
  count  = alltrue([local.kube_fledged_enabled, local.deploy_from_operator]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = local.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = local.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name               = "kube-fledged"
  namespace                     = "kube-fledged"
  helm_repository_url           = "https://senthilrch.github.io/kubefledged-charts/"
  helm_chart_name               = "kube-fledged"
  helm_chart_version            = var.kube_fledged_chart_version
  helm_template_values_override = yamlencode(local.kube_fledged_controller_values)

  pre_deployment_commands = [
    "export PATH=$PATH:/home/${local.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal",
  ]
  deployment_extra_args     = ["--wait", "--timeout 600s", "--history-max 1"]
  post_deployment_commands  = []
  helm_user_values_override = ""

  depends_on = [module.oke]
}

module "imagecaches" {
  count  = alltrue([local.kube_fledged_enabled, local.deploy_from_operator]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = local.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = local.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name               = "oci-hpc-imagecaches"
  namespace                     = "kube-fledged"
  helm_chart_path               = "${path.module}/files/oci-hpc-imagecaches"
  helm_template_values_override = yamlencode(local.kube_fledged_cache_values)

  pre_deployment_commands = [
    "export PATH=$PATH:/home/${local.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal",
  ]
  deployment_extra_args     = ["--wait", "--timeout 600s", "--history-max 1"]
  post_deployment_commands  = []
  helm_user_values_override = ""

  depends_on = [module.kube_fledged, module.kueue]
}
