# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "kube_fledged" {
  count = alltrue([local.kube_fledged_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  name             = "kube-fledged"
  namespace        = "kube-fledged"
  create_namespace = true
  repository       = "https://senthilrch.github.io/kubefledged-charts/"
  chart            = "kube-fledged"
  version          = var.kube_fledged_chart_version
  values           = [yamlencode(local.kube_fledged_controller_values)]
  wait             = true
  timeout          = 600
  max_history      = 1

  depends_on = [module.oke, data.oci_resourcemanager_private_endpoint_reachable_ip.oke]
}

# A separate release installs the CRD/controller before CR creation and
# removes the CRs before the controller on destroy. No purge is requested.
resource "helm_release" "imagecaches" {
  count = alltrue([local.kube_fledged_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  name        = "oci-hpc-imagecaches"
  namespace   = "kube-fledged"
  chart       = "${path.module}/files/oci-hpc-imagecaches"
  values      = [yamlencode(local.kube_fledged_cache_values)]
  wait        = true
  timeout     = 600
  max_history = 1

  depends_on = [helm_release.kube_fledged, helm_release.kueue, kubectl_manifest.kueue_webhook_probe]
}
