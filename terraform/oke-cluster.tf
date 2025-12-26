# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

data "oci_containerengine_clusters" "oke" {
  compartment_id = var.compartment_ocid
}

locals {

  deploy_from_operator = alltrue([var.create_bastion, var.create_operator, !var.control_plane_is_public, !var.deploy_to_oke_from_orm])
  deploy_from_local    = alltrue([!local.deploy_from_operator, var.control_plane_is_public, !var.deploy_to_oke_from_orm])
  deploy_from_orm      = alltrue([var.current_user_ocid != null, var.deploy_to_oke_from_orm])

  vcn_name = format("%v-%v", var.vcn_name, local.state_id)

  cluster_endpoints        = module.oke.cluster_endpoints
  cluster_public_endpoint  = try(format("https://%s", lookup(local.cluster_endpoints, "public_endpoint", "not-defined")), "not-defined")
  cluster_private_endpoint = try(format("https://%s", lookup(local.cluster_endpoints, "private_endpoint", "not-defined")), "not-defined")
  cluster_orm_endpoint     = try(format("https://%s:6443", one(data.oci_resourcemanager_private_endpoint_reachable_ip.oke.*.ip_address)), "not-defined")

  cluster_ca_cert = module.oke.cluster_ca_cert 

  cluster_id        = module.oke.cluster_id
  cluster_apiserver = try(trimspace(module.oke.apiserver_private_host), "")
  cluster_name      = format("%v-%v", var.cluster_name, local.state_id)

  kube_exec_args = concat(
    ["--region", var.region],
    var.oci_profile != null ? ["--profile", var.oci_profile] : [],
    ["ce", "cluster", "generate-token"],
    ["--cluster-id", module.oke.cluster_id],
  )

  nsgs = merge(
    {
      bastion  = var.create_bastion ? { create = "auto" } : { create = "never"}
      operator = var.create_operator ? { create = "auto" } : { create = "never"}
      int_lb   = { create = "auto" }
      pub_lb   = { create = "auto" }
      cp       = { create = "auto" }
      workers  = { create = "auto" }
      pods     = { create = "auto" }
    },
    var.create_fss ? {
      fss = { create = "always" }
    } : {}
  )

  subnets = merge(
    {
      bastion = merge(
        var.create_bastion ? { create = "auto" } : { create = "never" },
        (var.create_vcn && var.bastion_sn_cidr == null) || (!var.create_vcn && !var.custom_subnet_ids) ?
        { newbits = 13, netnum = 1 } : {},
        var.create_vcn && var.bastion_sn_cidr != null ?
        { cidr = var.bastion_sn_cidr } : {},
        !var.create_vcn && var.custom_subnet_ids ?
        { id = var.bastion_sn_id, create = "never" } : {},
        lookup(var.subnet_advanced_attrs, "bastion", {})
      )
      operator = merge(
        var.create_operator ? { create = "auto" } : { create = "never" },
        (var.create_vcn && var.operator_sn_cidr == null) || (!var.create_vcn && !var.custom_subnet_ids) ?
        { newbits = 13, netnum = 2 } : {},
        var.create_vcn && var.operator_sn_cidr != null ?
        { cidr = var.operator_sn_cidr } : {},
        !var.create_vcn && var.custom_subnet_ids ?
        { id = var.operator_sn_id, create = "never" } : {},
        lookup(var.subnet_advanced_attrs, "operator", {})
      )
      int_lb = merge(
        { create = "auto" },
        (var.create_vcn && var.int_lb_sn_cidr == null) || (!var.create_vcn && !var.custom_subnet_ids) ?
        { newbits = 11, netnum = 1 } : {},
        var.create_vcn && var.int_lb_sn_cidr != null ?
        { cidr = var.int_lb_sn_cidr } : {},
        !var.create_vcn && var.custom_subnet_ids ?
        { id = var.int_lb_sn_id, create = "never" } : {},
        lookup(var.subnet_advanced_attrs, "int_lb", {})
      )
      pub_lb = merge(
        { create = "auto" },
        (var.create_vcn && var.pub_lb_sn_cidr == null) || (!var.create_vcn && !var.custom_subnet_ids) ?
        { newbits = 11, netnum = 2 } : {},
        var.create_vcn && var.pub_lb_sn_cidr != null ?
        { cidr = var.pub_lb_sn_cidr } : {},
        !var.create_vcn && var.custom_subnet_ids ?
        { id = var.pub_lb_sn_id, create = "never" } : {},
        lookup(var.subnet_advanced_attrs, "pub_lb", {})
      )
      cp = merge(
        { create = "auto" },
        (var.create_vcn && var.cp_sn_cidr == null) || (!var.create_vcn && !var.custom_subnet_ids) ?
        { newbits = 13, netnum = 0 } : {},
        var.create_vcn && var.cp_sn_cidr != null ?
        { cidr = var.cp_sn_cidr } : {},
        !var.create_vcn && var.custom_subnet_ids ?
        { id = var.cp_sn_id, create = "never" } : {},
        lookup(var.subnet_advanced_attrs, "cp", {})
      )
      workers = merge(
        { create = "auto" },
        (var.create_vcn && var.workers_sn_cidr == null) || (!var.create_vcn && !var.custom_subnet_ids) ?
        { newbits = 4, netnum = 2 } : {},
        var.create_vcn && var.workers_sn_cidr != null ?
        { cidr = var.workers_sn_cidr } : {},
        !var.create_vcn && var.custom_subnet_ids ?
        { id = var.workers_sn_id, create = "never" } : {},
        lookup(var.subnet_advanced_attrs, "workers", {})
      )
      pods = merge(
        { create = "auto" },
        (var.create_vcn && var.pods_sn_cidr == null) || (!var.create_vcn && !var.custom_subnet_ids) ?
        { newbits = 2, netnum = 2 } : {},
        var.create_vcn && var.pods_sn_cidr != null ?
        { cidr = var.pods_sn_cidr } : {},
        !var.create_vcn && var.custom_subnet_ids ?
        { id = var.pods_sn_id, create = "never" } : {},
        lookup(var.subnet_advanced_attrs, "pods", {})
      )
    },
    var.create_fss ? {
      fss = merge(
        { create = "always" },
        (var.create_vcn && var.fss_sn_cidr == null) || (!var.create_vcn && !var.custom_subnet_ids) ?
        { newbits = 11, netnum = 3 } : {},
        var.create_vcn && var.fss_sn_cidr != null ?
        { cidr = var.fss_sn_cidr } : {},
        !var.create_vcn && var.custom_subnet_ids ?
        { id = var.fss_sn_id, create = "never" } : {},
        lookup(var.subnet_advanced_attrs, "fss", {})
      )
    } : {},
    var.create_lustre ? {
      lustre = merge(
        { create = "always" },
        (var.create_vcn && var.lustre_sn_cidr == null) || (!var.create_vcn && !var.custom_subnet_ids) ?
        { newbits = 7, netnum = 1 } : {},
        var.create_vcn && var.lustre_sn_cidr != null ?
        { cidr = var.lustre_sn_cidr } : {},
        !var.create_vcn && var.custom_subnet_ids ?
        { id = var.lustre_sn_id, create = "never" } : {},
        lookup(var.subnet_advanced_attrs, "lustre", {})
      )
    } : {}
  )

  cni_type = var.cni_type == "VCN-Native Pod Networking" ? "npn" : "flannel"
  nodes_supported_pods = flatten([
    anytrue([strcontains(var.worker_ops_shape, "Flex"), strcontains(var.worker_ops_shape, "Generic")]) ?
    [var.worker_ops_ocpus <= 2 ? 31 : (var.worker_ops_ocpus - 1) * 31] : [var.max_pods_per_node],
    var.worker_cpu_enabled && anytrue([strcontains(var.worker_cpu_shape, "Flex"), strcontains(var.worker_cpu_shape, "Generic")]) ?
    [var.worker_cpu_ocpus <= 2 ? 31 : (var.worker_cpu_ocpus - 1) * 31] : [var.max_pods_per_node],
    [110]
  ])

  pods_per_node = local.cni_type == "flannel" ? var.max_pods_per_node : min(local.nodes_supported_pods...)
}

module "oke" {
  source  = "oracle-terraform-modules/oke/oci"
  version = "5.3.3"

  providers = { oci.home = oci.home }

  region         = var.region
  tenancy_id     = var.tenancy_ocid
  compartment_id = var.compartment_ocid
  state_id       = local.state_id

  assign_public_ip_to_control_plane = var.create_public_subnets ? var.control_plane_is_public : false

  allow_bastion_cluster_access = true
  allow_node_port_access       = true
  allow_worker_internet_access = true
  allow_worker_ssh_access      = true
  assign_dns                   = true
  bastion_allowed_cidrs        = flatten(tolist([var.bastion_allowed_cidrs]))
  bastion_await_cloudinit      = false
  bastion_is_public            = var.create_public_subnets ? var.bastion_is_public : false
  bastion_image_type           = var.bastion_image_type
  bastion_image_os             = var.bastion_image_os
  bastion_image_os_version     = var.bastion_image_os_version
  bastion_user                 = var.bastion_user
  bastion_shape = {
    shape            = var.bastion_shape_name,
    ocpus            = var.bastion_shape_ocpus,
    memory           = var.bastion_shape_memory,
    boot_volume_size = 50
  }
  bastion_upgrade = false

  cluster_name = local.cluster_name
  cluster_type = "enhanced"
  cluster_addons = merge(
    {
      "NvidiaGpuPlugin" = {
        remove_addon_resources_on_delete = true
        override_existing                = true
        configurations = [
          {
            key   = "isDcgmExporterDisabled"
            value = "true"
          }
        ]
      }
    },
    # var.install_monitoring && var.install_node_problem_detector_kube_prometheus_stack ?
    # {
    #   "KubernetesMetricsServer" = {
    #     remove_addon_resources_on_delete = true
    #     override_existing                = true
    #     skipAddonDependenciesCheck = true
    #   }
    # } : {},
    var.create_cluster && var.install_monitoring && var.install_node_problem_detector_kube_prometheus_stack && var.preferred_kubernetes_services == "public" ?
    {
      "CertManager" = {
        remove_addon_resources_on_delete = true
        override_existing                = true
      }
    } : {},
    anytrue([
      var.worker_rdma_shape == "BM.GPU.MI300X.8",
      var.worker_gpu_shape == "BM.GPU.MI300X.8"
      ]) ? {
      "AmdGpuPlugin" = {
        remove_addon_resources_on_delete = true
        override_existing                = true
      }
    } : {}
  )
  cni_type                           = local.cni_type
  control_plane_allowed_cidrs        = flatten(tolist([var.control_plane_allowed_cidrs]))
  control_plane_is_public            = var.control_plane_is_public
  create_bastion                     = var.create_bastion
  create_cluster                     = var.create_cluster
  create_iam_defined_tags            = false
  create_iam_resources               = false
  create_iam_tag_namespace           = false
  create_operator                    = var.create_cluster ? var.create_operator : false 
  create_vcn                         = var.create_vcn
  kubernetes_version                 = var.kubernetes_version
  load_balancers                     = var.create_public_subnets ? "both" : "internal"
  lockdown_default_seclist           = true
  max_pods_per_node                  = local.pods_per_node
  operator_image_type                = var.operator_image_type
  operator_image_os                  = var.operator_image_os # Ignored when bastion_image_type = "custom"
  operator_image_os_version          = var.operator_image_os_version
  operator_user                      = var.operator_user
  operator_await_cloudinit           = local.deploy_from_operator ? true : false
  operator_install_kubectl_from_repo = var.create_operator
  operator_install_helm_from_repo    = var.create_operator
  operator_install_oci_cli_from_repo = var.create_operator
  operator_install_k9s               = var.create_operator
  operator_install_kubectx           = var.create_operator
  operator_shape = {
    shape            = var.operator_shape_name
    ocpus            = var.operator_shape_ocpus
    memory           = var.operator_shape_memory
    boot_volume_size = var.operator_shape_boot
  }
  output_detail = true
  pods_cidr     = "10.240.0.0/12"
  # services_cidr                     = "10.96.0.0/16"
  preferred_load_balancer           = var.preferred_kubernetes_services
  ssh_public_key                    = trimspace(local.ssh_public_key)
  ssh_private_key                   = local.deploy_from_operator ? tls_private_key.stack_key.private_key_openssh : null
  use_defined_tags                  = false
  vcn_cidrs                         = split(",", var.vcn_cidrs)
  vcn_create_internet_gateway       = var.create_public_subnets ? "auto" : "never"
  vcn_create_nat_gateway            = "auto"
  vcn_create_service_gateway        = "auto"
  nat_route_table_id                = var.private_subnet_route_table
  ig_route_table_id                 = var.public_subnet_route_table
  vcn_id                            = var.vcn_id
  vcn_name                          = local.vcn_name
  worker_disable_default_cloud_init = true
  worker_is_public                  = false
  worker_pools                      = local.worker_pools
  subnets                           = local.subnets
  nsgs                              = local.nsgs

  allow_rules_internal_lb = {
    "Allow TCP ingress to internal load balancers from internal VCN/DRG" = {
      protocol = "all", port = -1, source = local.vcn_cidr, source_type = "CIDR_BLOCK",
    }
  }

  allow_rules_public_lb = alltrue([var.create_cluster,var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public"]) ? {
    "Allow TCP ingress from anywhere to HTTP port" = {
      protocol = "6", port = 80, source = "0.0.0.0/0", source_type = "CIDR_BLOCK",
    },
    "Allow TCP ingress from anywhere to HTTPS port" = {
      protocol = "6", port = 443, source = "0.0.0.0/0", source_type = "CIDR_BLOCK",
    }
  } : {}

  allow_rules_workers = var.create_lustre ? {
    "Allow ingress for Lustre SVC from lustre subnet" = {
      protocol = "6", source_port_min = 512, source_port_max = 1023, destination_port_min = 988, destination_port_max = 988, source = local.lustre_subnet_cidr, source_type = "CIDR_BLOCK",
    }
    "Allow egress for Lustre SVC to lustre subnet" = {
      protocol = "6", source_port_min = 512, source_port_max = 1023, destination_port_min = 988, destination_port_max = 988, destination = local.lustre_subnet_cidr, destination_type = "CIDR_BLOCK",
    }
  } : {}

  depends_on = [
    null_resource.validate_bastion_networking, null_resource.validate_cluster_endpoint, null_resource.validate_cluster_services
  ]
}
