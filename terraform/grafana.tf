# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  grafana_dashboard_path  = "${path.module}/files/grafana/dashboards"
  grafana_dashboard_files = fileset(local.grafana_dashboard_path, "*.json")
  grafana_dashboards = (var.install_node_problem_detector_kube_prometheus_stack && var.install_grafana && var.install_grafana_dashboards) ? {
    for f in local.grafana_dashboard_files :
    f => file(join("/", [local.grafana_dashboard_path, f]))
  } : {}

  grafana_alert_path  = "${path.module}/files/grafana/alerts"
  grafana_alert_files = fileset(local.grafana_alert_path, "*.yaml")
  grafana_alerts = (var.install_node_problem_detector_kube_prometheus_stack && var.install_grafana && var.install_grafana_dashboards) ? {
    for f in local.grafana_alert_files :
    f => file(join("/", [local.grafana_alert_path, f]))
  } : {}
}

resource "kubernetes_config_map_v1" "grafana_dashboards" {
  for_each   = local.grafana_dashboards
  depends_on = [helm_release.prometheus]
  metadata {
    name      = format("dashboard-%s", trimsuffix(each.key, ".json"))
    namespace = var.monitoring_namespace
    annotations = {
      grafana_folder = "OKE"
    }
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = { (each.key) = each.value }
}

resource "kubernetes_config_map_v1" "grafana_alerts" {
  for_each   = local.grafana_alerts
  depends_on = [helm_release.prometheus]
  metadata {
    name      = format("alert-%s", trimsuffix(each.key, ".yaml"))
    namespace = var.monitoring_namespace
    labels = {
      grafana_alert = "1"
    }
  }
  data = { (each.key) = each.value }
}


resource "random_password" "grafana_admin_password" {
  length           = 16
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#$%&*()-_=+[]:?"
}