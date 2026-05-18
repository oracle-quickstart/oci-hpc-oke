# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

module "nvidia_dra_driver" {
  count  = alltrue([var.install_nvidia_dra_driver, var.worker_gmc_enabled, local.deploy_from_operator]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "dra-driver-nvidia-gpu"
  helm_chart_name     = "dra-driver-nvidia-gpu"
  namespace           = "dra-driver-nvidia-gpu"
  helm_repository_url = "oci://registry.k8s.io/dra-driver-nvidia/charts"
  helm_chart_version  = var.nvidia_dra_driver_chart_version

  pre_deployment_commands = [
    "export PATH=$PATH:/home/${var.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal"
  ]

  deployment_extra_args    = ["--wait", "--timeout 300s", "--history-max 1"]
  post_deployment_commands = []

  helm_template_values_override = yamlencode({
    nvidiaDriverRoot            = "/"
    gpuResourcesEnabledOverride = false
    resources = {
      gpus = {
        enabled = false
      }
      computeDomains = {
        enabled = true
      }
    }
    kubeletPlugin = {
      tolerations = [
        {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    }
  })
  helm_user_values_override = ""

  depends_on = [module.oke]
}
