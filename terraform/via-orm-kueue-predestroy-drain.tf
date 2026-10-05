# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

# Drain all Kueue CRs before the chart is uninstalled so the CRD cascade does not
# hang on resource-in-use finalizers.

locals {
  kube_config = module.oke.cluster_kubeconfig
  patched_kube_config = merge(local.kube_config, {
    "clusters" = [
      for c in local.kube_config["clusters"] : {
        "name" = c["name"]
        "cluster" = {
          "server"                   = local.deploy_from_orm ? local.cluster_orm_endpoint : (local.deploy_from_local ? local.cluster_public_endpoint : "not-defined")
          "insecure-skip-tls-verify" = true
        }
      }
    ]
    # Same exec args as the providers, so oci_profile applies.
    "users" = [
      for u in local.kube_config["users"] : {
        "name" = u["name"]
        "user" = {
          "exec" = merge(u["user"]["exec"], { "args" = local.kube_exec_args })
        }
      }
    ]
  })
}

resource "null_resource" "kueue_predestroy_drain_via_orm" {
  count = alltrue([var.install_kueue, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  triggers = {
    kubeconfig   = yamlencode(local.patched_kube_config)
    drain_script = file("${path.module}/files/kueue/predestroy-drain.sh")
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Stop on any error, so kubectl never falls back to ~/.kube/config.
      set -euo pipefail
      WORKDIR="$(mktemp -d "$${TMPDIR:-/tmp}/kueue-drain.XXXXXX")"
      trap 'rm -rf "$WORKDIR"' EXIT
      printf '%s' '${self.triggers.kubeconfig}' > "$WORKDIR/kubeconfig"
      export KUBECONFIG="$WORKDIR/kubeconfig"
      export PYTHONWARNINGS="ignore:the 'strict' parameter::urllib3.poolmanager"
      printf '%s' '${base64encode(self.triggers.drain_script)}' | base64 -d > "$WORKDIR/drain.sh"
      bash "$WORKDIR/drain.sh"
    EOT
  }

  lifecycle {
    ignore_changes = [
      triggers["kubeconfig"],
      triggers["drain_script"]
    ]
  }

  depends_on = [helm_release.kueue]
}
