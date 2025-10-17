# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "nginx" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public", local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [
    module.oke,
    time_sleep.wait_for_ingress_lb_termination,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke
  ]
  namespace  = "nginx"
  name       = "ingress-nginx"
  chart      = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  version    = var.nginx_chart_version
  values = [
    templatefile(
      "${path.root}/files/nginx-ingress/values.yaml.tpl",
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
  destroy_duration = "60s"
}

resource "kubectl_manifest" "cluster_issuer" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public", local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  depends_on = [
    module.oke,
    helm_release.nginx
  ]

  yaml_body = file("${path.root}/files/cert-manager/cluster-issuer.yaml")
}

resource "time_sleep" "wait_for_nginx_lb" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public", local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  depends_on = [helm_release.nginx]

  create_duration = "60s"
}

