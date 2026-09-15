# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "kubectl_manifest" "amd_device_metrics_exporter_service_monitor" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, local.deploy_amd_gpu_operator_addon, local.amd_device_metrics_exporter_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body = local.amd_device_metrics_exporter_service_monitor_manifest

  depends_on = [
    module.oke,
    helm_release.prometheus,
    oci_containerengine_addon.amd_gpu_operator,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke,
  ]
}
