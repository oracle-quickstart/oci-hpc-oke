# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  scrape_interval = format("%vs", var.scrape_interval_seconds)
  scrape_timeout  = format("%vs", var.scrape_timeout_seconds)
  retention       = format("%vh", var.retention_hours)
  retention_size  = format("%vGB", var.retention_gb)
}

variable "compartment_ocid" { type = string }
variable "create_policies" { default = true }
variable "create_vcn" { default = true }
variable "kubernetes_version" { default = "v1.29.1" }
variable "region" { type = string }
variable "tenancy_ocid" { type = string }
variable "vcn_cidrs" { default = "10.140.0.0/16" } # TODO input in RMS schema
variable "vcn_name" { default = "oke-gpu-quickstart" }

variable "create_bastion" { default = true }
variable "bastion_shape" { default = "VM.Standard.E4.Flex" }
variable "bastion_allowed_cidrs" { default = ["0.0.0.0/0"] }
variable "bastion_image_type" {
  default     = "platform"
  description = "Whether to use a platform or custom image for the created bastion instance. When custom is set, the bastion_image_id must be specified."
  type        = string
}

variable "bastion_image_os" {
  default     = "Oracle Autonomous Linux"
  description = "Bastion image operating system name when bastion_image_type = 'platform'."
  type        = string
}

variable "bastion_image_os_version" {
  default     = "8"
  description = "Bastion image operating system version when bastion_image_type = 'platform'."
  type        = string
}

variable "bastion_image_id" {
  default     = null
  description = "Image ID for created bastion instance."
  type        = string
}


variable "cluster_name" { default = "oke-gpu-quickstart" }
variable "control_plane_allowed_cidrs" { default = ["0.0.0.0/0"] }

variable "create_operator" { default = false }
variable "operator_shape_config" { default = false }
variable "operator_shape_name" { default = "VM.Standard.E4.Flex" }
variable "operator_shape_ocpus" { default = 2 }
variable "operator_shape_memory" { default = 2 }
variable "operator_shape_boot" { default = 50 }
variable "operator_image_id" {
  default     = null
  description = "Image ID for created operator instance."
  type        = string
}

variable "operator_image_os" {
  default     = "Oracle Linux"
  description = "Operator image operating system name when operator_image_type = 'platform'."
  type        = string
}

variable "operator_image_os_version" {
  default     = "8"
  description = "Operator image operating system version when operator_image_type = 'platform'."
  type        = string
}

variable "operator_image_type" {
  default     = "platform"
  description = "Whether to use a platform or custom image for the created operator instance. When custom is set, the operator_image_id must be specified."
  type        = string
}

variable "create_fss" { default = false }
variable "fss_ad" { default = "" }
variable "create_bv_high" { default = false }

variable "worker_ops_boot_volume_size" { default = 128 }
variable "worker_ops_memory" { default = 64 }
variable "worker_ops_ocpus" { default = 16 }
variable "worker_ops_pool_size" { default = 3 }
variable "worker_ops_shape" { default = "VM.Standard.E4.Flex" }
variable "worker_ops_image_type" { default = "Custom" }
variable "worker_ops_image_custom_id" { default = "" }
variable "worker_ops_ad" { default = "" }

variable "worker_cpu_boot_volume_size" { default = 256 }
variable "worker_cpu_enabled" { default = false }
variable "worker_cpu_image_id" { default = "" }
variable "worker_cpu_image_os_version" { default = "8" }
variable "worker_cpu_image_os" { default = "Oracle Linux" }
variable "worker_cpu_image_type" { default = "Custom" }
variable "worker_cpu_memory" { default = 32 }
variable "worker_cpu_ocpus" { default = 4 }
variable "worker_cpu_pool_size" { default = 1 }
variable "worker_cpu_shape" { default = "VM.Standard.E4.Flex" }
variable "worker_cpu_ad" { default = "" }

variable "worker_gpu_boot_volume_size" { default = 512 }
variable "worker_gpu_enabled" { default = false }
variable "worker_gpu_pool_size" { default = 1 }
variable "worker_gpu_image_os_version" { default = "8" }
variable "worker_gpu_image_os" { default = "Oracle Linux" }
variable "worker_gpu_image_id" { default = "" }
variable "worker_gpu_image_type" { default = "Custom" }
variable "worker_gpu_shape" { default = "VM.GPU.A10.1" }
variable "worker_gpu_ad" { default = "" }

variable "worker_rdma_boot_volume_size" { default = 512 }
variable "worker_rdma_boot_volume_vpus_per_gb" { default = 10 }
variable "worker_rdma_ad" { default = "" }
variable "worker_rdma_enabled" { default = false }
variable "worker_rdma_pool_size" { default = 4 }
variable "worker_rdma_image_os_version" { default = "8" }
variable "worker_rdma_image_os" { default = "Oracle Linux" }
variable "worker_rdma_image_id" { default = "" }
variable "worker_rdma_image_type" { default = "Custom" }
variable "worker_rdma_shape" { default = "BM.GPU.H100.8" }
variable "disable_gpu_device_plugin" { default = false }

variable "worker_cpu_image_platform_id" {
  default = null
  type    = string
}
variable "worker_cpu_image_custom_id" {
  default = null
  type    = string
}
variable "worker_gpu_image_platform_id" {
  default = null
  type    = string
}
variable "worker_gpu_image_custom_id" {
  default = null
  type    = string
}
variable "worker_rdma_image_platform_id" {
  default = null
  type    = string
}
variable "worker_rdma_image_custom_id" {
  default = null
  type    = string
}
variable "current_user_ocid" {
  default = null
  type    = string
}
variable "api_fingerprint" {
  default = null
  type    = string
}
variable "ssh_public_key" {
  default = null
  type    = string
}
variable "vcn_id" {
  default = null
  type    = string
}
variable "vcn_compartment_ocid" {
  default = null
  type    = string
}
variable "oci_auth" {
  type        = string
  default     = null
  description = "One of [api_key instance_principal instance_principal_with_certs security_token resource_principal]"
}
variable "oci_profile" {
  type    = string
  default = null
}

# STORAGE
variable "nvme_raid_enabled" { default = true }
variable "nvme_raid_level" { default = 0 }

# MONITORING
# Installation

variable "install_monitoring" {
  default = true
  type    = bool
}
variable "install_prometheus_stack" {
  default = true
  type    = bool
}
variable "install_prometheus_adapter" {
  default = false
  type    = bool
}
variable "install_prometheus_pushgateway" {
  default = true
  type    = bool
}
variable "install_grafana" {
  default = true
  type    = bool
}
variable "install_grafana_dashboards" {
  default = true
  type    = bool
}
variable "install_metrics_server" {
  default = true
  type    = bool
}

variable "install_dcgm_exporter" {
  default = true
  type    = bool
}

variable "monitoring_namespace" {
  default = "monitoring"
  type    = string
}
variable "prometheus_stack_chart_version" {
  default = "62.3.1"
  type    = string
}
variable "prometheus_pushgateway_chart_version" {
  default = "2.14.0"
  type    = string
}
variable "prometheus_adapter_chart_version" {
  default = "4.11.0"
  type    = string
}
variable "metrics_server_chart_version" {
  default = "3.12.1"
  type    = string
}

variable "dcgm_exporter_chart_version" {
  default = "3.5.0"
  type    = string
}

# Configuration
variable "prom_server_memory_request" {
  default = "90%"
  type    = string
}
variable "prom_server_memory_limit" {
  default = "90%"
  type    = string
}
variable "retention_hours" {
  default = 48
  type    = number
}
variable "retention_gb" {
  default = 1000
  type    = number
}
variable "retention_storageclass" {
  default = "oci-bv"
  type    = string
}
variable "scrape_interval_seconds" {
  default = 30
  type    = string
}
variable "scrape_timeout_seconds" {
  default = 25
  type    = string
}