# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  metrics_server_version = one(helm_release.metrics_server[*].version)
  metrics_server_labels = merge(local.monitoring_labels, {
    "app.kubernetes.io/name"              = "metrics-server"
    "app.kubernetes.io/version"           = var.metrics_server_chart_version
    "service.istio.io/canonical-revision" = var.metrics_server_chart_version
    "sidecar.istio.io/inject"             = "true"
  })

  metrics_server_helm_values = {
    podLabels = local.metrics_server_labels
    replicas  = 2
    metrics   = { enabled = true }
    serviceMonitor = {
      enabled       = true // requires metrics.enabled = true
      interval      = local.scrape_interval
      scrapeTimeout = local.scrape_timeout
    }
  }
  metrics_server_helm_values_yaml = jsonencode(local.metrics_server_helm_values)
}

resource "helm_release" "metrics_server" {
  count             = var.install_monitoring && var.install_metrics_server ? 1 : 0
  depends_on        = [helm_release.prometheus]
  namespace         = var.monitoring_namespace
  name              = "metrics-server"
  chart             = "metrics-server"
  repository        = "https://kubernetes-sigs.github.io/metrics-server"
  version           = var.metrics_server_chart_version
  values            = [local.metrics_server_helm_values_yaml]
  create_namespace  = false
  recreate_pods     = true
  force_update      = true
  dependency_update = true
  wait              = false
  max_history       = 1
}
