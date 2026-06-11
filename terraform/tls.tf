# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  user_public_ssh_key     = var.ssh_public_key != null ? trimspace(var.ssh_public_key) : ""
  bundled_ssh_public_keys = "${local.user_public_ssh_key}\n${trimspace(tls_private_key.stack_key.public_key_openssh)}"
  # Always bundle the stack key. Bundling only when via-operator deployments are
  # enabled changes the operator's ssh_public_key trigger when a feature like
  # Slinky is enabled on an existing stack, forcing an operator replacement (and
  # leaving an existing bastion without the stack key).
  ssh_public_key = local.bundled_ssh_public_keys
}

resource "tls_private_key" "stack_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}