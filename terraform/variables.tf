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

  validation {
    condition     = contains(["platform", "custom"], lower(var.bastion_image_type))
    error_message = "bastion_image_type must be either 'platform' or 'custom'."
  }
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
variable "bastion_image_compartment" {
  default     = null
  description = "Compartment containing the selected bastion custom image."
  type        = string
}
variable "bastion_image_custom_uri" {
  default     = null
  description = "Object Storage URI used to import a custom image for the created bastion instance."
  type        = string
}
variable "bastion_image_use_uri" {
  default     = false
  description = "Import the bastion custom image from an Object Storage URI."
  type        = bool
}
variable "bastion_user" {
  default     = "auto"
  description = "The user used to SSH into the bastion instance. Set to 'auto' to use opc for Oracle Linux images and ubuntu for all other images, or override with your own username."
  type        = string

  validation {
    condition     = lower(var.bastion_user) == "auto" || can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.bastion_user))
    error_message = "bastion_user must be 'auto' or a valid Linux username."
  }
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

  validation {
    condition     = contains(["platform", "custom"], lower(var.operator_image_type))
    error_message = "operator_image_type must be either 'platform' or 'custom'."
  }
}
variable "operator_image_compartment" {
  default     = null
  description = "Compartment containing the selected operator custom image."
  type        = string
}
variable "operator_image_custom_uri" {
  default     = null
  description = "Object Storage URI used to import a custom image for the created operator instance."
  type        = string
}
variable "operator_image_use_uri" {
  default     = false
  description = "Import the operator custom image from an Object Storage URI."
  type        = bool
}
variable "operator_allow_image_drift" {
  default     = true
  description = "Allow the operator instance image to drift from the latest resolved image without forcing replacement."
  type        = bool
}
variable "operator_user" {
  default     = "auto"
  description = "The user used to SSH into the operator instance. Set to 'auto' to use opc for Oracle Linux images and ubuntu for all other images, or override with your own username."
  type        = string

  validation {
    condition     = lower(var.operator_user) == "auto" || can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.operator_user))
    error_message = "operator_user must be 'auto' or a valid Linux username."
  }
}

# STORAGE
variable "create_fss" { default = true }
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
  default = true
  type    = bool
}

variable "install_mpi_operator" {
  default     = true
  type        = bool
  description = "Install MPI Operator for running MPIJob workloads."
}

variable "deploy_nccl_rccl_param_configmap" {
  default     = true
  type        = bool
  description = "Create a shape-specific ConfigMap in the default namespace with the recommended NCCL/RCCL parameters for each enabled RDMA or GMC GPU shape. Names use oci-nccl-parameters-<shape> for NVIDIA and oci-rccl-parameters-<shape> for AMD, with the shape converted to lowercase and dots replaced by hyphens. NCCL_IB_HCA is set to 'mlx5' when SR-IOV virtual functions are enabled via the network operator for that shape, otherwise the shape's full device list."
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
  default = "87.2.1"
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
  default = "0.6.0"
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
variable "kubernetes_version" { default = "v1.35.2" }
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
variable "hostname_override" {
  default     = false
  type        = bool
  description = "Bootstrap worker nodes with kubelet --hostname-override so they register in Kubernetes by hostname instead of private IP address. Defaults to false: Slurm deployments get clean Slurm node names from the nodeset.slinky.slurm.net/hostname-override node annotation set by the oci-hpc-oke-utils annotator instead (requires the Slurm operator chart 1.2 or later)."
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

variable "nvidia_gpu_operator_cdi_default" {
  type        = bool
  default     = true
  description = "Use CDI as the default device-injection mode (cdi.default). Requires nvidia_gpu_operator_cdi_enabled = true and a CDI-capable device list strategy (nvidia_gpu_operator_device_list_strategy = \"cdi-cri\"); otherwise GPU pods fail with \"unresolvable CDI devices\"."
}

variable "nvidia_gpu_operator_device_list_strategy" {
  type        = string
  default     = "cdi-cri"
  description = "DEVICE_LIST_STRATEGY for the NVIDIA device plugin. \"cdi-cri\" (the default) makes the device plugin generate the workload CDI spec and pass devices via CRI, which is required when CDI is enabled. \"envvar\" passes bare GPU UUIDs and is incompatible with CDI mode. Any value other than \"envvar\" makes the addon set devicePlugin.env."

  validation {
    condition     = contains(["envvar", "cdi-cri", "cdi-annotations", "volume-mounts"], var.nvidia_gpu_operator_device_list_strategy)
    error_message = "nvidia_gpu_operator_device_list_strategy must be one of: envvar, cdi-cri, cdi-annotations, volume-mounts."
  }
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

variable "deploy_nvidia_network_operator" {
  type        = bool
  default     = false
  description = "Deploy the NvidiaNetworkOperator OKE addon."
}

variable "nvidia_network_operator_addon_version" {
  type        = string
  default     = "v25.10.0"
  description = "Version of the NvidiaNetworkOperator OKE addon."
}

variable "nvidia_network_operator_configuration" {
  type = map(string)
  default = {
    "sriovNetworkOperator.enabled" = "true"
  }
  description = "Configuration key-value pairs for the NvidiaNetworkOperator OKE addon."
}

variable "nvidia_network_operator_ipam_subnet" {
  type        = string
  default     = "192.168.0.0/16"
  description = "Subnet for the NVIDIA IPAM IP pool used by SR-IOV network interfaces."
}

variable "nvidia_network_operator_ipam_gateway" {
  type        = string
  default     = "192.168.0.1"
  description = "Gateway for the NVIDIA IPAM IP pool used by SR-IOV network interfaces."
}

variable "nvidia_network_operator_ipam_per_node_block_size" {
  type        = number
  default     = 100
  description = "Number of IPs allocated to each node from the NVIDIA IPAM IP pool."
}

variable "nvidia_network_operator_sriov_max_unavailable" {
  type        = string
  default     = "100%"
  description = "Percentage or number of nodes that can be drained or rebooted concurrently during SR-IOV VF configuration. Use a lower percentage (for example 25%) to maintain cluster availability in production."
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

# Workers - GPU RDMA pool
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
variable "worker_rdma_use_cluster_network" { default = false }
variable "worker_rdma_host_group_id" { default = "" }

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
  validation {
    condition = length(compact([
      for line in split("\n", trimspace(var.worker_gmc_gpu_memory_fabric_ids)) : trimspace(line)
      ])) == length(toset(compact([
        for line in split("\n", trimspace(var.worker_gmc_gpu_memory_fabric_ids)) : trimspace(line)
    ])))
    error_message = "GPU Memory Fabric OCIDs must be unique."
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
  default = "0.18.0"
  type    = string
}

variable "kueue_local_queue_default_namespace" {
  default     = "default"
  type        = string
  description = "The namespace where the Kueue LocalQueue will be created."
}

# Slinky / Slurm Operator
variable "install_slinky" {
  default     = false
  type        = bool
  description = "Install Slinky Slurm Operator and, by default, a Slurm cluster. If no Slurm worker nodesets are enabled, the controller, accounting, login, and identity services still deploy."
}

variable "slinky_advanced_options" {
  default     = false
  type        = bool
  description = "Show advanced Slinky Slurm Operator configuration fields in OCI Resource Manager."
}

variable "slinky_install_slurm_cluster" {
  default     = true
  type        = bool
  description = "Install the Slinky Slurm Helm chart after the Slinky operator is ready."
}

variable "slinky_operator_namespace" {
  default     = "slinky"
  type        = string
  description = "Kubernetes namespace for the Slinky operator and webhook."
}

variable "slinky_slurm_namespace" {
  default     = "slurm"
  type        = string
  description = "Kubernetes namespace for the Slurm cluster resources."
}

variable "slinky_image_profile" {
  default     = "26.05.1-ubuntu26.04"
  type        = string
  description = "Tested Slinky image profile used by auto chart and image tag settings."

  validation {
    condition = contains([
      "25.11.6-ubuntu24.04",
      "26.05-ubuntu24.04",
      "26.05.1-ubuntu26.04",
    ], var.slinky_image_profile)
    error_message = "slinky_image_profile must be one of: 25.11.6-ubuntu24.04, 26.05-ubuntu24.04, 26.05.1-ubuntu26.04."
  }
}

variable "slinky_operator_chart_version" {
  default     = "auto"
  type        = string
  description = "Slinky slurm-operator Helm chart version. Use auto to select the version from slinky_image_profile."
}

variable "slinky_slurm_chart_version" {
  default     = "auto"
  type        = string
  description = "Slinky slurm Helm chart version. Use auto to select the version from slinky_image_profile."
}

variable "slinky_operator_cert_manager_enabled" {
  default     = false
  type        = bool
  description = "Use cert-manager to issue the Slinky webhook certificate. When false, the Slinky chart generates a self-signed webhook certificate."
}

variable "slinky_operator_values_override" {
  default     = ""
  type        = string
  description = "Additional YAML values merged into the Slinky operator Helm release after the generated values."
}

variable "slinky_slurm_values_override" {
  default     = ""
  type        = string
  description = "Additional YAML values merged into the Slinky Slurm Helm release after the generated OKE values."
}

variable "slinky_login_enabled" {
  default     = true
  type        = bool
  description = "Enable a Slinky LoginSet with a LoadBalancer service. Requires slinky_identity_enabled=true so login users resolve through the managed OpenLDAP SSSD configuration."
}

variable "slinky_worker_network_mode" {
  default     = "hostNetwork"
  type        = string
  description = "Network mode for the Slinky RDMA NodeSet. Use virtualFunctions for pod networking with SR-IOV RDMA VFs, or hostNetwork to share the Kubernetes node network namespace. Forced to virtualFunctions when deploy_nvidia_network_operator is true. Standard GPU workers always use pod networking; GMC workers always use hostNetwork."

  validation {
    condition     = contains(["virtualFunctions", "hostNetwork"], var.slinky_worker_network_mode)
    error_message = "slinky_worker_network_mode must be either 'virtualFunctions' or 'hostNetwork'."
  }
}

variable "slinky_worker_mount_infiniband" {
  default     = true
  type        = bool
  description = "Mount /dev/infiniband into Slinky RDMA slurmd pods. GMC workers always mount it and standard GPU workers do not."
}

variable "slinky_worker_ssh_enabled" {
  default     = true
  type        = bool
  description = "Enable sshd in Slinky slurmd pods. Required when slinky_identity_enabled=true because the Slinky slurm chart couples worker SSSD configuration to SSH. When hostNetwork is enabled, sshd listens on port 2222 to avoid conflict with the node sshd."
}

variable "slinky_worker_replicas" {
  default     = null
  type        = number
  description = "Number of Slinky slurmd replicas when overriding the worker NodeSet to StatefulSet. Ignored by the default DaemonSet worker mode."
}

variable "slinky_gpus_per_node" {
  default     = null
  type        = number
  description = "GPUs per Slinky accelerator slurmd pod. Defaults independently to the final numeric component of each pool's worker shape."
}

variable "slinky_worker_rdma_resource" {
  default     = "nvidia.com/rdma-vf"
  type        = string
  description = "Extended resource requested by virtualFunctions Slinky RDMA workers."
}

variable "slinky_worker_rdma_vfs_per_node" {
  default     = null
  type        = number
  description = "Number of SR-IOV RDMA VFs requested by each pod-networked Slinky RDMA worker. Leave null (default) to derive it from the worker shape (the number of RDMA PFs it exposes); set explicitly only to request fewer VFs."

  validation {
    condition     = var.slinky_worker_rdma_vfs_per_node == null ? true : try(var.slinky_worker_rdma_vfs_per_node == floor(var.slinky_worker_rdma_vfs_per_node) && var.slinky_worker_rdma_vfs_per_node > 0, false)
    error_message = "slinky_worker_rdma_vfs_per_node must be a positive integer when set, or null to auto-derive from the worker shape."
  }
}

variable "slinky_worker_rdma_network" {
  default     = "default/rdma-vf"
  type        = string
  description = "Multus NetworkAttachmentDefinition used by pod-networked Slinky RDMA workers. Use namespace/name when the NAD is not in the Slurm namespace."
}

variable "slinky_worker_image_repository" {
  default     = "iad.ocir.io/idxzjcdglx2s/slurm-operator"
  type        = string
  description = "Container image repository for Slinky slurmd pods."
}

variable "slinky_worker_image_tag" {
  default     = "auto"
  type        = string
  description = "Container image tag for Slinky accelerator slurmd pods. Use auto to select NVIDIA NCCL with Pyxis or AMD RCCL with Pyxis. All enabled accelerator pools must use the same GPU vendor."
}

variable "slinky_gpu_autodetect" {
  default     = "auto"
  type        = string
  description = "Slurm gres.conf AutoDetect value. Use auto to select rsmi for AMD GPU shapes and nvml for NVIDIA GPU shapes."
}

variable "slinky_identity_enabled" {
  default     = true
  type        = bool
  description = "Deploy in-cluster HA OpenLDAP and configure SSSD/NSS integration for Slurm controller, login, and worker pods."
}

variable "slinky_home_enabled" {
  default     = true
  type        = bool
  description = "Create a Slurm /home PVC bound to an FSS PersistentVolume and mount it into login and worker pods."
}

variable "slinky_home_pv_name" {
  default     = "fss-pv"
  type        = string
  description = "PersistentVolume name used by the Slurm home PVC. The stack creates fss-pv when create_fss=true."
}

variable "slinky_home_pvc_size" {
  default     = "50Gi"
  type        = string
  description = "Requested size for the Slurm home PVC."
}

variable "slinky_accounting_enabled" {
  default     = true
  type        = bool
  description = "Deploy MariaDB Operator and a MariaDB instance for SlurmDBD accounting."
}

variable "slinky_mariadb_operator_chart_version" {
  default     = "26.6.0"
  type        = string
  description = "MariaDB Operator and CRD Helm chart version."
}

variable "slinky_openldap_namespace" {
  default     = "identity"
  type        = string
  description = "Kubernetes namespace for HA OpenLDAP."
}

variable "slinky_openldap_chart_version" {
  default     = "4.3.3"
  type        = string
  description = "helm-openldap/openldap-stack-ha chart version."
}

variable "slinky_openldap_domain" {
  default     = "example.org"
  type        = string
  description = "LDAP DNS domain used by the bundled OpenLDAP deployment."
}

variable "slinky_openldap_base_dn" {
  default     = "dc=example,dc=org"
  type        = string
  description = "LDAP base DN used by SSSD and the bundled OpenLDAP deployment."
}

variable "slinky_openldap_admin_password" {
  default     = null
  type        = string
  description = "OpenLDAP admin password. Leave unset to generate a unique per-stack password."
  sensitive   = true

  validation {
    condition     = var.slinky_openldap_admin_password == null ? true : length(regexall("[\\r\\n]", var.slinky_openldap_admin_password)) == 0
    error_message = "slinky_openldap_admin_password must not contain newline characters."
  }
}

variable "slinky_openldap_config_password" {
  default     = null
  type        = string
  description = "OpenLDAP cn=config admin password. Leave unset to generate a unique per-stack password."
  sensitive   = true

  validation {
    condition     = var.slinky_openldap_config_password == null ? true : length(regexall("[\\r\\n]", var.slinky_openldap_config_password)) == 0
    error_message = "slinky_openldap_config_password must not contain newline characters."
  }
}

variable "slinky_openldap_primary_replicas" {
  default     = 1
  type        = number
  description = "Number of writable OpenLDAP primary replicas. Keep this at 1 for single writable primary topology."
}

variable "slinky_openldap_readonly_replicas" {
  default     = 2
  type        = number
  description = "Number of read-only OpenLDAP replicas."
}

variable "slinky_openldap_storage_size" {
  default     = "8Gi"
  type        = string
  description = "Persistent storage size for each OpenLDAP pod."
}

variable "slinky_mariadb_storage_size" {
  default     = "16Gi"
  type        = string
  description = "Persistent storage size for the Slurm accounting MariaDB instance."
}

variable "slinky_accounting_image_repository" {
  default     = "auto"
  type        = string
  description = "Container image repository for the SlurmDBD accounting pod. Use auto to select the repository from slinky_image_profile."
}

variable "slinky_accounting_image_tag" {
  default     = "auto"
  type        = string
  description = "Container image tag for the SlurmDBD accounting pod. Use auto to select the tag from slinky_image_profile."
}

variable "slinky_restapi_image_repository" {
  default     = "auto"
  type        = string
  description = "Container image repository for the Slurm REST API pod. Use auto to select the repository from slinky_image_profile."
}

variable "slinky_restapi_image_tag" {
  default     = "auto"
  type        = string
  description = "Container image tag for the Slurm REST API pod. Use auto to select the tag from slinky_image_profile."
}

variable "slinky_controller_image_repository" {
  default     = "iad.ocir.io/idxzjcdglx2s/slurm-operator"
  type        = string
  description = "Container image repository for the Slurm controller pod."
}

variable "slinky_controller_image_tag" {
  default     = "auto"
  type        = string
  description = "Container image tag for the Slurm controller pod. Use auto to select the tag from slinky_image_profile."
}

variable "slinky_login_image_repository" {
  default     = "iad.ocir.io/idxzjcdglx2s/slurm-operator"
  type        = string
  description = "Container image repository for the Slurm login pod."
}

variable "slinky_login_image_tag" {
  default     = "auto"
  type        = string
  description = "Container image tag for the Slurm login pod. Use auto to select the tag from slinky_image_profile."
}

variable "slinky_sssd_image_repository" {
  default     = "auto"
  type        = string
  description = "Container image repository used for the SSSD sidecar. Use auto to select the repository from slinky_image_profile."
}

variable "slinky_sssd_image_tag" {
  default     = "auto"
  type        = string
  description = "Container image tag used for the SSSD sidecar. Use auto to select the tag from slinky_image_profile."
}

variable "slinky_nodeset_name" {
  default     = "gpu"
  type        = string
  description = "Slinky NodeSet and partition name used for the standard GPU worker pool."
}

variable "slinky_rdma_nodeset_name" {
  default     = "rdma"
  type        = string
  description = "Slinky NodeSet and partition name used for the GPU with RDMA worker pool."
}

variable "slinky_gmc_nodeset_name" {
  default     = "gmc"
  type        = string
  description = "Slinky NodeSet and partition name prefix used for GPU Memory Cluster fabrics. A fabric suffix is added when multiple fabrics are configured."
}

variable "slinky_default_partition" {
  default     = "auto"
  type        = string
  description = "Default Slinky partition. Use auto, gpu, rdma, gmc, cpu, all, or an exact generated partition name. With multiple GMC fabrics, gmc selects the aggregate <slinky_gmc_nodeset_name>-all partition. auto prefers GPU, then RDMA, GMC, and CPU."
}

variable "slinky_cpu_worker_enabled" {
  default     = false
  type        = bool
  description = "Run Slurm workers on the CPU worker pool. Requires worker_cpu_enabled."
}

variable "slinky_cpu_nodeset_name" {
  default     = "cpu"
  type        = string
  description = "Slinky nodeset name used for the CPU Slurm worker pool."
}

variable "slinky_cpu_worker_image_repository" {
  default     = ""
  type        = string
  description = "Container image repository for CPU Slurm workers. Empty uses slinky_worker_image_repository."
}

variable "slinky_cpu_worker_image_tag" {
  default     = "auto"
  type        = string
  description = "Container image tag for CPU Slurm workers. auto uses the same image as the GPU workers, which runs fine without GPUs but is large; set a slimmer slurmd tag to speed up pulls on CPU nodes."
}

# OCI HPC OKE Utils
variable "install_oci_hpc_oke_utils" {
  default     = true
  type        = bool
  description = "Install the OCI HPC OKE Utils Helm chart (includes the RDMA/GMC node labeler and image prepuller)."
}

# RDMA topology labeler
variable "install_rdma_labeler" {
  default     = true
  type        = bool
  description = "Deploy the RDMA/GMC labeler DaemonSet to populate topology labels and the GPU memory fabric label used by Slurm GMC NodeSets."
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
