# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
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
variable "create_dynamic_group" { default = true }
variable "use_existing_dynamic_group" {
  type    = bool
  default = false
}
variable "use_default_identity_domain" {
  type    = bool
  default = true
}
variable "identity_domain_compartment_id" {
  type    = string
  default = null
}
variable "identity_domain_id" {
  type    = string
  default = null
}
variable "dynamic_group_id" {
  type    = string
  default = null
}
variable "dynamic_group_id_input" {
  type    = string
  default = null
}


# General Variables
variable "ssh_public_key" {
  default = null
  type    = string
}

# Network
variable "create_vcn" { default = true }
variable "enable_ipv6" { default = false }

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
variable "bastion_service_sn_cidr" { default = null }
variable "operator_sn_cidr" { default = null }
variable "int_lb_sn_cidr" { default = null }
variable "pub_lb_sn_cidr" { default = null }
variable "cp_sn_cidr" { default = null }
variable "workers_sn_cidr" { default = null }
variable "pods_sn_cidr" { default = null }
variable "fss_sn_cidr" { default = null }
variable "lustre_sn_cidr" { default = null }
variable "worker_secondary_vnic_subnets" {
  default     = {}
  description = "Additional subnet definitions for worker secondary VNICs. Keys can be referenced by worker_pool_secondary_vnics[*][*].subnet_key, and values follow the module subnets map shape, for example { create = \"always\", ipv4cidr_blocks = [\"100.64.0.0/21\", \"100.64.8.0/21\"] }."
  type        = any
}
variable "bastion_sn_id" { default = null }
variable "bastion_service_sn_id" { default = null }
variable "operator_sn_id" { default = null }
variable "int_lb_sn_id" { default = null }
variable "pub_lb_sn_id" { default = null }
variable "cp_sn_id" { default = null }
variable "workers_sn_id" { default = null }
variable "pods_sn_id" { default = null }
variable "fss_sn_id" { default = null }
variable "lustre_sn_id" { default = null }
variable "subnet_advanced_attrs" {
  default = {}
  type    = any
}
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
variable "allow_rules_lustre" {
  default = {}
  type    = any
}
variable "use_stateless_rules" {
  type    = bool
  default = false
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

# Bastion Service
variable "create_oci_bastion_service" {
  default     = false
  description = "Create an OCI Bastion service in a dedicated subnet."
  type        = bool
}
variable "bastion_service_allowed_cidrs" {
  default     = ["0.0.0.0/0"]
  description = "CIDR allowlist for OCI Bastion service clients."
  type        = list(string)
}
variable "bastion_service_allow_worker_ssh" {
  default     = false
  description = "Allow SSH access to worker nodes via OCI Bastion Service."
  type        = bool
}
variable "bastion_service_max_session_ttl" {
  default     = 10800
  description = "Max session TTL in seconds for the OCI Bastion service (max 10800)."
  type        = number
}

# Operator
variable "create_operator" { default = true }
variable "operator_shape_config" { default = false }
variable "operator_shape_name" { default = "VM.Standard.E5.Flex" }
variable "operator_shape_ocpus" { default = 1 }
variable "operator_shape_ocpus_denseIO_e4_flex" {
  default = 8
  type    = number
}
variable "operator_shape_ocpus_denseIO_e5_flex" {
  default = 8
  type    = number
}
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
variable "nvme_raid_enabled" { default = true }
variable "nvme_raid_level" { default = 10 }
variable "create_lustre" { default = false }
variable "create_lustre_pv" { default = true }
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
variable "lustre_mount_path" {
  default = "/mnt/oci-lustre"
  type    = string
}
# created variable for fss mounting
variable "fss_mount_path" {
  default = "/mnt/oci-fss"
  type    = string
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

variable "install_amd_device_metrics_exporter" {
  default = false
  type    = bool
}

variable "install_mpi_operator" {
  default     = true
  type        = bool
  description = "Install MPI Operator for running MPIJob workloads."
}

variable "install_nvidia_dra_driver" {
  default     = true
  type        = bool
  description = "Install the NVIDIA DRA driver Helm chart for GPU Memory Cluster compute domains."
}

variable "nvidia_dra_driver_chart_version" {
  default     = "0.4.0"
  type        = string
  description = "NVIDIA DRA driver Helm chart version."
}

variable "monitoring_namespace" {
  default = "monitoring"
  type    = string
}

variable "node_problem_detector_chart_version" {
  default = "2.4.1"
  type    = string
}

variable "prometheus_stack_chart_version" {
  default = "85.0.3"
  type    = string
}

variable "amd_device_metrics_exporter_chart_version" {
  default = "v1.5.0"
  type    = string
}

variable "cert_manager_chart_version" {
  default = "v1.20.2"
  type    = string
}

variable "ingress_chart_version" {
  default = "0.5.0"
  type    = string
}

variable "oke_ons_webhook_chart_version" {
  default = "0.1.0"
  type    = string
}

variable "setup_oci_metrics_exporter" {
  default = true
  type    = bool
}

variable "oci_metrics_exporter_chart_version" {
  default = "0.1.0"
  type    = string
}

variable "setup_alerting" {
  default = true
  type    = bool
}

variable "avoid_waiting_for_delete_target" {
  default = false
  type    = bool
}

variable "use_lets_encrypt_prod_endpoint" {
  default = true
  type    = bool
}

variable "wildcard_dns_domain" {
  default = "endpoint.oci-hpc.ai"
  type    = string
}

variable "monitoring_advanced_options" {
  default = false
  type    = bool
}

# OKE Cluster Setup
variable "cluster_name" { default = "oke-gpu-quickstart" }
variable "kubernetes_version" { default = "v1.34.2" }
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
variable "services_cidr" {
  default     = "10.96.0.0/16"
  description = "CIDR block for Kubernetes services."
  type        = string
}
variable "preferred_kubernetes_services" {
  type        = string
  default     = "public"
  description = "The type of preferred Kubernetes services. Accepted options are public or internal."
}
variable "setup_credential_provider_for_ocir" {
  type        = bool
  default     = true
  description = "Setup the OKE credential provider for OCIR."
}

# OKE Cluster Setup - Advanced Options
variable "override_hostnames" {
  default = false
  type    = bool
}
variable "disable_gpu_device_plugin" { default = false }

variable "deploy_node_feature_discovery" {
  type        = bool
  default     = true
  description = "Deploy the NodeFeatureDiscovery OKE addon."
}

variable "deploy_nvidia_gpu_operator" {
  type        = bool
  default     = true
  description = "Deploy the NvidiaGpuOperator OKE addon."
}

variable "nvidia_gpu_operator_advanced_options" {
  type        = bool
  default     = false
  description = "Show advanced NVIDIA GPU Operator configuration options in the ORM UI."
}

variable "nvidia_gpu_operator_addon_version" {
  type        = string
  default     = "v25.10.1"
  description = "Version of the NvidiaGpuOperator OKE addon."
}

variable "nvidia_gpu_operator_disable_plugin" {
  type        = bool
  default     = true
  description = "Disable the NvidiaGpuPlugin when using the NVIDIA GPU Operator addon."
}

variable "nvidia_gpu_operator_cdi_enabled" {
  type        = bool
  default     = true
  description = "Enable CDI (Container Device Interface) in the NVIDIA GPU Operator addon."
}

variable "nvidia_gpu_operator_toolkit_enabled" {
  type        = bool
  default     = true
  description = "Enable the NVIDIA container toolkit in the NVIDIA GPU Operator addon."
}

variable "nvidia_gpu_operator_skip_nfd_dependency_check" {
  type        = bool
  default     = false
  description = "Skip the NodeFeatureDiscovery dependency check in the NVIDIA GPU Operator addon."
}

variable "nvidia_gpu_operator_mig_manager_enabled" {
  type        = bool
  default     = false
  description = "Enable the NVIDIA MIG Manager in the NVIDIA GPU Operator addon."
}

variable "nvidia_gpu_operator_mig_strategy" {
  type        = string
  default     = "single"
  description = "MIG strategy for GFD and Device Plugin (none, single, mixed)."
}

variable "nvidia_gpu_operator_configuration" {
  type = map(string)
  default = {
    "cdi.default"                                  = "false"
    "daemonsets.rollingUpdate.maxUnavailable"      = "10%"
    "dcgm.enabled"                                 = "true"
    "dcgmExporter.enabled"                         = "true"
    "dcgmExporter.service.internalTrafficPolicy"   = "Cluster"
    "dcgmExporter.serviceMonitor.enabled"          = "true"
    "dcgmExporter.serviceMonitor.interval"         = "15s"
    "dcgmExporter.serviceMonitor.honorLabels"      = "false"
    "dcgmExporter.serviceMonitor.additionalLabels" = "{\"release\":\"kube-prometheus-stack\"}"
    "dcgmExporter.serviceMonitor.relabelings"      = "[{\"action\":\"replace\",\"sourceLabels\":[\"__meta_kubernetes_pod_node_name\"],\"targetLabel\":\"hostname\"},{\"action\":\"replace\",\"sourceLabels\":[\"__meta_kubernetes_node_label_node_kubernetes_io_instance_type\"],\"targetLabel\":\"instance_shape\"},{\"action\":\"replace\",\"sourceLabels\":[\"__meta_kubernetes_node_label_oci_oraclecloud_com_host_serial_number\"],\"targetLabel\":\"host_serial_number\"},{\"action\":\"replace\",\"sourceLabels\":[\"__meta_kubernetes_node_label_displayName\"],\"targetLabel\":\"oci_name\"}]"
    "dcgmExporter.config.name"                     = "metrics-config"
    "dcgmExporter.env"                             = "[{\"name\":\"DCGM_EXPORTER_COLLECTORS\",\"value\":\"/etc/dcgm-exporter/dcgm-metrics.csv\"}]"
    "devicePlugin.enabled"                         = "true"
    "devicePlugin.mps.root"                        = "/run/nvidia/mps"
    "toolkit.installDir"                           = "/usr/local/nvidia"
    "operator.logging.level"                       = "info"
    "hostPaths.rootFS"                             = "/"
    "hostPaths.driverInstallDir"                   = "/run/nvidia/driver"
  }
  description = "Additional configuration key-value pairs for the NvidiaGpuOperator OKE addon. These are merged with the individual variables above, which take precedence."
}

variable "kubeproxy_mode" { default = "ipvs" }
variable "oke_pre_bootstrap_script" {
  type        = string
  default     = ""
  description = "Bash commands to be executed on all of the worker nodes before the OKE Bootstrapping."
}
variable "oke_post_bootstrap_script" {
  type        = string
  default     = ""
  description = "Bash commands to be executed on all of the worker nodes after the OKE Bootstrapping."
}
variable "oke_kubelet_extra_args" {
  type        = string
  default     = ""
  description = "kubelet-extra-args to be used for the kubelet configuration. https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/"
}

# Instance Metadata Service (IMDS)
variable "legacy_imds_endpoints_disabled" {
  type        = bool
  default     = true
  description = "Whether to disable legacy IMDS endpoints on nodepool instances (IMDSv1). When true, only IMDSv2 is available."
}
variable "worker_pool_secondary_vnics" {
  default     = {}
  description = "Per-worker-pool secondary VNIC profiles keyed by worker pool name, then VNIC name. Applies to managed OKE node pools such as oke-system, oke-cpu, oke-gpu, and oke-rdma. Each profile can include subnet_id or subnet_key, ip_count, nsg_ids, assign_public_ip, skip_source_dest_check, display_name, and optional application_resources."
  type        = any
}

# Worker secondary VNIC UI inputs
variable "worker_ops_secondary_vnic_enabled" { default = false }
variable "worker_ops_secondary_vnic_subnet_cidr" {
  default = null
  type    = string
}
variable "worker_ops_secondary_vnic_subnet_id" {
  default = null
  type    = string
}
variable "worker_ops_secondary_vnic_ip_count" {
  default = 32
  validation {
    condition     = contains([1, 2, 4, 8, 16, 32, 64, 128, 256], var.worker_ops_secondary_vnic_ip_count)
    error_message = "worker_ops_secondary_vnic_ip_count must be a power of two from 1 to 256."
  }
}
variable "worker_ops_secondary_vnic_nsg_ids" {
  default = []
  type    = list(string)
}
variable "worker_cpu_secondary_vnic_enabled" { default = false }
variable "worker_cpu_secondary_vnic_subnet_cidr" {
  default = null
  type    = string
}
variable "worker_cpu_secondary_vnic_subnet_id" {
  default = null
  type    = string
}
variable "worker_cpu_secondary_vnic_ip_count" {
  default = 32
  validation {
    condition     = contains([1, 2, 4, 8, 16, 32, 64, 128, 256], var.worker_cpu_secondary_vnic_ip_count)
    error_message = "worker_cpu_secondary_vnic_ip_count must be a power of two from 1 to 256."
  }
}
variable "worker_cpu_secondary_vnic_nsg_ids" {
  default = []
  type    = list(string)
}
variable "worker_gpu_secondary_vnic_enabled" { default = false }
variable "worker_gpu_secondary_vnic_subnet_cidr" {
  default = null
  type    = string
}
variable "worker_gpu_secondary_vnic_subnet_id" {
  default = null
  type    = string
}
variable "worker_gpu_secondary_vnic_ip_count" {
  default = 32
  validation {
    condition     = contains([1, 2, 4, 8, 16, 32, 64, 128, 256], var.worker_gpu_secondary_vnic_ip_count)
    error_message = "worker_gpu_secondary_vnic_ip_count must be a power of two from 1 to 256."
  }
}
variable "worker_gpu_secondary_vnic_nsg_ids" {
  default = []
  type    = list(string)
}
variable "worker_rdma_secondary_vnic_enabled" { default = false }
variable "worker_rdma_secondary_vnic_subnet_cidr" {
  default = null
  type    = string
}
variable "worker_rdma_secondary_vnic_subnet_id" {
  default = null
  type    = string
}
variable "worker_rdma_secondary_vnic_ip_count" {
  default = 32
  validation {
    condition     = contains([1, 2, 4, 8, 16, 32, 64, 128, 256], var.worker_rdma_secondary_vnic_ip_count)
    error_message = "worker_rdma_secondary_vnic_ip_count must be a power of two from 1 to 256."
  }
}
variable "worker_rdma_secondary_vnic_nsg_ids" {
  default = []
  type    = list(string)
}

# Workers - System pool
variable "worker_ops_ad" { default = "" }
variable "worker_ops_pool_size" { default = 3 }
variable "worker_ops_shape" { default = "VM.Standard.E5.Flex" }
variable "worker_ops_ocpus" { default = 4 }
variable "worker_ops_memory" { default = 16 }
variable "worker_ops_boot_volume_size" { default = 128 }
variable "worker_ops_image_type" { default = "Custom" }
variable "worker_ops_image_custom_id" { default = "" }
variable "worker_ops_image_custom_uri" { default = "" }
variable "worker_ops_image_platform_id" {
  default = null
  type    = string
}
variable "worker_ops_image_os" { default = "Oracle Linux" }
variable "worker_ops_image_os_version" { default = "8" }
variable "worker_ops_image_use_uri" {
  default = false
  type    = bool
}
variable "worker_ops_max_pods_per_node" {
  default     = 110
  description = "Maximum number of pods per node for the system worker pool. Max is 110."
  type        = number
}
variable "worker_ops_kubernetes_version" {
  default     = null
  description = "Kubernetes version for the system worker pool. Defaults to cluster version if not specified."
  type        = string
}
variable "worker_ops_node_cycling_enabled" {
  default     = false
  description = "Enable node cycling for the system worker pool."
  type        = bool
}
variable "worker_ops_node_cycling_max_surge" {
  default     = "25%"
  description = "Maximum surge for node cycling in the system worker pool."
  type        = string
}
variable "worker_ops_node_cycling_max_unavailable" {
  default     = 0
  description = "Maximum unavailable nodes during node cycling in the system worker pool."
  type        = number
}
variable "worker_ops_node_cycling_mode" {
  default     = "instance"
  description = "What node cycling mode will be used for nodes in the system worker pool. Accepted options are 'instance' or 'boot_volume'."
  type        = string
}

# Workers - CPU pool
variable "worker_cpu_enabled" { default = false }
variable "worker_cpu_ad" { default = "" }
variable "worker_cpu_pool_size" { default = 1 }
variable "worker_cpu_shape" { default = "VM.Standard.E5.Flex" }
variable "worker_cpu_ocpus" { default = 6 }
variable "worker_cpu_ocpus_denseIO_e4_flex" {
  default = 8
  type    = number
}
variable "worker_cpu_ocpus_denseIO_e5_flex" {
  default = 8
  type    = number
}
variable "worker_cpu_memory" { default = 32 }
variable "worker_cpu_boot_volume_size" { default = 256 }
variable "worker_cpu_image_type" { default = "Custom" }
variable "worker_cpu_image_custom_id" {
  default = null
  type    = string
}
variable "worker_cpu_image_custom_uri" {
  default = null
  type    = string
}
variable "worker_cpu_image_use_uri" {
  default = false
  type    = bool
}
variable "worker_cpu_image_os" { default = "Oracle Linux" }
variable "worker_cpu_image_os_version" { default = "8" }
variable "worker_cpu_image_platform_id" {
  default = null
  type    = string
}
variable "worker_cpu_max_pods_per_node" {
  default     = 110
  description = "Maximum number of pods per node for the CPU worker pool. Max is 110."
  type        = number
}
variable "worker_cpu_kubernetes_version" {
  default     = null
  description = "Kubernetes version for the CPU worker pool. Defaults to cluster version if not specified."
  type        = string
}
variable "worker_cpu_node_cycling_enabled" {
  default     = false
  description = "Enable node cycling for the CPU worker pool."
  type        = bool
}
variable "worker_cpu_node_cycling_max_surge" {
  default     = "25%"
  description = "Maximum surge for node cycling in the CPU worker pool."
  type        = string
}
variable "worker_cpu_node_cycling_max_unavailable" {
  default     = 0
  description = "Maximum unavailable nodes during node cycling in the CPU worker pool."
  type        = number
}
variable "worker_cpu_node_cycling_mode" {
  default     = "instance"
  description = "What node cycling mode will be used for nodes in the CPU worker pool. Accepted options are 'instance' or 'boot_volume'."
  type        = string
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
variable "worker_gpu_image_custom_uri" {
  default = null
  type    = string
}
variable "worker_gpu_image_use_uri" {
  default = false
  type    = bool
}
variable "worker_gpu_image_os" { default = "Oracle Linux" }
variable "worker_gpu_image_os_version" { default = "8" }
variable "worker_gpu_image_platform_id" {
  default = null
  type    = string
}
variable "worker_gpu_max_pods_per_node" {
  default     = 64
  description = "Maximum number of pods per node for the GPU worker pool. Max is 110."
  type        = number
}
variable "worker_gpu_kubernetes_version" {
  default     = null
  description = "Kubernetes version for the GPU worker pool. Defaults to cluster version if not specified."
  type        = string
}
variable "worker_gpu_node_cycling_enabled" {
  default     = false
  description = "Enable node cycling for the GPU worker pool."
  type        = bool
}
variable "worker_gpu_node_cycling_max_surge" {
  default     = "25%"
  description = "Maximum surge for node cycling in the GPU worker pool."
  type        = string
}
variable "worker_gpu_node_cycling_max_unavailable" {
  default     = 0
  description = "Maximum unavailable nodes during node cycling in the GPU worker pool."
  type        = number
}
variable "worker_gpu_node_cycling_mode" {
  default     = "boot_volume"
  description = "What node cycling mode will be used for nodes in the GPU worker pool. Accepted options are 'instance' or 'boot_volume'."
  type        = string
}

# Workers - GPU + RDMA node pool
variable "worker_rdma_enabled" { default = false }
variable "worker_rdma_ad" { default = "" }
variable "worker_rdma_pool_size" { default = 4 }
variable "worker_rdma_shape" { default = "BM.GPU.H100.8" }
variable "worker_rdma_boot_volume_size" { default = 512 }
variable "worker_rdma_boot_volume_vpus_per_gb" { default = 10 }
variable "worker_rdma_compute_cluster_id" {
  default     = null
  description = "Compute Cluster OCID to use for GPU + RDMA OKE-managed node pool placement."
  type        = string
}
variable "worker_rdma_host_group_id" {
  default     = null
  description = "Optional Compute Host Group OCID to use with the GPU + RDMA OKE-managed node pool."
  type        = string
}
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
variable "worker_rdma_image_custom_uri" {
  default = null
  type    = string
}
variable "worker_rdma_image_use_uri" {
  default = false
  type    = bool
}
variable "worker_rdma_max_pods_per_node" {
  default     = 64
  description = "Maximum number of pods per node for the RDMA worker pool. Max is 110."
  type        = number
}
variable "worker_rdma_kubernetes_version" {
  default     = null
  description = "Kubernetes version for the RDMA worker pool. Defaults to cluster version if not specified."
  type        = string
}

# Workers - GPU Memory Cluster
variable "worker_gmc_enabled" {
  default     = false
  description = "Whether to create the GPU Memory Cluster worker pool."
  type        = bool
}
variable "worker_gmc_ad" {
  default     = ""
  description = "Availability domain for the GMC worker pool (e.g. 'ZHZP:AP-SYDNEY-1-AD-1'). Only the trailing AD number is used."
  type        = string
}
variable "worker_gmc_shape" {
  default     = "BM.GPU.GB200-v3.4"
  description = "Shape for the GMC worker pool."
  type        = string
}
variable "worker_gmc_image_id" {
  default     = null
  description = "Custom image OCID for the GMC worker pool. Must be a GMC/RDMA-compatible image for the chosen shape."
  type        = string
}
variable "worker_gmc_boot_volume_size" {
  default     = 512
  description = "Boot volume size in GB for the GMC worker pool."
  type        = number
}
variable "worker_gmc_boot_volume_vpus_per_gb" {
  default     = 10
  description = "Boot volume VPUs/GB for the GMC worker pool."
  type        = number
}
variable "worker_gmc_max_pods_per_node" {
  default     = 64
  description = "Maximum number of pods per node for the GMC worker pool. Max is 110."
  type        = number
}
variable "worker_gmc_kubernetes_version" {
  default     = null
  description = "Kubernetes version for the GMC worker pool. Defaults to cluster version if not specified."
  type        = string
}
variable "worker_gmc_gpu_memory_fabric_ids" {
  default     = ""
  description = "GPU Memory Fabric OCIDs to fan out into one GPU Memory Cluster per fabric, one OCID per line."
  type        = string
  validation {
    condition = alltrue([
      for id in compact([
        for line in split("\n", trimspace(var.worker_gmc_gpu_memory_fabric_ids)) : trimspace(line)
      ]) : can(regex("^ocid1\\..*", id))
    ])
    error_message = "GPU Memory Fabric OCIDs must be provided one per line."
  }
}
variable "worker_gmc_scale_target_size" {
  default     = 18
  description = "Target size for the GPU Memory Cluster scale config (number of nodes per fabric)."
  type        = number
}
variable "worker_gmc_scale_is_upsize_enabled" {
  default     = true
  description = "Allow the OCI control plane to upsize the GPU Memory Cluster."
  type        = bool
}
variable "worker_gmc_scale_is_downsize_enabled" {
  default     = true
  description = "Allow the OCI control plane to downsize the GPU Memory Cluster."
  type        = bool
}

# Kueue
variable "install_kueue" {
  default     = true
  type        = bool
  description = "Install Kueue and create Topology Aware Scheduling resources (Topology, ResourceFlavor, ClusterQueue, LocalQueue)."
}

variable "kueue_chart_version" {
  default = "0.17.2"
  type    = string
}

variable "kueue_local_queue_default_namespace" {
  default     = "default"
  type        = string
  description = "The namespace where the Kueue LocalQueue will be created."
}

# OCI HPC OKE Utils
variable "install_oci_hpc_oke_utils" {
  default     = true
  type        = bool
  description = "Install the OCI HPC OKE Utils Helm chart (includes RDMA topology labeler and image prepuller)."
}

# RDMA topology labeler
variable "install_rdma_labeler" {
  default     = true
  type        = bool
  description = "Deploy the RDMA topology labeler DaemonSet to populate node labels required for Topology Aware Scheduling."
}

# Image prepuller
variable "install_image_prepuller" {
  default     = false
  type        = bool
  description = "Deploy the image prepuller DaemonSet to pre-pull container images on GPU worker nodes."
}

# hostexec
variable "install_hostexec" {
  default     = false
  type        = bool
  description = "Deploy the hostexec DaemonSet to execute commands on the host."
}


# K8s resources deployment method
variable "deploy_to_oke_from_orm" {
  type        = bool
  default     = false
  description = "Should be set to true when deploying the stack from Oracle Resource Manager."
}
