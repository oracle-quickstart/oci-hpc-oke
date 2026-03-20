# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

module "kueue" {
  count  = alltrue([var.install_kueue, var.worker_rdma_enabled, local.deploy_from_operator]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "kueue"
  helm_chart_name     = "kueue"
  namespace           = "kueue-system"
  helm_repository_url = "oci://registry.k8s.io/kueue/charts"
  helm_chart_version  = var.kueue_chart_version

  pre_deployment_commands = [
    "export PATH=$PATH:/home/${var.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal"
  ]

  deployment_extra_args = ["--wait", "--timeout 300s", "--history-max 1"]

  post_deployment_commands = flatten([
    # Deploy Kueue Topology
    "cat <<'EOF' | kubectl apply -f -",
    split("\n", file("${path.module}/files/kueue/topology.yaml")),
    "EOF",
    # Deploy ResourceFlavor
    "cat <<'EOF' | kubectl apply -f -",
    split("\n", templatefile("${path.module}/files/kueue/resource-flavor.yaml.tpl", {
      flavor_name   = local.kueue_flavor_name
      shape         = var.worker_rdma_shape
      gpu_label_key = local.kueue_gpu_resource
    })),
    "EOF",
    # Deploy ClusterQueue
    "cat <<'EOF' | kubectl apply -f -",
    split("\n", templatefile("${path.module}/files/kueue/cluster-queue.yaml.tpl", {
      flavor_name  = local.kueue_flavor_name
      gpu_resource = local.kueue_gpu_resource
    })),
    "EOF",
    # Deploy LocalQueue
    "cat <<'EOF' | kubectl apply -f -",
    split("\n", templatefile("${path.module}/files/kueue/local-queue.yaml.tpl", {
      flavor_name = local.kueue_flavor_name
      namespace   = var.kueue_local_queue_default_namespace
    })),
    "EOF"
  ])

  helm_template_values_override = ""
  helm_user_values_override     = ""

  depends_on = [module.oke]
}
