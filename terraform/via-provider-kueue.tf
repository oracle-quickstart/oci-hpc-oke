# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  kueue_amd_shapes   = ["BM.GPU.MI300X.8", "BM.GPU.MI355X-v1.8", "BM.GPU.MI355X.8"]
  kueue_shape        = var.worker_gmc_enabled ? var.worker_gmc_shape : var.worker_rdma_shape
  kueue_is_amd       = contains(local.kueue_amd_shapes, local.kueue_shape)
  kueue_gpu_resource = local.kueue_is_amd ? "amd.com/gpu" : "nvidia.com/gpu"
  kueue_flavor_name  = "${lower(replace(local.kueue_shape, ".", "-"))}-rdma-topology-aware"
}

resource "helm_release" "kueue" {
  count = alltrue([var.install_kueue, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [
    module.oke,
    helm_release.cert_manager,
    kubectl_manifest.cert_manager_webhook_probe,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke
  ]
  namespace        = "kueue-system"
  name             = "kueue"
  chart            = "oci://registry.k8s.io/kueue/charts/kueue"
  version          = var.kueue_chart_version
  create_namespace = true
  # wait = false so "helm uninstall" on destroy does not hang on the Kueue CRD
  # cascade (resource-in-use finalizers). ORM/local equivalent of the operator
  # drain in kueue-predestroy-drain.tf; readiness is gated by the webhook probe.
  wait        = false
  timeout     = 300
  max_history = 1
}

resource "kubectl_manifest" "kueue_webhook_probe" {
  count = alltrue([var.install_kueue, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  # Apply a harmless Kueue resource first so kubectl provider retries absorb
  # webhook CA propagation races before the real Kueue objects are created.
  yaml_body  = file("${path.module}/files/kueue/webhook-readiness-probe.yaml")
  depends_on = [helm_release.kueue]
}

# Kueue Topology for RDMA-aware scheduling. The topology, flavor, and queues
# are only created when an RDMA-capable pool exists: the flavor binds to the
# oci-rdma topology whose node labels only RDMA-networked nodes carry, and
# gating also prevents creating a flavor from the worker_rdma_shape default
# for a pool that does not exist.
resource "kubectl_manifest" "kueue_topology" {
  count = alltrue([var.install_kueue, var.worker_rdma_enabled || var.worker_gmc_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body  = file("${path.module}/files/kueue/topology.yaml")
  depends_on = [helm_release.kueue, kubectl_manifest.kueue_webhook_probe]
}

# ResourceFlavor matching the active GPU worker pool shape
resource "kubectl_manifest" "kueue_resource_flavor" {
  count = alltrue([var.install_kueue, var.worker_rdma_enabled || var.worker_gmc_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body = templatefile("${path.module}/files/kueue/resource-flavor.yaml.tpl", {
    flavor_name   = local.kueue_flavor_name
    shape         = local.kueue_shape
    gpu_label_key = local.kueue_gpu_resource
  })

  depends_on = [helm_release.kueue, kubectl_manifest.kueue_topology]
}

# ClusterQueue with resource quotas
resource "kubectl_manifest" "kueue_cluster_queue" {
  count = alltrue([var.install_kueue, var.worker_rdma_enabled || var.worker_gmc_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body = templatefile("${path.module}/files/kueue/cluster-queue.yaml.tpl", {
    flavor_name  = local.kueue_flavor_name
    gpu_resource = local.kueue_gpu_resource
  })

  depends_on = [helm_release.kueue, kubectl_manifest.kueue_resource_flavor]
}

# LocalQueue in the user-specified namespace
resource "kubectl_manifest" "kueue_local_queue" {
  count = alltrue([var.install_kueue, var.worker_rdma_enabled || var.worker_gmc_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body = templatefile("${path.module}/files/kueue/local-queue.yaml.tpl", {
    flavor_name = local.kueue_flavor_name
    namespace   = var.kueue_local_queue_default_namespace
  })

  depends_on = [helm_release.kueue, kubectl_manifest.kueue_cluster_queue]
}
