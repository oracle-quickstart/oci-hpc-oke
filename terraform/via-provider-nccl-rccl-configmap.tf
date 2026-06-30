# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  # Recommended NCCL/RCCL parameters per shape, transcribed verbatim from
  # docs/recommended-nccl-rccl-parameters-by-shape.md. NCCL_IB_HCA holds the
  # standard (non-VF) value: shapes the doc writes as "NCCL_IB_HCA==..." keep a
  # single leading "=" (NCCL exact-name-match prefix); the two GB200 shapes the
  # doc writes with a single "=" carry no prefix. When SR-IOV virtual functions
  # are in use the value is overridden to "mlx5" below.
  nccl_rccl_parameters = {
    "BM.GPU4.8" = {
      NCCL_DEBUG                 = "WARN"
      NCCL_IB_SPLIT_DATA_ON_QPS  = "0"
      NCCL_IB_QPS_PER_CONNECTION = "4"
      NCCL_IB_GID_INDEX          = "3"
      NCCL_IB_HCA                = "=mlx5_0,mlx5_2,mlx5_6,mlx5_8,mlx5_10,mlx5_12,mlx5_14,mlx5_16,mlx5_1,mlx5_3,mlx5_7,mlx5_9,mlx5_11,mlx5_13,mlx5_15,mlx5_17"
      NCCL_IB_TC                 = "41"
      NCCL_IB_SL                 = "0"
      NCCL_IB_TIMEOUT            = "22"
    }
    "BM.GPU.A100-v2.8" = {
      NCCL_DEBUG                 = "WARN"
      NCCL_IB_SPLIT_DATA_ON_QPS  = "0"
      NCCL_IB_QPS_PER_CONNECTION = "4"
      NCCL_IB_GID_INDEX          = "3"
      NCCL_IB_HCA                = "=mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_14,mlx5_15,mlx5_16,mlx5_17,mlx5_9,mlx5_10,mlx5_11,mlx5_12"
      NCCL_IB_TC                 = "41"
      NCCL_IB_SL                 = "0"
      NCCL_IB_TIMEOUT            = "22"
    }
    "BM.GPU.H100.8" = {
      NCCL_DEBUG                = "WARN"
      NCCL_CUMEM_ENABLE         = "0"
      NCCL_IB_SPLIT_DATA_ON_QPS = "0"
      NCCL_IB_GID_INDEX         = "3"
      NCCL_IB_HCA               = "=mlx5_0,mlx5_1,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_9,mlx5_10,mlx5_12,mlx5_13,mlx5_14,mlx5_15,mlx5_16,mlx5_17"
      NCCL_IB_TC                = "41"
      NCCL_IB_SL                = "0"
      NCCL_IB_TIMEOUT           = "22"
      NCCL_SOCKET_IFNAME        = "eth0"
      NCCL_IGNORE_CPU_AFFINITY  = "1"
    }
    "BM.GPU.H200.8" = {
      NCCL_DEBUG                = "WARN"
      NCCL_CUMEM_ENABLE         = "0"
      NCCL_IB_SPLIT_DATA_ON_QPS = "0"
      NCCL_IB_GID_INDEX         = "3"
      NCCL_IB_HCA               = "=mlx5_0,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_9,mlx5_10,mlx5_11"
      NCCL_IB_TC                = "41"
      NCCL_IB_SL                = "0"
      NCCL_IB_TIMEOUT           = "22"
      NCCL_SOCKET_IFNAME        = "eth0"
      NCCL_IGNORE_CPU_AFFINITY  = "1"
    }
    "BM.GPU.B4.8" = {
      NCCL_DEBUG                 = "WARN"
      NCCL_IB_SPLIT_DATA_ON_QPS  = "0"
      NCCL_IB_QPS_PER_CONNECTION = "4"
      NCCL_IB_GID_INDEX          = "3"
      NCCL_IB_HCA                = "=mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_14,mlx5_15,mlx5_16,mlx5_17,mlx5_9,mlx5_10,mlx5_11,mlx5_12"
      NCCL_IB_TC                 = "41"
      NCCL_IB_SL                 = "0"
      NCCL_IB_TIMEOUT            = "22"
    }
    "BM.GPU.B200.8" = {
      NCCL_DEBUG                = "WARN"
      NCCL_CUMEM_ENABLE         = "0"
      NCCL_IB_SPLIT_DATA_ON_QPS = "0"
      NCCL_IB_GID_INDEX         = "3"
      NCCL_IB_HCA               = "=mlx5_0,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_9,mlx5_10,mlx5_11"
      NCCL_IB_TC                = "41"
      NCCL_IB_SL                = "0"
      NCCL_IB_TIMEOUT           = "22"
      NCCL_SOCKET_IFNAME        = "eth0"
      NCCL_IGNORE_CPU_AFFINITY  = "1"
    }
    "BM.GPU.B300.8" = {
      NCCL_DEBUG                = "WARN"
      NCCL_CUMEM_ENABLE         = "0"
      NCCL_IB_SPLIT_DATA_ON_QPS = "0"
      NCCL_IB_GID_INDEX         = "3"
      NCCL_IB_HCA               = "=mlx5_0,mlx5_1,mlx5_7,mlx5_8,mlx5_9,mlx5_10,mlx5_11,mlx5_12,mlx5_13,mlx5_14,mlx5_16,mlx5_17,mlx5_18,mlx5_19,mlx5_20,mlx5_21"
      NCCL_IB_TC                = "41"
      NCCL_IB_SL                = "0"
      NCCL_IB_TIMEOUT           = "22"
      NCCL_SOCKET_IFNAME        = "eth0"
      NCCL_IGNORE_CPU_AFFINITY  = "1"
    }
    "BM.GPU.GB200.4" = {
      NCCL_DEBUG         = "WARN"
      NCCL_MNNVL_ENABLE  = "1"
      NCCL_CUMEM_ENABLE  = "1"
      NCCL_NET_PLUGIN    = "sys"
      NCCL_IB_HCA        = "mlx5_0,mlx5_1,mlx5_3,mlx5_4"
      NCCL_NVLS_ENABLE   = "1"
      NCCL_SOCKET_IFNAME = "eth0"
    }
    "BM.GPU.GB200-v2.4" = {
      NCCL_DEBUG         = "WARN"
      NCCL_MNNVL_ENABLE  = "1"
      NCCL_CUMEM_ENABLE  = "1"
      NCCL_NET_PLUGIN    = "sys"
      NCCL_IB_HCA        = "mlx5_0,mlx5_1,mlx5_3,mlx5_4"
      NCCL_NVLS_ENABLE   = "1"
      NCCL_SOCKET_IFNAME = "eth0"
    }
    "BM.GPU.GB200-v3.4" = {
      NCCL_IB_TIMEOUT            = "22"
      NCCL_IB_SL                 = "0"
      NCCL_IB_TC                 = "41"
      NCCL_IB_GID_INDEX          = "3"
      NCCL_DEBUG                 = "WARN"
      NCCL_IB_QPS_PER_CONNECTION = "1"
      NCCL_IB_SPLIT_DATA_ON_QPS  = "0"
      NCCL_CUMEM_ENABLE          = "1"
      NCCL_IB_HCA                = "=mlx5_0,mlx5_1,mlx5_2,mlx5_3,mlx5_5,mlx5_6,mlx5_7,mlx5_8"
      NCCL_NET_GDR_C2C           = "1"
      NCCL_MNNVL_ENABLE          = "1"
      NCCL_NET_PLUGIN            = "none"
    }
    "BM.GPU.GB300.4" = {
      NCCL_DEBUG                 = "WARN"
      NCCL_MNNVL_ENABLE          = "1"
      NCCL_CUMEM_ENABLE          = "1"
      NCCL_NET_PLUGIN            = "none"
      NCCL_IB_HCA                = "=mlx5_0,mlx5_1,mlx5_2,mlx5_3,mlx5_5,mlx5_6,mlx5_7,mlx5_8"
      NCCL_NVLS_ENABLE           = "1"
      NCCL_SOCKET_IFNAME         = "eth0"
      NCCL_NET_GDR_C2C           = "1"
      NCCL_IB_GID_INDEX          = "3"
      NCCL_IB_TC                 = "41"
      NCCL_IB_SL                 = "0"
      NCCL_IB_TIMEOUT            = "22"
      NCCL_BUFFSIZE              = "16777216"
      NCCL_IB_QPS_PER_CONNECTION = "4"
      NCCL_IB_SPLIT_DATA_ON_QPS  = "0"
      NCCL_DMABUF_ENABLE         = "1"
    }
    "BM.GPU.MI300X.8" = {
      NCCL_CUMEM_ENABLE          = "0"
      NCCL_IB_TIMEOUT            = "22"
      NCCL_IB_SL                 = "0"
      NCCL_IB_TC                 = "41"
      NCCL_IB_GID_INDEX          = "3"
      NCCL_DEBUG                 = "WARN"
      NCCL_IB_QPS_PER_CONNECTION = "1"
      NCCL_IB_SPLIT_DATA_ON_QPS  = "0"
      NCCL_IB_HCA                = "=mlx5_0,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_7,mlx5_8,mlx5_9"
      NCCL_PXN_DISABLE           = "0"
      NCCL_NET_PLUGIN            = "none"
    }
    "BM.GPU.MI355X.8" = {
      NCCL_IB_HCA                                = "=ionic_0,ionic_2,ionic_3,ionic_4,ionic_5,ionic_7,ionic_8,ionic_9"
      NCCL_SOCKET_IFNAME                         = "ens9np0"
      NCCL_GDR_FLUSH_DISABLE                     = "1"
      RCCL_GDR_FLUSH_GPU_MEM_NO_RELAXED_ORDERING = "0"
      NCCL_IB_QPS_PER_CONNECTION                 = "2"
      NCCL_IB_GID_INDEX                          = "1"
      NCCL_BUFFSIZE                              = "16777216"
      NCCL_MAX_P2P_NCHANNELS                     = "32"
      NCCL_IB_TC                                 = "41"
      NCCL_IB_FIFO_TC                            = "185"
      NCCL_IGNORE_CPU_AFFINITY                   = "1"
      NCCL_PXN_DISABLE                           = "0"
      NCCL_DMABUF_ENABLE                         = "0"
      NCCL_DEBUG                                 = "WARN"
      NCCL_NET_OPTIONAL_RECV_COMPLETION          = "1"
      RCCL_IB_ABORT_ON_ERROR                     = "1"
      NCCL_IB_USE_INLINE                         = "1"
      NCCL_NET_PLUGIN                            = "librccl-anp.so"
      RCCL_LL128_FORCE_ENABLE                    = "1"
    }
    "BM.GPU.MI355X-v1.8" = {
      NCCL_MIN_NCHANNELS         = "32"
      NCCL_IB_QPS_PER_CONNECTION = "1"
      NCCL_SOCKET_IFNAME         = "eth0"
      NCCL_IB_SL                 = "0"
      NCCL_IB_GID_INDEX          = "3"
      NCCL_IB_TC                 = "41"
      NCCL_IGNORE_CPU_AFFINITY   = "1"
      NCCL_IB_HCA                = "=mlx5_0,mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7"
    }
  }

  nccl_rccl_configmap_shapes = distinct(concat(
    var.worker_rdma_enabled ? [var.worker_rdma_shape] : [],
    var.worker_gmc_enabled ? [var.worker_gmc_shape] : [],
  ))

  nccl_rccl_configmap_shape_params = {
    for shape in local.nccl_rccl_configmap_shapes :
    shape => lookup(local.nccl_rccl_parameters, shape, {})
    if length(lookup(local.nccl_rccl_parameters, shape, {})) > 0
  }

  nccl_rccl_configmaps = {
    for shape, params in local.nccl_rccl_configmap_shape_params :
    shape => {
      name = format(
        "oci-%s-parameters-%s",
        contains(local.amd_gpu_plugin_shapes, shape) ? "rccl" : "nccl",
        lower(replace(shape, ".", "-")),
      )
      namespace = "default"
      data = merge(
        params,
        alltrue([
          local.deploy_nvidia_network_operator_manifests,
          contains(local.nvidia_network_operator_sriov_shapes, shape),
        ]) ? { NCCL_IB_HCA = "mlx5" } : {},
      )
    }
  }

  deploy_nccl_rccl_param_configmap = alltrue([
    var.deploy_nccl_rccl_param_configmap,
    length(local.nccl_rccl_configmaps) > 0,
  ])

  nccl_rccl_configmap_manifests = {
    for shape, configmap in local.nccl_rccl_configmaps :
    shape => yamlencode({
      apiVersion = "v1"
      kind       = "ConfigMap"
      metadata = {
        name      = configmap.name
        namespace = configmap.namespace
      }
      data = configmap.data
    })
  }
}

resource "kubectl_manifest" "nccl_rccl_configmap" {
  for_each = alltrue([local.deploy_nccl_rccl_param_configmap, local.deploy_from_local || local.deploy_from_orm]) ? local.nccl_rccl_configmap_manifests : {}

  yaml_body         = each.value
  server_side_apply = true
  wait_for_rollout  = false

  depends_on = [
    module.oke,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke,
  ]
}
