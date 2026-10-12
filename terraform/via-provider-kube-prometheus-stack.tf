# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

# Rendered once for both the provider path (below) and the operator path
# (module.kube_prometheus_stack), so the two can't drift.
locals {
  kube_prometheus_stack_values = templatefile("${path.module}/files/kube-prometheus/values.yaml.tftpl", {
    install_grafana               = var.install_grafana
    preferred_kubernetes_services = var.preferred_kubernetes_services
    setup_alerting                = var.setup_alerting
    monitoring_namespace          = var.monitoring_namespace
    prometheus_cpu                = var.prometheus_cpu
    prometheus_memory             = var.prometheus_memory
    prometheus_retention          = var.prometheus_retention
    install_thanos                = local.thanos_enabled
    prometheus_shards             = var.prometheus_shards
    prometheus_replicas           = var.prometheus_replicas
    thanos_version                = var.thanos_version
    thanos_upload_existing_blocks = var.thanos_upload_existing_blocks
  })
}

resource "helm_release" "prometheus" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  # Kueue's mutating webhook intercepts Job creates cluster-wide; the chart's
  # admission hook Jobs fail with "no endpoints available for service
  # kueue-webhook-service" while Kueue is still starting.
  # With Thanos, the thanos release must exist first: it creates the objstore
  # Secret the sidecars mount and the Thanos Query that Grafana points at.
  depends_on = [
    helm_release.ingress,
    time_sleep.wait_for_ingress_lb,
    helm_release.kueue,
    kubectl_manifest.kueue_webhook_probe,
    helm_release.thanos,
    null_resource.thanos_predestroy_purge_via_orm,
  ]
  namespace         = var.monitoring_namespace
  name              = "kube-prometheus-stack"
  chart             = "kube-prometheus-stack"
  repository        = "https://prometheus-community.github.io/helm-charts"
  version           = var.prometheus_stack_chart_version
  values            = [local.kube_prometheus_stack_values]
  create_namespace  = true
  recreate_pods     = false
  force_update      = true
  dependency_update = true
  wait              = true
  max_history       = 1
  set = var.install_grafana ? (var.preferred_kubernetes_services == "public" ? [
    {
      name  = "grafana.ingress.enabled",
      value = "true"
    },
    {
      name  = "grafana.ingress.ingressClassName",
      value = "contour"
    },
    {
      name  = "grafana.ingress.annotations.cert-manager\\.io\\/cluster-issuer",
      value = "le-clusterissuer"
    },
    {
      name  = "grafana.ingress.annotations.ingress\\.kubernetes\\.io/force-ssl-redirect",
      type  = "string"
      value = "true"
    },
    {
      name  = "grafana.ingress.hosts[0]",
      value = "grafana.${data.kubernetes_service_v1.ingress_lb[0].status[0].load_balancer[0].ingress[0].ip}.${var.wildcard_dns_domain}"
    },
    {
      name  = "grafana.ingress.tls[0].hosts[0]",
      value = "grafana.${data.kubernetes_service_v1.ingress_lb[0].status[0].load_balancer[0].ingress[0].ip}.${var.wildcard_dns_domain}"
    },
    {
      name  = "grafana.ingress.tls[0].secretName",
      value = "grafana-tls"
    }
    ] : concat([
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
      ], local.create_nsgs_effective ? [
      {
        name  = "grafana.service.annotations.oci\\.oraclecloud\\.com\\/oci-network-security-groups"
        value = local.lb_nsg_id_int
      }
  ] : [])) : []
  set_sensitive = var.install_grafana ? [
    {
      name  = "grafana.adminPassword"
      value = random_password.grafana_admin_password[0].result
    }
  ] : []
}

resource "time_sleep" "wait_for_lb_termination" {
  count            = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.install_grafana, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  destroy_duration = "60s"
}

resource "time_sleep" "wait_for_lb_provisioning" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.install_grafana, var.preferred_kubernetes_services != "public"]) ? 1 : 0

  depends_on      = [helm_release.prometheus]
  create_duration = "60s"
}

data "kubernetes_service_v1" "grafana_internal_ip" {
  count = alltrue([anytrue([local.deploy_from_orm, local.deploy_from_local]), var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.install_grafana, var.preferred_kubernetes_services != "public"]) ? 1 : 0

  depends_on = [time_sleep.wait_for_lb_provisioning]

  metadata {
    name      = try(format("%s-grafana", one(helm_release.prometheus.*.name)), "")
    namespace = one(helm_release.prometheus.*.namespace)
  }
}
