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

variable "install_nvidia_dcgm_exporter" {
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

variable "monitoring_namespace" {
  default = "monitoring"
  type    = string
}

variable "node_problem_detector_chart_version" {
  default = "2.4.0"
  type    = string
}

variable "prometheus_stack_chart_version" {
  default = "81.6.3"
  type    = string
}

variable "dcgm_exporter_chart_version" {
  default = "4.8.1"
  type    = string
}

variable "amd_device_metrics_exporter_chart_version" {
  default = "v1.4.1"
  type    = string
}

variable "cert_manager_chart_version" {
  default = "v1.19.2"
  type    = string
}

variable "ingress_chart_version" {
  default = "0.2.1"
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
  default     = false
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

variable "nvidia_gpu_operator_addon_version" {
  type        = string
  default     = "v25.3.4"
  description = "Version of the NvidiaGpuOperator OKE addon."
}

variable "nvidia_gpu_operator_disable_plugin" {
  type        = bool
  default     = true
  description = "Disable the NvidiaGpuPlugin when using the GPU Operator addon."
}

variable "nvidia_gpu_operator_cdi_enabled" {
  type        = bool
  default     = true
  description = "Enable CDI (Container Device Interface) in the GPU Operator addon."
}

variable "nvidia_gpu_operator_toolkit_enabled" {
  type        = bool
  default     = false
  description = "Enable the NVIDIA container toolkit in the GPU Operator addon."
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

# Kueue
variable "install_kueue" {
  default     = true
  type        = bool
  description = "Install Kueue and create Topology Aware Scheduling resources (Topology, ResourceFlavor, ClusterQueue, LocalQueue). Requires worker_rdma_enabled."
}

variable "kueue_chart_version" {
  default = "0.16.3"
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