# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  prometheus_stack_version = one(helm_release.prometheus[*].version)
  prometheus_labels = merge(local.monitoring_labels, {
    "app.kubernetes.io/name"              = "prometheus"
    "service.istio.io/canonical-name"     = "prometheus"
    "app.kubernetes.io/version"           = var.prometheus_stack_chart_version
    "service.istio.io/canonical-revision" = var.prometheus_stack_chart_version
    "sidecar.istio.io/inject"             = "true"
  })

  admission_labels = merge(local.prometheus_labels, {
    "app.kubernetes.io/name"          = "prometheus-admission"
    "service.istio.io/canonical-name" = "prometheus-admission"
    "sidecar.istio.io/inject"         = "false"
  })

  prometheus_helm_values = merge({
    alertmanager          = { enabled = false }
    defaultRules          = { create = false }
    coreDns               = { enabled = true }
    kubeApiServer         = { enabled = true }
    kubeControllerManager = { enabled = false }
    prometheusOperator = {
      admissionWebhooks = {
        enabled = true
        deployment = {
          enabled   = true
          podLabels = local.admission_labels
        }
        labels = local.admission_labels
      }
    }
    prometheus = {
      service = {
        annotations = {}
        labels      = local.prometheus_labels
        clusterIP   = ""
      }
      prometheusSpec = {
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        probeSelectorNilUsesHelmValues          = false
        scrapeConfigSelectorNilUsesHelmValues   = false
        remoteWriteDashboards                   = true
        scrapeInterval                          = local.scrape_interval
        scrapeTimeout                           = local.scrape_timeout
        retention                               = local.retention
        retentionSize                           = local.retention_size
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = var.retention_storageclass
              accessModes      = ["ReadWriteOnce"]
              resources = {
                requests = { storage = format("%vGi", var.retention_gb + 25) }
              }
            }
          }
        }
        requests = {
          cpu    = "1000m"
          memory = local.prom_server_memory_request_bytes
        }
        limits = {
          memory = local.prom_server_memory_limit_bytes
        }
      }
    }
    nodeExporter             = local.node_exporter_helm
    prometheus-node-exporter = local.node_exporter_values
  }, local.grafana_helm_values)
  prometheus_helm_values_yaml = jsonencode(local.prometheus_helm_values)
}

resource "helm_release" "prometheus" {
  count             = var.install_monitoring && var.install_prometheus_stack ? 1 : 0
  depends_on        = [module.oke]
  namespace         = var.monitoring_namespace
  name              = "prom"
  chart             = "kube-prometheus-stack"
  repository        = "https://prometheus-community.github.io/helm-charts"
  version           = var.prometheus_stack_chart_version
  values            = ["${file("./files/kube-prometheus-stack-values.yaml")}"]
  create_namespace  = true
  recreate_pods     = false
  force_update      = true
  dependency_update = true
  wait              = false
  max_history       = 1
  set_sensitive {
    name  = "grafana.adminPassword"
    value = random_password.grafana_admin_password.result
  }
}
