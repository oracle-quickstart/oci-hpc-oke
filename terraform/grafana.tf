
# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  grafana_jsonnet_dir       = "${path.module}/files/grafana/jsonnet"
  grafana_jsonnet_cache_dir = abspath("${path.root}/.terraform/grafana-jsonnet")
  grafana_jsonnet_build_dir = "${local.grafana_jsonnet_cache_dir}/rendered"

  grafana_legacy_common_dashboard_dir = "${path.module}/files/grafana/legacy-dashboard-backups/common"
  grafana_legacy_gpu_dashboard_dir    = "${path.module}/files/grafana/legacy-dashboard-backups/gpu"
  grafana_legacy_oci_dashboard_dir    = "${path.module}/files/grafana/legacy-dashboard-backups/oci"

  grafana_legacy_common_dashboard_files = fileset(local.grafana_legacy_common_dashboard_dir, "*.json")
  grafana_legacy_gpu_dashboard_files    = fileset(local.grafana_legacy_gpu_dashboard_dir, "*.json")
  grafana_legacy_oci_dashboard_files    = fileset(local.grafana_legacy_oci_dashboard_dir, "*.json")

  grafana_legacy_common_dashboard_files_path = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? [for f in local.grafana_legacy_common_dashboard_files : "${local.grafana_legacy_common_dashboard_dir}/${f}"] : []
  grafana_legacy_gpu_dashboard_files_path    = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? [for f in local.grafana_legacy_gpu_dashboard_files : "${local.grafana_legacy_gpu_dashboard_dir}/${f}"] : []
  grafana_legacy_oci_dashboard_files_path    = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards && var.setup_oci_metrics_exporter) ? [for f in local.grafana_legacy_oci_dashboard_files : "${local.grafana_legacy_oci_dashboard_dir}/${f}"] : []

  grafana_rendered_dashboards = try(jsondecode(data.external.grafana_dashboards[0].result.dashboards), {
    common = {}
    gpu    = {}
    oci    = {}
  })
  grafana_jsonnet_source_hash = try(data.external.grafana_dashboards[0].result.source_hash, "disabled")

  grafana_common_dashboards     = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? try(local.grafana_rendered_dashboards.common, {}) : {}
  grafana_gpu_dashboard_sources = try(local.grafana_rendered_dashboards.gpu, {})
  grafana_oci_dashboard_sources = try(local.grafana_rendered_dashboards.oci, {})
  grafana_gpu_health_dashboard  = try(jsondecode(local.grafana_gpu_dashboard_sources["gpu-health-status.json"]), { panels = [] })
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
  grafana_oci_dashboards = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards && var.setup_oci_metrics_exporter) ? local.grafana_oci_dashboard_sources : {}

  grafana_legacy_common_dashboards = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? {
    for f in local.grafana_legacy_common_dashboard_files :
    f => file("${local.grafana_legacy_common_dashboard_dir}/${f}")
  } : {}
  grafana_legacy_gpu_dashboards = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? {
    for f in local.grafana_legacy_gpu_dashboard_files :
    f => file("${local.grafana_legacy_gpu_dashboard_dir}/${f}")
  } : {}
  grafana_legacy_oci_dashboards = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards && var.setup_oci_metrics_exporter) ? {
    for f in local.grafana_legacy_oci_dashboard_files :
    f => file("${local.grafana_legacy_oci_dashboard_dir}/${f}")
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

data "external" "grafana_dashboards" {
  count = var.install_monitoring && var.install_grafana ? 1 : 0

  program = ["python3", "${local.grafana_jsonnet_dir}/render_dashboards.py", "--external"]
  query = {
    cache_dir  = local.grafana_jsonnet_cache_dir
    output_dir = local.grafana_jsonnet_build_dir
  }
}

resource "terraform_data" "validate_grafana_dashboard_render" {
  count = var.install_monitoring && var.install_grafana && var.install_grafana_dashboards ? 1 : 0

  input = local.grafana_jsonnet_source_hash

  lifecycle {
    precondition {
      condition     = length(setsubtract(local.grafana_legacy_common_dashboard_files, toset(keys(try(local.grafana_rendered_dashboards.common, {}))))) == 0
      error_message = "A legacy common dashboard backup has no rendered Jsonnet replacement."
    }
    precondition {
      condition     = length(setsubtract(local.grafana_legacy_gpu_dashboard_files, toset(keys(try(local.grafana_rendered_dashboards.gpu, {}))))) == 0
      error_message = "A legacy GPU dashboard backup has no rendered Jsonnet replacement."
    }
    precondition {
      condition     = length(setsubtract(local.grafana_legacy_oci_dashboard_files, toset(keys(try(local.grafana_rendered_dashboards.oci, {}))))) == 0
      error_message = "A legacy OCI dashboard backup has no rendered Jsonnet replacement."
    }
  }
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
