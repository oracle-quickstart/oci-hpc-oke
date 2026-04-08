# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "kubectl_manifest" "nvidia_dcgm_exporter_service_monitor" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.deploy_nvidia_gpu_operator, lookup(var.nvidia_gpu_operator_configuration, "dcgmExporter.enabled", "true") == "true", (var.worker_rdma_enabled && can(regex("GPU", coalesce(var.worker_rdma_shape, ""))) && !contains(["BM.GPU.MI300X.8", "BM.GPU.MI355X-v1.8", "BM.GPU.MI355X.8"], var.worker_rdma_shape)) || (var.worker_gpu_enabled && can(regex("GPU", coalesce(var.worker_gpu_shape, ""))) && !contains(["BM.GPU.MI300X.8", "BM.GPU.MI355X-v1.8", "BM.GPU.MI355X.8"], var.worker_gpu_shape)), local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body = file("${path.module}/files/nvidia-dcgm-exporter-service-monitor/service-monitor.yaml")

  depends_on = [
    module.oke,
    helm_release.prometheus,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke
  ]
}
