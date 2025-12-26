# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "nvidia_dcgm_exporter" {
  count             = alltrue([var.create_cluster,var.install_monitoring, var.install_nvidia_dcgm_exporter, var.install_node_problem_detector_kube_prometheus_stack, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on        = [helm_release.prometheus]
  namespace         = var.monitoring_namespace
  name              = "dcgm-exporter"
  chart             = "${path.module}/files/nvidia-dcgm-exporter"
  version           = var.dcgm_exporter_chart_version
  values            = ["${file("${path.module}/files/nvidia-dcgm-exporter/oke-values.yaml")}"]
  create_namespace  = false
  recreate_pods     = true
  force_update      = true
  dependency_update = true
  wait              = false
  max_history       = 1
}
