# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "amd_device_metrics_exporter" {
  count             = var.install_amd_device_metrics_exporter && var.install_node_problem_detector_kube_prometheus_stack ? 1 : 0
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
