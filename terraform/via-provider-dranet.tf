# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "dranet" {
  count = alltrue([var.install_dranet, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [
    module.oke,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke
  ]

  namespace        = "kube-system"
  name             = "dranet"
  chart            = "oci://registry.k8s.io/networking/charts/dranet"
  version          = var.dranet_chart_version
  create_namespace = false
  wait             = true
  timeout          = 300
  max_history      = 1

  # Native InfiniBand NICs stay on the host, where the OKE health checks read them.
  values = [yamlencode({
    args = {
      moveIBInterfaces = false
    }
  })]
}

resource "kubectl_manifest" "dranet_device_class" {
  count = alltrue([var.install_dranet, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body  = file("${path.module}/files/dranet/deviceclass.yaml")
  depends_on = [helm_release.dranet]
}
