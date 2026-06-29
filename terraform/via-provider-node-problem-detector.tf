# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  npd_has_amd_gpu = (
    (var.worker_rdma_enabled && contains(local.amd_gpu_plugin_shapes, var.worker_rdma_shape)) ||
    (var.worker_gpu_enabled && contains(local.amd_gpu_plugin_shapes, var.worker_gpu_shape))
  )
  npd_has_nvidia_gpu = (
    (var.worker_rdma_enabled && can(regex("GPU", coalesce(var.worker_rdma_shape, ""))) && !contains(local.amd_gpu_plugin_shapes, var.worker_rdma_shape)) ||
    (var.worker_gpu_enabled && can(regex("GPU", coalesce(var.worker_gpu_shape, ""))) && !contains(local.amd_gpu_plugin_shapes, var.worker_gpu_shape))
  )
}

resource "helm_release" "node_problem_detector_amd" {
  count      = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, local.npd_has_amd_gpu, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [helm_release.prometheus]
  namespace  = var.monitoring_namespace
  name       = "gpu-rdma-node-problem-detector-amd"
  chart      = "node-problem-detector"
  repository = "oci://ghcr.io/deliveryhero/helm-charts"
  version    = var.node_problem_detector_chart_version
  values = [
    file("${path.module}/files/node-problem-detector/values.yaml"),
    file("${path.module}/files/node-problem-detector/values-amd.yaml"),
  ]
  create_namespace  = true
  recreate_pods     = true
  force_update      = true
  dependency_update = true
  wait              = false
  max_history       = 1
}

resource "helm_release" "node_problem_detector_nvidia" {
  count      = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, local.npd_has_nvidia_gpu, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [helm_release.prometheus]
  namespace  = var.monitoring_namespace
  name       = "gpu-rdma-node-problem-detector-nvidia"
  chart      = "node-problem-detector"
  repository = "oci://ghcr.io/deliveryhero/helm-charts"
  version    = var.node_problem_detector_chart_version
  values = [
    file("${path.module}/files/node-problem-detector/values.yaml"),
    file("${path.module}/files/node-problem-detector/values-nvidia.yaml"),
  ]
  create_namespace  = true
  recreate_pods     = true
  force_update      = true
  dependency_update = true
  wait              = false
  max_history       = 1
}
