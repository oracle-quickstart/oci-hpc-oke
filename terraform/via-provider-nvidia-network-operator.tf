# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  deploy_nvidia_network_operator_manifests = alltrue([
    var.deploy_nvidia_network_operator,
    lookup(var.nvidia_network_operator_configuration, "sriovNetworkOperator.enabled", "false") == "true",
  ])

  nvidia_network_operator_namespace = "nvidia-network-operator"

  # Must match the shapes covered by files/nvidia-network-operator/sriov-network-node-policy.yaml.
  nvidia_network_operator_sriov_shapes = [
    "BM.GPU4.8",
    "BM.GPU.A100-v2.8",
    "BM.GPU.B4.8",
    "BM.GPU.B200.8",
    "BM.GPU.H100.8",
    "BM.GPU.H200.8",
    "BM.GPU.MI300X.8",
    "BM.GPU.MI355X-v1.8",
    "BM.GPU.B300.8",
  ]

  nvidia_network_operator_ip_pool_manifest = yamlencode({
    apiVersion = "nv-ipam.nvidia.com/v1alpha1"
    kind       = "IPPool"
    metadata = {
      name      = "sriov-pool"
      namespace = local.nvidia_network_operator_namespace
    }
    spec = {
      subnet           = var.nvidia_network_operator_ipam_subnet
      perNodeBlockSize = var.nvidia_network_operator_ipam_per_node_block_size
      gateway          = var.nvidia_network_operator_ipam_gateway
    }
  })

  nvidia_network_operator_sriov_pool_config_manifest = yamlencode({
    apiVersion = "sriovnetwork.openshift.io/v1"
    kind       = "SriovNetworkPoolConfig"
    metadata = {
      name      = "rdma-vf"
      namespace = local.nvidia_network_operator_namespace
    }
    spec = {
      maxUnavailable = var.nvidia_network_operator_sriov_max_unavailable
      nodeSelector = {
        matchExpressions = [
          {
            key      = "node.kubernetes.io/instance-type"
            operator = "In"
            values   = local.nvidia_network_operator_sriov_shapes
          }
        ]
      }
    }
  })
}

# The OKE add-on resource reports created before the Network Operator has
# finished reconciling its namespace and CRDs (IPPool, SriovNetworkNodePolicy,
# SriovNetworkPoolConfig, SriovNetwork). Applying the CRs immediately races that
# registration and fails with "no matches for kind". The operator-host path
# polls for the CRDs over SSH; the local/ORM path has no shell, so it settles for
# a fixed delay here before the kubectl_manifest applies below.
resource "time_sleep" "wait_for_nvidia_network_operator_crds" {
  count = alltrue([local.deploy_nvidia_network_operator_manifests, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  create_duration = "120s"

  depends_on = [
    module.oke,
    oci_containerengine_addon.nvidia_network_operator,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke,
  ]
}

resource "kubectl_manifest" "nvidia_network_operator_ip_pool" {
  count = alltrue([local.deploy_nvidia_network_operator_manifests, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body         = local.nvidia_network_operator_ip_pool_manifest
  server_side_apply = true
  wait_for_rollout  = false

  depends_on = [
    module.oke,
    oci_containerengine_addon.nvidia_network_operator,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke,
    time_sleep.wait_for_nvidia_network_operator_crds,
  ]
}

data "kubectl_file_documents" "nvidia_network_operator_sriov_policies" {
  content = file("${path.module}/files/nvidia-network-operator/sriov-network-node-policy.yaml")
}

resource "kubectl_manifest" "nvidia_network_operator_sriov_policies" {
  for_each = alltrue([local.deploy_nvidia_network_operator_manifests, local.deploy_from_local || local.deploy_from_orm]) ? data.kubectl_file_documents.nvidia_network_operator_sriov_policies.manifests : {}

  yaml_body         = each.value
  server_side_apply = true
  wait_for_rollout  = false

  depends_on = [
    module.oke,
    oci_containerengine_addon.nvidia_network_operator,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke,
    time_sleep.wait_for_nvidia_network_operator_crds,
  ]
}

resource "kubectl_manifest" "nvidia_network_operator_sriov_pool_config" {
  count = alltrue([local.deploy_nvidia_network_operator_manifests, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body         = local.nvidia_network_operator_sriov_pool_config_manifest
  server_side_apply = true
  wait_for_rollout  = false

  depends_on = [
    module.oke,
    oci_containerengine_addon.nvidia_network_operator,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke,
    time_sleep.wait_for_nvidia_network_operator_crds,
  ]
}

resource "kubectl_manifest" "nvidia_network_operator_sriov_network" {
  count = alltrue([local.deploy_nvidia_network_operator_manifests, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body         = file("${path.module}/files/nvidia-network-operator/sriov-network.yaml")
  server_side_apply = true
  wait_for_rollout  = false

  depends_on = [
    module.oke,
    oci_containerengine_addon.nvidia_network_operator,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke,
    time_sleep.wait_for_nvidia_network_operator_crds,
    kubectl_manifest.nvidia_network_operator_ip_pool,
  ]
}
