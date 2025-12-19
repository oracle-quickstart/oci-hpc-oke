
# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  grafana_common_dashboard_dir = var.create_cluster ? "${path.module}/files/grafana/dashboards/common" : null
  grafana_amd_dashboard_dir    = var.create_cluster ? "${path.module}/files/grafana/dashboards/amd" : null
  grafana_nvidia_dashboard_dir = var.create_cluster ? "${path.module}/files/grafana/dashboards/nvidia" : null

  grafana_common_dashboard_files = var.create_cluster ? fileset("${local.grafana_common_dashboard_dir}", "*.json") : null
  grafana_amd_dashboard_files    = var.create_cluster ? fileset("${local.grafana_amd_dashboard_dir}", "*.json") : null
  grafana_nvidia_dashboard_files = var.create_cluster ? fileset("${local.grafana_nvidia_dashboard_dir}", "*.json") : null 

  grafana_common_dashboard_files_path = (var.create_cluster && var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? [for f in local.grafana_common_dashboard_files : join("/", ["${local.grafana_common_dashboard_dir}", f])] : []
  grafana_amd_dashboard_files_path    = (var.create_cluster && var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? [for f in local.grafana_amd_dashboard_files : join("/", ["${local.grafana_amd_dashboard_dir}", f])] : []
  grafana_nvidia_dashboard_files_path = (var.create_cluster && var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? [for f in local.grafana_nvidia_dashboard_files : join("/", ["${local.grafana_nvidia_dashboard_dir}", f])] : []

  grafana_common_dashboards = (var.create_cluster && var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? {
    for f in local.grafana_common_dashboard_files :
    f => file(join("/", ["${local.grafana_common_dashboard_dir}", f]))
  } : {}
  grafana_amd_dashboards = (var.create_cluster && var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? {
    for f in local.grafana_amd_dashboard_files :
    f => file(join("/", ["${local.grafana_amd_dashboard_dir}", f]))
  } : {}
  grafana_nvidia_dashboards = (var.create_cluster && var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? {
    for f in local.grafana_nvidia_dashboard_files :
    f => file(join("/", ["${local.grafana_nvidia_dashboard_dir}", f]))
  } : {}

  grafana_alert_dir   = var.create_cluster ? "${path.module}/files/grafana/alerts" : null
  grafana_alert_files = var.create_cluster ? fileset(local.grafana_alert_dir, "*.yaml") : null
  grafana_alerts = (var.create_cluster && var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? {
    for f in local.grafana_alert_files :
    f => file(join("/", [local.grafana_alert_dir, f]))
  } : {}

  grafana_alert_files_path = (var.create_cluster && var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? [for f in local.grafana_alert_files : join("/", ["${local.grafana_alert_dir}", f])] : []
}

resource "random_password" "grafana_admin_password" {
  count = var.create_cluster ? 1 : 0
  length           = 16
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#$%&*()-_=+[]:?"
}
