# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "thanos" {
  count = alltrue([local.thanos_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [
    oci_objectstorage_bucket.thanos,
    time_sleep.wait_for_thanos_policy,
  ]
  namespace        = var.monitoring_namespace
  name             = "thanos"
  chart            = "${path.module}/files/thanos"
  values           = [local.thanos_chart_values]
  create_namespace = true
  wait             = true
  max_history      = 1
}

# Empties the stack-created bucket on destroy. kube-prometheus-stack depends on
# this resource, so on destroy it is removed (sidecars and Thanos Ruler gone)
# before the purge runs, and the purge runs before the thanos release and the
# bucket are deleted.
resource "null_resource" "thanos_predestroy_purge_via_orm" {
  count = alltrue([local.thanos_create_bucket, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  triggers = {
    kubeconfig   = yamlencode(local.patched_kube_config)
    namespace    = var.monitoring_namespace
    bucket       = local.thanos_bucket_name
    region       = var.region
    purge_script = file("${path.module}/files/thanos/predestroy-purge.sh")
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Stop on any error, so kubectl never falls back to ~/.kube/config.
      set -euo pipefail
      WORKDIR="$(mktemp -d "$${TMPDIR:-/tmp}/thanos-purge.XXXXXX")"
      trap 'rm -rf "$WORKDIR"' EXIT
      printf '%s' '${self.triggers.kubeconfig}' > "$WORKDIR/kubeconfig"
      export KUBECONFIG="$WORKDIR/kubeconfig"
      export PYTHONWARNINGS="ignore:the 'strict' parameter::urllib3.poolmanager"
      printf '%s' '${base64encode(self.triggers.purge_script)}' | base64 -d > "$WORKDIR/purge.sh"
      bash "$WORKDIR/purge.sh" '${self.triggers.namespace}' '${self.triggers.bucket}' '${self.triggers.region}'
    EOT
  }

  lifecycle {
    ignore_changes = [
      triggers["kubeconfig"],
      triggers["purge_script"],
    ]
  }

  depends_on = [helm_release.thanos, oci_objectstorage_bucket.thanos]
}
