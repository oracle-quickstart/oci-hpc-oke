# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "nvidia_dra_driver" {
  count = alltrue([var.install_nvidia_dra_driver, var.worker_gmc_enabled, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [
    module.oke,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke
  ]

  namespace        = "dra-driver-nvidia-gpu"
  name             = "dra-driver-nvidia-gpu"
  chart            = "oci://registry.k8s.io/dra-driver-nvidia/charts/dra-driver-nvidia-gpu"
  version          = var.nvidia_dra_driver_chart_version
  create_namespace = true
  wait             = true
  timeout          = 300
  max_history      = 1

  values = [yamlencode({
    nvidiaDriverRoot            = "/"
    gpuResourcesEnabledOverride = false
    resources = {
      gpus = {
        enabled = false
      }
      computeDomains = {
        enabled = true
      }
    }
    kubeletPlugin = {
      tolerations = [
        {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    }
  })]
}
