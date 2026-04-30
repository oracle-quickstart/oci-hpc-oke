# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "oci_metrics_exporter" {
  count      = alltrue([var.install_monitoring, var.setup_oci_metrics_exporter, var.install_node_problem_detector_kube_prometheus_stack, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [helm_release.prometheus]
  namespace  = var.monitoring_namespace
  name       = "oci-metrics-exporter"
  chart      = "${path.module}/files/oci-metrics-exporter"
  version    = var.oci_metrics_exporter_chart_version
  set = [
    {
      name  = "telegraf.streamOcid"
      value = try(oci_streaming_stream.oci_metrics_exporter[0].id, "")
    }
  ]
  create_namespace  = false
  recreate_pods     = true
  force_update      = true
  dependency_update = true
  wait              = false
  max_history       = 1
}
