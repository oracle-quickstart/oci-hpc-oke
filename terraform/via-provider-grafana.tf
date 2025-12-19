# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl


resource "kubernetes_config_map_v1" "grafana_common_dashboards" {
  for_each   = alltrue([var.create_cluster, var.install_node_problem_detector_kube_prometheus_stack, local.deploy_from_local || local.deploy_from_orm]) ? local.grafana_common_dashboards : {}
  depends_on = [helm_release.prometheus]
  metadata {
    name      = format("dashboard-%s", trimsuffix(each.key, ".json"))
    namespace = var.monitoring_namespace
    annotations = {
      grafana_dashboard_folder = "Kubernetes"
    }
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = { (each.key) = each.value }
}

resource "kubernetes_config_map_v1" "grafana_nvidia_dashboards" {
  for_each = (
    (
      (can(regex("GPU", coalesce(var.worker_rdma_shape, ""))) && var.worker_rdma_shape != "BM.GPU.MI300X.8") ||
      (can(regex("GPU", coalesce(var.worker_gpu_shape, ""))) && var.worker_gpu_shape != "BM.GPU.MI300X.8")
    ) && alltrue([var.create_cluster, var.install_node_problem_detector_kube_prometheus_stack, local.deploy_from_local || local.deploy_from_orm]) ? local.grafana_nvidia_dashboards : {}
  )

  depends_on = [helm_release.prometheus]

  metadata {
    name      = format("dashboard-%s", trimsuffix(each.key, ".json"))
    namespace = var.monitoring_namespace
    annotations = {
      grafana_dashboard_folder = "GPU Nodes"
    }
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    (each.key) = each.value
  }
}

resource "kubernetes_config_map_v1" "grafana_amd_dashboards" {
  for_each = (
    (
      var.worker_rdma_shape == "BM.GPU.MI300X.8" ||
      var.worker_gpu_shape == "BM.GPU.MI300X.8"
    ) && alltrue([var.create_cluster, var.install_node_problem_detector_kube_prometheus_stack, local.deploy_from_local || local.deploy_from_orm]) ? local.grafana_amd_dashboards : {}
  )

  depends_on = [helm_release.prometheus]

  metadata {
    name      = format("dashboard-%s", trimsuffix(each.key, ".json"))
    namespace = var.monitoring_namespace
    annotations = {
      grafana_dashboard_folder = "GPU Nodes"
    }
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    (each.key) = each.value
  }
}

resource "kubernetes_config_map_v1" "grafana_alerts" {
  for_each   = alltrue([var.create_cluster, var.install_node_problem_detector_kube_prometheus_stack, local.deploy_from_local || local.deploy_from_orm]) ? local.grafana_alerts : {}
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