# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  kueue_amd_shapes   = ["BM.GPU.MI300X.8", "BM.GPU.MI355X-v1.8", "BM.GPU.MI355X.8"]
  kueue_is_amd       = contains(local.kueue_amd_shapes, var.worker_rdma_shape)
  kueue_gpu_resource = local.kueue_is_amd ? "amd.com/gpu" : "nvidia.com/gpu"
  kueue_flavor_name  = "${lower(replace(var.worker_rdma_shape, ".", "-"))}-rdma-topology-aware"
}

resource "helm_release" "kueue" {
  count = alltrue([var.install_kueue, var.worker_rdma_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [
    module.oke,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke
  ]
  namespace        = "kueue-system"
  name             = "kueue"
  chart            = "oci://registry.k8s.io/kueue/charts/kueue"
  version          = var.kueue_chart_version
  create_namespace = true
  wait             = true
  timeout          = 300
  max_history      = 1
}

# Kueue Topology for RDMA-aware scheduling
resource "kubectl_manifest" "kueue_topology" {
  count = alltrue([var.install_kueue, var.worker_rdma_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body  = file("${path.module}/files/kueue/topology.yaml")
  depends_on = [helm_release.kueue]
}

# ResourceFlavor matching the RDMA worker pool shape
resource "kubectl_manifest" "kueue_resource_flavor" {
  count = alltrue([var.install_kueue, var.worker_rdma_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body = templatefile("${path.module}/files/kueue/resource-flavor.yaml.tpl", {
    flavor_name   = local.kueue_flavor_name
    shape         = var.worker_rdma_shape
    gpu_label_key = local.kueue_gpu_resource
  })

  depends_on = [helm_release.kueue, kubectl_manifest.kueue_topology]
}

# ClusterQueue with resource quotas
resource "kubectl_manifest" "kueue_cluster_queue" {
  count = alltrue([var.install_kueue, var.worker_rdma_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body = templatefile("${path.module}/files/kueue/cluster-queue.yaml.tpl", {
    flavor_name  = local.kueue_flavor_name
    gpu_resource = local.kueue_gpu_resource
  })

  depends_on = [helm_release.kueue, kubectl_manifest.kueue_resource_flavor]
}

# LocalQueue in the user-specified namespace
resource "kubectl_manifest" "kueue_local_queue" {
  count = alltrue([var.install_kueue, var.worker_rdma_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body = templatefile("${path.module}/files/kueue/local-queue.yaml.tpl", {
    flavor_name = local.kueue_flavor_name
    namespace   = var.kueue_local_queue_default_namespace
  })

  depends_on = [helm_release.kueue, kubectl_manifest.kueue_cluster_queue]
}
