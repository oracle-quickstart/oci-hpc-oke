
# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  grafana_common_dashboard_dir = "${path.module}/files/grafana/dashboards/common"
  grafana_gpu_dashboard_dir    = "${path.module}/files/grafana/dashboards/gpu"
  grafana_oci_dashboard_dir    = "${path.module}/files/grafana/dashboards/oci"

  grafana_common_dashboard_files = fileset("${local.grafana_common_dashboard_dir}", "*.json")
  grafana_gpu_dashboard_files    = fileset("${local.grafana_gpu_dashboard_dir}", "*.json")
  grafana_oci_dashboard_files    = fileset("${local.grafana_oci_dashboard_dir}", "*.json")

  grafana_common_dashboard_files_path = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? [for f in local.grafana_common_dashboard_files : join("/", ["${local.grafana_common_dashboard_dir}", f])] : []
  grafana_gpu_dashboard_files_path    = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? [for f in local.grafana_gpu_dashboard_files : join("/", ["${local.grafana_gpu_dashboard_dir}", f])] : []
  grafana_oci_dashboard_files_path    = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards && var.setup_oci_metrics_exporter) ? [for f in local.grafana_oci_dashboard_files : join("/", ["${local.grafana_oci_dashboard_dir}", f])] : []

  grafana_common_dashboards = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? {
    for f in local.grafana_common_dashboard_files :
    f => file(join("/", ["${local.grafana_common_dashboard_dir}", f]))
  } : {}
  grafana_gpu_dashboard_sources = {
    for f in local.grafana_gpu_dashboard_files :
    f => file(join("/", ["${local.grafana_gpu_dashboard_dir}", f]))
  }
  grafana_gpu_health_dashboard = jsondecode(local.grafana_gpu_dashboard_sources["gpu-health-status.json"])
  grafana_gpu_health_panels = [
    for panel in local.grafana_gpu_health_dashboard.panels : panel
    if(panel.id != 7 || local.has_nvidia_gpu) && (panel.id != 23 || local.has_amd_gpu)
  ]
  grafana_gpu_health_panels_reflowed = [
    for index, panel in local.grafana_gpu_health_panels :
    panel.type == "stat" ? merge(panel, {
      gridPos = merge(panel.gridPos, {
        x = (index % 8) * 3
        y = floor(index / 8) * 3
      })
    }) : panel
  ]
  grafana_gpu_dashboards = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? {
    for f, content in local.grafana_gpu_dashboard_sources :
    f => f == "gpu-health-status.json" ? jsonencode(merge(local.grafana_gpu_health_dashboard, {
      panels = local.grafana_gpu_health_panels_reflowed
    })) : content
  } : {}
  grafana_oci_dashboards = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards && var.setup_oci_metrics_exporter) ? {
    for f in local.grafana_oci_dashboard_files :
    f => file(join("/", ["${local.grafana_oci_dashboard_dir}", f]))
  } : {}

  grafana_alert_dir   = "${path.module}/files/grafana/alerts"
  grafana_alert_files = fileset(local.grafana_alert_dir, "*.yaml")
  grafana_amd_alert_files = [
    "gpu-bad-pages.yaml",
  ]
  grafana_nvidia_alert_files = [
    "dcgm-health.yaml",
    "gpu-fabric-manager.yaml",
    "gpu-imex.yaml",
    "gpu-row-remap.yaml",
    "gpu-xid.yaml",
    "nvlink-speed.yaml",
    "rdma-vf-counters.yaml",
    "rdma-vf-routes.yaml",
  ]
  grafana_alert_files_filtered = [
    for f in local.grafana_alert_files : f
    if(!contains(local.grafana_amd_alert_files, f) || local.has_amd_gpu) &&
    (!contains(local.grafana_nvidia_alert_files, f) || local.has_nvidia_gpu) &&
    (f != "npd-delete-nvidia-alerts.yaml" || (local.has_amd_gpu && !local.has_nvidia_gpu)) &&
    (f != "npd-delete-amd-alerts.yaml" || (local.has_nvidia_gpu && !local.has_amd_gpu))
  ]
  grafana_alerts = (var.install_monitoring && var.install_grafana && var.setup_alerting) ? {
    for f in local.grafana_alert_files_filtered :
    f => file(join("/", [local.grafana_alert_dir, f]))
  } : {}

  grafana_alert_files_path = (var.install_monitoring && var.install_grafana && var.setup_alerting) ? [for f in local.grafana_alert_files_filtered : join("/", ["${local.grafana_alert_dir}", f])] : []
}

resource "random_password" "grafana_admin_password" {
  count = var.install_grafana ? 1 : 0

  length           = 16
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#$%&*()-_=+[]:?"
}
