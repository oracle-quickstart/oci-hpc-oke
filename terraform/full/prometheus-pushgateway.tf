# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  prometheus_pushgateway_version = one(helm_release.metrics_server[*].version)
  prometheus_pushgateway_helm_values = {
    serviceMonitor = {
      enabled       = true
      namespace     = var.monitoring_namespace
      interval      = local.scrape_interval
      scrapeTimeout = local.scrape_timeout
    }
  }
  prometheus_pushgateway_helm_values_yaml = jsonencode(local.prometheus_pushgateway_helm_values)
}

resource "helm_release" "prometheus_pushgateway" {
  count             = var.install_monitoring && var.install_prometheus_pushgateway ? 1 : 0
  depends_on        = [helm_release.prometheus]
  namespace         = var.monitoring_namespace
  name              = "prom-pushgateway"
  chart             = "prometheus-pushgateway"
  repository        = "https://prometheus-community.github.io/helm-charts"
  version           = var.prometheus_pushgateway_chart_version
  values            = [local.prometheus_pushgateway_helm_values_yaml]
  create_namespace  = false
  recreate_pods     = true
  force_update      = true
  dependency_update = true
  wait              = false
  max_history       = 1
}

