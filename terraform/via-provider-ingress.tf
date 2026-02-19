# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "ingress" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public", local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [
    time_sleep.wait_for_ingress_lb_termination
  ]
  namespace  = "projectcontour"
  name       = "contour"
  chart      = "contour"
  repository = "https://projectcontour.github.io/helm-charts/"
  version    = var.ingress_chart_version
  values = [
    templatefile(
      "${path.module}/files/ingress/values.yaml.tpl",
      {
        min_bw    = 10,
        max_bw    = 100,
        lb_nsg_id = var.preferred_kubernetes_services == "public" ? module.oke.pub_lb_nsg_id : module.oke.int_lb_nsg_id
        state_id  = local.state_id
      }
    )
  ]
  create_namespace  = true
  recreate_pods     = false
  force_update      = true
  dependency_update = true
  wait              = true
  max_history       = 1

}

resource "time_sleep" "wait_for_ingress_lb_termination" {
  count            = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public", local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  destroy_duration = "120s"

  depends_on = [
    helm_release.cert_manager
  ]
}

resource "kubectl_manifest" "cluster_issuer" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public", local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  depends_on = [
    helm_release.ingress,
  ]

  yaml_body = (var.use_lets_encrypt_prod_endpoint ?
    templatefile("${path.module}/files/cert-manager/cluster-issuer-prod.yaml", { state = local.state_id }) :
    templatefile("${path.module}/files/cert-manager/cluster-issuer-staging.yaml", { state = local.state_id })
  )
}

resource "time_sleep" "wait_for_ingress_lb" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public", local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  depends_on = [helm_release.ingress]

  create_duration = "60s"
}