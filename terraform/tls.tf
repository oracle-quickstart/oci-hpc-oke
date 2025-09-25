# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  user_public_ssh_key     = var.ssh_public_key != null ? trimspace(var.ssh_public_key) : ""
  bundled_ssh_public_keys = "${local.user_public_ssh_key}\n${trimspace(tls_private_key.stack_key.public_key_openssh)}"
  ssh_public_key          = local.deploy_from_operator && var.install_node_problem_detector_kube_prometheus_stack ? local.bundled_ssh_public_keys : local.user_public_ssh_key # need to use known public/private key pair to deploy resources via ORM 
}

resource "tls_private_key" "stack_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}