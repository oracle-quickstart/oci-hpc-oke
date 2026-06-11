# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "cert_manager" {
  count = alltrue([
    anytrue([
      var.preferred_kubernetes_services == "public",
      var.install_kueue,
      var.install_nvidia_dra_driver,
      alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack]),
      alltrue([var.install_slinky, var.slinky_identity_enabled]),
    ]),
    local.deploy_from_local || local.deploy_from_orm
  ]) ? 1 : 0
  depends_on = [
    module.oke,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke
  ]
  namespace         = "cert-manager"
  name              = "cert-manager"
  chart             = "cert-manager"
  repository        = "oci://quay.io/jetstack/charts"
  version           = var.cert_manager_chart_version
  values            = ["${file("${path.module}/files/cert-manager/values.yaml")}"]
  create_namespace  = true
  recreate_pods     = false
  force_update      = true
  dependency_update = true
  wait              = true
  max_history       = 1
}

resource "kubectl_manifest" "cert_manager_webhook_probe" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public", local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  # Create a harmless cert-manager resource first so provider retries absorb
  # webhook CA propagation races before the real ACME ClusterIssuer is applied.
  depends_on = [helm_release.cert_manager]

  yaml_body = file("${path.module}/files/cert-manager/webhook-readiness-probe.yaml")
}
