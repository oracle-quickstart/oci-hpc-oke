# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  kueue_shape        = var.worker_gmc_enabled ? var.worker_gmc_shape : var.worker_rdma_shape
  kueue_is_amd       = contains(local.amd_gpu_plugin_shapes, local.kueue_shape)
  kueue_gpu_resource = local.kueue_is_amd ? "amd.com/gpu" : "nvidia.com/gpu"
  kueue_flavor_name  = "${lower(replace(local.kueue_shape, ".", "-"))}-rdma-topology-aware"
  # TAS only uses nodes with all topology labels, which the RDMA labeler sets.
  kueue_queues_enabled = alltrue([
    var.worker_gmc_enabled || (var.worker_rdma_enabled && can(regex("GPU", coalesce(var.worker_rdma_shape, "")))),
    var.install_oci_hpc_oke_utils,
    var.install_rdma_labeler,
  ])
}

resource "helm_release" "kueue" {
  count = alltrue([var.install_kueue, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  # cert-manager must finish installing before the Kueue chart registers its
  # cluster-wide Deployment webhook, otherwise cert-manager's own Deployments
  # are rejected with "no endpoints available for service
  # kueue-webhook-service". The probe below can plan zero instances and
  # ordering does not carry through a zero-instance resource, so cert-manager
  # is listed directly.
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
  # Manager config with the DRA deviceClassMappings.
  values = [file("${path.module}/files/kueue/values.yaml")]
}

resource "kubectl_manifest" "kueue_webhook_probe" {
  count = alltrue([var.install_kueue, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  # v1beta1 to v1beta2 updates the object in place instead of deleting and recreating it.
  upgrade_api_version = true

  # Apply a harmless Kueue resource first so kubectl provider retries absorb
  # webhook CA propagation races before the real Kueue objects are created.
  yaml_body  = file("${path.module}/files/kueue/webhook-readiness-probe.yaml")
  depends_on = [helm_release.kueue]
}

# Kueue Topology for RDMA-aware scheduling. The topology, flavor, and queues
# are only created for a GPU RDMA or GMC pool with the RDMA labeler, because
# the flavor binds to the oci-rdma topology whose labels the labeler sets.
resource "kubectl_manifest" "kueue_topology" {
  count               = alltrue([var.install_kueue, local.kueue_queues_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  upgrade_api_version = true

  yaml_body  = file("${path.module}/files/kueue/topology.yaml")
  depends_on = [helm_release.kueue, kubectl_manifest.kueue_webhook_probe]
}

# ResourceFlavor matching the active GPU worker pool shape
resource "kubectl_manifest" "kueue_resource_flavor" {
  count               = alltrue([var.install_kueue, local.kueue_queues_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  upgrade_api_version = true

  yaml_body = templatefile("${path.module}/files/kueue/resource-flavor.yaml.tpl", {
    flavor_name   = local.kueue_flavor_name
    shape         = local.kueue_shape
    gpu_label_key = local.kueue_gpu_resource
  })

  depends_on = [helm_release.kueue, kubectl_manifest.kueue_topology]
}

# ClusterQueue with resource quotas
resource "kubectl_manifest" "kueue_cluster_queue" {
  count               = alltrue([var.install_kueue, local.kueue_queues_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  upgrade_api_version = true

  yaml_body = templatefile("${path.module}/files/kueue/cluster-queue.yaml.tpl", {
    flavor_name  = local.kueue_flavor_name
    gpu_resource = local.kueue_gpu_resource
    rdma_vf      = local.deploy_nvidia_network_operator_manifests
  })

  depends_on = [helm_release.kueue, kubectl_manifest.kueue_resource_flavor]
}

# The LocalQueue namespace, when it is not default. apply_only keeps it on
# destroy, because it can hold other workloads.
resource "kubectl_manifest" "kueue_local_queue_namespace" {
  count = alltrue([var.install_kueue, local.kueue_queues_enabled, var.kueue_local_queue_default_namespace != "default", local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = var.kueue_local_queue_default_namespace }
  })
  apply_only = true
  depends_on = [helm_release.kueue]
}

# LocalQueue in the user-specified namespace
resource "kubectl_manifest" "kueue_local_queue" {
  count               = alltrue([var.install_kueue, local.kueue_queues_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  upgrade_api_version = true

  yaml_body = templatefile("${path.module}/files/kueue/local-queue.yaml.tpl", {
    flavor_name = local.kueue_flavor_name
    namespace   = var.kueue_local_queue_default_namespace
  })

  depends_on = [helm_release.kueue, kubectl_manifest.kueue_cluster_queue, kubectl_manifest.kueue_local_queue_namespace]
}
