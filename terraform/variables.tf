# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

# Provider auth
variable "api_fingerprint" {
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

# ORM Variables
variable "current_user_ocid" {
  default = null
  type    = string
}
variable "compartment_ocid" { type = string }
variable "tenancy_ocid" { type = string }
variable "region" { type = string }

# Identity
variable "create_policies" { default = true }

# General Variables
variable "ssh_public_key" {
  default = null
  type    = string
}

# Network
variable "create_vcn" { default = true }

variable "vcn_compartment_ocid" {
  default = null
  type    = string
}
variable "vcn_id" {
  default = null
  type    = string
}
variable "vcn_name" { default = "oke-gpu-quickstart" }
variable "vcn_cidrs" { default = "10.140.0.0/16" }
variable "create_public_subnets" {
  type    = bool
  default = true
}
variable "bastion_sn_cidr" { default = null }
variable "operator_sn_cidr" { default = null }
variable "int_lb_sn_cidr" { default = null }
variable "pub_lb_sn_cidr" { default = null }
variable "cp_sn_cidr" { default = null }
variable "workers_sn_cidr" { default = null }
variable "pods_sn_cidr" { default = null }
variable "fss_sn_cidr" { default = null }
variable "lustre_sn_cidr" { default = null }
variable "bastion_sn_id" { default = null }
variable "operator_sn_id" { default = null }
variable "int_lb_sn_id" { default = null }
variable "pub_lb_sn_id" { default = null }
variable "cp_sn_id" { default = null }
variable "workers_sn_id" { default = null }
variable "pods_sn_id" { default = null }
variable "fss_sn_id" { default = null }
variable "lustre_sn_id" { default = null }
variable "networking_advanced_options" {
  type    = bool
  default = false
}
variable "custom_subnet_ids" {
  type    = bool
  default = false
}
variable "private_subnet_route_table" {
  type    = string
  default = null
}
variable "public_subnet_route_table" {
  type    = string
  default = null
}


# Bastion
variable "create_bastion" { default = true }
variable "bastion_shape_config" { default = false }
variable "bastion_shape_name" { default = "VM.Standard.E5.Flex" }
variable "bastion_shape_ocpus" { default = 1 }
variable "bastion_shape_memory" { default = 4 }
variable "bastion_is_public" {
  type        = bool
  default     = true
  description = "Create the bastion host in a public subnet and assign it a public IP."
}
variable "bastion_allowed_cidrs" { default = ["0.0.0.0/0"] }
variable "bastion_image_type" {
  default     = "platform"
  description = "Whether to use a platform or custom image for the created bastion instance. When custom is set, the bastion_image_id must be specified."
  type        = string
}
variable "bastion_image_os" {
  default     = "Canonical Ubuntu"
  description = "Bastion image operating system name when bastion_image_type = 'platform'."
  type        = string
}
variable "bastion_image_os_version" {
  default     = "22.04"
  description = "Bastion image operating system version when bastion_image_type = 'platform'."
  type        = string
}
variable "bastion_image_id" {
  default     = null
  description = "Image ID for created bastion instance."
  type        = string
}
variable "bastion_user" {
  default     = "ubuntu"
  description = "The user used to SSH into the bastion instance."
  type        = string
}

# Operator
variable "create_operator" { default = true }
variable "operator_shape_config" { default = false }
variable "operator_shape_name" { default = "VM.Standard.E5.Flex" }
variable "operator_shape_ocpus" { default = 1 }
variable "operator_shape_memory" { default = 8 }
variable "operator_shape_boot" { default = 50 }
variable "operator_image_id" {
  default     = null
  description = "Image ID for created operator instance."
  type        = string
}
variable "operator_image_os" {
  default     = "Canonical Ubuntu"
  description = "Operator image operating system name when operator_image_type = 'platform'."
  type        = string
}
variable "operator_image_os_version" {
  default     = "22.04"
  description = "Operator image operating system version when operator_image_type = 'platform'."
  type        = string
}
variable "operator_image_type" {
  default     = "platform"
  description = "Whether to use a platform or custom image for the created operator instance. When custom is set, the operator_image_id must be specified."
  type        = string
}
variable "operator_user" {
  default     = "ubuntu"
  description = "The user used to SSH into the operator instance."
  type        = string
}

# STORAGE
variable "create_fss" { default = false }
variable "fss_ad" { default = "" }
variable "create_bv_high" { default = false }
variable "nvme_raid_enabled" { default = true }
variable "nvme_raid_level" { default = 10 }
variable "create_lustre" { default = false }
variable "lustre_ad" { default = "" }
variable "lustre_size_in_tb" {
  type    = number
  default = 31.2
}
variable "lustre_performance_tier" {
  type    = number
  default = 125
}
variable "lustre_cluster_placement_group_id" { default = null }
variable "lustre_file_system_name" { default = "lustrefs" }
variable "install_lustre_client" {
  default = true
  type    = bool
}
variable "lustre_client_helm_chart_version" {
  default = "0.1.1"
  type    = string
}
variable "create_lustre_pv" {
  default = true
  type    = bool
}

# MONITORING
variable "install_monitoring" {
  default = true
  type    = bool
}

variable "install_node_problem_detector_kube_prometheus_stack" {
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

variable "install_nvidia_dcgm_exporter" {
  default = true
  type    = bool
}

variable "install_amd_device_metrics_exporter" {
  default = false
  type    = bool
}

variable "monitoring_namespace" {
  default = "monitoring"
  type    = string
}

variable "node_problem_detector_chart_version" {
  default = "2.3.22"
  type    = string
}

variable "prometheus_stack_chart_version" {
  default = "77.5.0"
  type    = string
}

variable "dcgm_exporter_chart_version" {
  default = "4.5.2"
  type    = string
}

variable "amd_device_metrics_exporter_chart_version" {
  default = "v1.3.1"
  type    = string
}

variable "nginx_chart_version" {
  default = "4.13.2"
  type    = string
}

variable "oke_ons_webhook_chart_version" {
  default = "0.1.0"
  type    = string
}

variable "setup_alerting" {
  default = true
  type    = bool
}

variable "avoid_waiting_for_delete_target" {
  default = true
  type    = bool
}

# OKE Cluster Setup
variable "cluster_name" { default = "oke-gpu-quickstart" }
variable "kubernetes_version" { default = "v1.34.1" }
variable "control_plane_allowed_cidrs" { default = ["0.0.0.0/0"] }
variable "cni_type" {
  default = "npn"
  type    = string
}
variable "control_plane_is_public" {
  type        = bool
  default     = true
  description = "Create the OKE control plane endpoint in a public subnet and assign it a public IP."
}
variable "max_pods_per_node" {
  default     = 110
  description = "The default maximum number of pods to deploy per node when unspecified on a pool. Absolute maximum is 110. Ignored when when cni_type != 'npn'."
  type        = number
}
variable "preferred_kubernetes_services" {
  type        = string
  default     = "public"
  description = "The type of preferred Kubernetes services. Accepted options are public or internal."
}

# OKE Cluster Setup - Advanced Options
variable "override_hostnames" {
  default = false
  type    = bool
}
variable "disable_gpu_device_plugin" { default = false }

# Workers - System pool
variable "worker_ops_ad" { default = "" }
variable "worker_ops_pool_size" { default = 2 }
variable "worker_ops_shape" { default = "VM.Standard.E5.Flex" }
variable "worker_ops_ocpus" { default = 8 }
variable "worker_ops_memory" { default = 32 }
variable "worker_ops_boot_volume_size" { default = 128 }
variable "worker_ops_image_type" { default = "Custom" }
variable "worker_ops_image_custom_id" { default = "" }

# Workers - CPU pool
variable "worker_cpu_enabled" { default = false }
variable "worker_cpu_ad" { default = "" }
variable "worker_cpu_pool_size" { default = 1 }
variable "worker_cpu_shape" { default = "VM.Standard.E5.Flex" }
variable "worker_cpu_ocpus" { default = 6 }
variable "worker_cpu_memory" { default = 32 }
variable "worker_cpu_boot_volume_size" { default = 256 }
variable "worker_cpu_image_type" { default = "Custom" }
variable "worker_cpu_image_custom_id" {
  default = null
  type    = string
}
variable "worker_cpu_image_id" { default = "" }
variable "worker_cpu_image_os" { default = "Oracle Linux" }
variable "worker_cpu_image_os_version" { default = "8" }
variable "worker_cpu_image_platform_id" {
  default = null
  type    = string
}

# Workers - GPU node-pool
variable "worker_gpu_enabled" { default = false }
variable "worker_gpu_ad" { default = "" }
variable "worker_gpu_pool_size" { default = 1 }
variable "worker_gpu_shape" { default = "VM.GPU.A10.1" }
variable "worker_gpu_boot_volume_size" { default = 512 }
variable "worker_gpu_image_type" { default = "Custom" }
variable "worker_gpu_image_custom_id" {
  default = null
  type    = string
}
variable "worker_gpu_image_os" { default = "Oracle Linux" }
variable "worker_gpu_image_os_version" { default = "8" }
variable "worker_gpu_image_platform_id" {
  default = null
  type    = string
}
variable "worker_gpu_image_id" { default = "" }

# Workers - GPU Cluster-network
variable "worker_rdma_enabled" { default = false }
variable "worker_rdma_ad" { default = "" }
variable "worker_rdma_pool_size" { default = 4 }
variable "worker_rdma_shape" { default = "BM.GPU.H100.8" }
variable "worker_rdma_boot_volume_size" { default = 512 }
variable "worker_rdma_boot_volume_vpus_per_gb" { default = 10 }
variable "worker_rdma_image_type" { default = "Custom" }
variable "worker_rdma_image_os" { default = "Oracle Linux" }
variable "worker_rdma_image_os_version" { default = "8" }
variable "worker_rdma_image_platform_id" {
  default = null
  type    = string
}
variable "worker_rdma_image_custom_id" {
  default = null
  type    = string
}
variable "worker_rdma_image_id" { default = "" }

# K8s resources deployment method
variable "deploy_to_oke_from_orm" {
  type        = bool
  default     = false
  description = "Should be set to true when deploying the stack from Oracle Resource Manager."
}
