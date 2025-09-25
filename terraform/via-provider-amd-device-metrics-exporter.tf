# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "amd_device_metrics_exporter" {
  count             = alltrue([var.install_monitoring, var.install_amd_device_metrics_exporter && (var.worker_rdma_shape == "BM.GPU.MI300X.8" || var.worker_gpu_shape == "BM.GPU.MI300X.8"), var.install_node_problem_detector_kube_prometheus_stack, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on        = [helm_release.prometheus]
  namespace         = var.monitoring_namespace
  name              = "amd-device-metrics-exporter"
  chart             = "device-metrics-exporter-charts"
  repository        = "https://rocm.github.io/device-metrics-exporter"
  version           = var.amd_device_metrics_exporter_chart_version
  values            = ["${file("./files/amd-device-metrics-exporter/values.yaml")}"]
  create_namespace  = false
  recreate_pods     = true
  force_update      = true
  dependency_update = true
  wait              = false
  max_history       = 1
}
