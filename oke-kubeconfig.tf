# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  endpoint_port   = 6443
  kubeconfig_path = pathexpand(format("~/.kubeconfig.%s", local.state_id))
  kubeconfig_user = try(one(one(module.oke[*].cluster_kubeconfig).users[*]), tomap({}))
  user_token_env = var.oci_auth != null ? [
    { name = "OCI_CLI_AUTH", value = var.oci_auth }
  ] : []
  user_token_args = concat(
    ["--region", var.region],
    var.oci_profile != null ? ["--profile", var.oci_profile] : [],
    ["ce", "cluster", "generate-token"],
    ["--cluster-id", one(module.oke[*].cluster_id)],
  )
  kubeconfig_user_env = merge(local.kubeconfig_user, {
    user = { exec = {
      apiVersion = "client.authentication.k8s.io/v1beta1"
      command    = "oci"
      args       = local.user_token_args
      env        = local.user_token_env
  } } })
  kubeconfig_content = yamlencode(merge(one(module.oke[*].cluster_kubeconfig), {
    users = [local.kubeconfig_user_env]
  }))
}
