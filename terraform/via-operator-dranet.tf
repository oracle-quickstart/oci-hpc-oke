# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

module "dranet" {
  count  = alltrue([var.install_dranet, local.deploy_from_operator]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = local.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = local.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "dranet"
  helm_chart_name     = "dranet"
  namespace           = "kube-system"
  helm_repository_url = "oci://registry.k8s.io/networking/charts"
  helm_chart_version  = var.dranet_chart_version

  pre_deployment_commands = [
    "export PATH=$PATH:/home/${local.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal",
    "export PYTHONWARNINGS=\"ignore:the 'strict' parameter::urllib3.poolmanager\""
  ]

  deployment_extra_args = ["--wait", "--timeout 300s", "--history-max 1"]

  post_deployment_commands = flatten([
    "cat <<'EOF' | kubectl apply -f -",
    split("\n", file("${path.module}/files/dranet/deviceclass.yaml")),
    "EOF",
  ])

  # Native InfiniBand NICs stay on the host, where the OKE health checks read them.
  helm_template_values_override = yamlencode({
    args = {
      moveIBInterfaces = false
    }
  })
  helm_user_values_override = ""

  depends_on = [module.oke]
}
