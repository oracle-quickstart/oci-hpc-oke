# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "prometheus" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [
    module.oke,
    helm_release.nginx,
    time_sleep.wait_for_lb_termination,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke
  ]
  namespace         = var.monitoring_namespace
  name              = "kube-prometheus-stack"
  chart             = "kube-prometheus-stack"
  repository        = "https://prometheus-community.github.io/helm-charts"
  version           = var.prometheus_stack_chart_version
  values            = ["${templatefile("./files/kube-prometheus/values.yaml.tftpl", { preferred_kubernetes_services = var.preferred_kubernetes_services})}"]
  create_namespace  = true
  recreate_pods     = false
  force_update      = true
  dependency_update = true
  wait              = true
  max_history       = 1
  set = var.preferred_kubernetes_services == "public" ? [
    {
      name  = "grafana.ingress.enabled",
      value = "true"
    },
    {
      name  = "grafana.ingress.ingressClassName",
      value = "nginx"
    },
    {
      name  = "grafana.ingress.annotations.cert-manager\\.io\\/cluster-issuer",
      value = "le-clusterissuer"
    },
    {
      name  = "grafana.ingress.hosts[0]",
      value = "grafana.${data.kubernetes_service.nginx_lb[0].status[0].load_balancer[0].ingress[0].ip}.${var.wildcard_dns_domain}"
    },
    {
      name  = "grafana.ingress.tls[0].hosts[0]",
      value = "grafana.${data.kubernetes_service.nginx_lb[0].status[0].load_balancer[0].ingress[0].ip}.${var.wildcard_dns_domain}"
    },
    {
      name  = "grafana.ingress.tls[0].secretName",
      value = "grafana-tls"
    }
    ] : [
    {
      name  = "grafana.service.type",
      value = "LoadBalancer"
    },
    {
      name  = "grafana.service.annotations.oci\\.oraclecloud\\.com\\/load-balancer-type",
      value = "lb"
    },
    {
      name  = "grafana.service.annotations.service\\.beta\\.kubernetes\\.io\\/oci-load-balancer-internal",
      type  = "string"
      value = "true"
    },
    {
      name  = "grafana.service.annotations.service\\.beta\\.kubernetes\\.io\\/oci-load-balancer-shape",
      value = "flexible"
    },
    {
      name  = "grafana.service.annotations.service\\.beta\\.kubernetes\\.io\\/oci-load-balancer-shape-flex-min",
      type  = "string"
      value = "100"
    },
    {
      name  = "grafana.service.annotations.service\\.beta\\.kubernetes\\.io\\/oci-load-balancer-shape-flex-max",
      type  = "string"
      value = "100"
    },
    {
      name  = "grafana.service.annotations.service\\.beta\\.kubernetes\\.io\\/oci-load-balancer-security-list-management-mode",
      type  = "string"
      value = "None"
    },
    {
      name  = "grafana.service.annotations.oci\\.oraclecloud\\.com\\/oci-network-security-groups"
      value = "${module.oke.int_lb_nsg_id}"
    }
  ]
  set_sensitive = [
    {
      name  = "grafana.adminPassword"
      value = random_password.grafana_admin_password.result
    }
  ]
}

resource "time_sleep" "wait_for_lb_termination" {
  count            = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  destroy_duration = "60s"
}

resource "time_sleep" "wait_for_lb_provisioning" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services != "public"]) ? 1 : 0

  depends_on      = [helm_release.prometheus]
  create_duration = "60s"
}

data "kubernetes_service" "grafana_internal_ip" {
  count = alltrue([anytrue([local.deploy_from_orm, local.deploy_from_local]), var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services != "public"]) ? 1 : 0

  depends_on = [time_sleep.wait_for_lb_provisioning]

  metadata {
    name      = try(format("%s-grafana", one(helm_release.prometheus.*.name)), "")
    namespace = one(helm_release.prometheus.*.namespace)
  }
}