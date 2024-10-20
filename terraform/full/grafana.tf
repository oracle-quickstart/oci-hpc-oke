# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  grafana_name    = "grafana"
  grafana_version = "10.2"
  grafana_labels = merge(
    local.labels_gpu_stack, local.monitoring_labels, {
      "app.kubernetes.io/name"              = local.grafana_name
      "service.istio.io/canonical-name"     = local.grafana_name
      "app.kubernetes.io/version"           = local.grafana_version
      "service.istio.io/canonical-revision" = local.grafana_version
  })

  grafana_dashboard_path  = "${path.module}/files/dashboards"
  grafana_dashboard_files = fileset(local.grafana_dashboard_path, "*.json")
  grafana_dashboards = (var.install_monitoring && var.install_grafana && var.install_grafana_dashboards) ? {
    for f in local.grafana_dashboard_files :
    f => filebase64(join("/", [local.grafana_dashboard_path, f]))
  } : {}

  grafana_helm_values = {
    extraLabels = local.grafana_labels
    grafana = {
      enabled = var.install_grafana
      "grafana.ini" = {
        analytics = {
          enabled                  = false
          reporting_enabled        = false
          check_for_updates        = false
          check_for_plugin_updates = false
          feedback_links_enabled   = false
        }
        server = {
          enable_gzip = true
        }
        auth = {
          login_maximum_lifetime_duration = "120d"
          token_rotation_interval_minutes = 600
          basic                           = { enabled = true }
        }
        users = {
          default_theme     = "light"
          viewers_can_edit  = true
          editors_can_admin = true
        }
      }
      replicas = 1
      podDisruptionBudget = {
        apiVersion     = "policy/v1"
        minAvailable   = 1
        maxUnavailable = 0
      }
      deploymentStrategy = {
        type = "RollingUpdate"
        rollingUpdate = {
          maxSurge       = "100%"
          maxUnavailable = 0
        }
      }
      podPortName   = "http-web"
      podLabels     = local.grafana_labels
      adminUser     = "oke" # TODO
      adminPassword = "oke" # TODO
      inMemory      = { enabled = true }
      resources = { # TODO dynamic/configurable
        requests = {
          cpu    = "100m"
          memory = "4Gi"
        }
        limits = {
          cpu    = "8"
          memory = "8Gi"
        }
      }
      service = {
        enabled     = true
        type        = "ClusterIP"
        port        = 80
        targetPort  = 3000
        labels      = local.grafana_labels
        portName    = "http-web"
        appProtocol = "tcp"
      }
      defaultDashboardsEnabled = false
      persistence = {
        enabled          = true
        type             = "sts"
        storageClassName = "oci-bv"
        accessModes      = ["ReadWriteOnce"]
        size             = "50Gi"
        finalizers       = ["kubernetes.io/pvc-protection"]
      }
    }
    sidecar = {
      dashboards = {
        enabled                   = true
        enableNewTablePanelSyntax = true
        label                     = "grafana_dashboard"
        labelValue                = "1"
        searchNamespace           = "ALL"
        foldersFromFilesStructure = true
        updateIntervalSeconds     = 30
        provider                  = { allowUiUpdates = true }
      }
    }
  }
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
    labels = merge(local.monitoring_labels, {
      grafana_dashboard = "1"
      release           = "prometheus"
    })
  }
  binary_data = { (each.key) = each.value }
}

resource "random_password" "grafana_admin_password" {
  length           = 12
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}