# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

data "oci_containerengine_clusters" "oke" {
  compartment_id = var.compartment_ocid
}

data "kubernetes_nodes" "pool" {
  depends_on = [module.oke]
  metadata {
    labels = {
      "oke.oraclecloud.com/pool.name" = "oke-ops"
    }
  }
}

locals {
  vcn_name                 = format("%v-%v", var.vcn_name, local.state_id)
  cluster_endpoints        = module.oke.cluster_endpoints
  cluster_public_endpoint  = try(format("https://%s", lookup(local.cluster_endpoints, "public_endpoint", null)), null)
  cluster_private_endpoint = try(format("https://%s", lookup(local.cluster_endpoints, "private_endpoint", null)), null)
  cluster_ca_cert          = module.oke.cluster_ca_cert
  cluster_id               = module.oke.cluster_id
  cluster_apiserver        = try(trimspace(module.oke.apiserver_private_host), "")
  cluster_name             = format("%v-%v", var.cluster_name, local.state_id)
  # Kubernetes labels
  labels_gpu_stack = tomap({
    "app.kubernetes.io/part-of" = "oke-gpu-stack"
    "app.kubernetes.io/version" = "1"
  })
  monitoring_version = "1"
  monitoring_labels = merge(local.labels_gpu_stack, tomap({
    "app.kubernetes.io/name"    = var.monitoring_namespace
    "app.kubernetes.io/version" = local.monitoring_version
  }))
  kube_exec_args = concat(
    ["--region", var.region],
    var.oci_profile != null ? ["--profile", var.oci_profile] : [],
    ["ce", "cluster", "generate-token"],
    ["--cluster-id", module.oke.cluster_id],
  )
  # Node resources for Prometheus
  node             = element(tolist(one(data.kubernetes_nodes.pool[*].nodes)), 1)
  node_allocatable = lookup(element(lookup(local.node, "status", [{}]), 1), "allocatable", {})
  node_memory      = lookup(local.node_allocatable, "memory", "8000000Ki")
  node_memory_bytes = (
    length(regexall("Ki$", local.node_memory)) > 0
    ? parseint(trimsuffix(local.node_memory, "Ki"), 10) * 1000
    : parseint(local.node_memory)
  )
  prom_server_memory_request_bytes = (
    length(regexall("%$", var.prom_server_memory_request)) > 0
    ? local.node_memory_bytes * (parseint(trimsuffix(var.prom_server_memory_request, "%"), 10) * 0.01)
    : var.prom_server_memory_request
  )
  prom_server_memory_limit_bytes = (
    length(regexall("%$", var.prom_server_memory_limit)) > 0
    ? local.node_memory_bytes * (parseint(trimsuffix(var.prom_server_memory_limit, "%"), 10) * 0.01)
    : var.prom_server_memory_limit
  )
}

module "oke" {
  source                            = "github.com/oracle-quickstart/oci-hpc-oke.git?ref=5.1.8&depth=1"
  providers                         = { oci.home = oci.home }
  region                            = var.region
  tenancy_id                        = var.tenancy_ocid
  compartment_id                    = var.compartment_ocid
  state_id                          = local.state_id
  assign_public_ip_to_control_plane = true
  allow_bastion_cluster_access      = true
  allow_node_port_access            = true
  allow_worker_internet_access      = true
  allow_worker_ssh_access           = true
  assign_dns                        = true
  bastion_allowed_cidrs             = flatten(tolist([var.bastion_allowed_cidrs]))
  bastion_await_cloudinit           = false
  bastion_is_public                 = true
  bastion_image_type                = "platform"
  bastion_image_os                  = "Canonical Ubuntu" # Ignored when bastion_image_type = "custom"
  bastion_image_os_version          = "22.04"
  bastion_user                      = "ubuntu"
  bastion_shape = {
    shape = var.bastion_shape, ocpus = 4, memory = 16, boot_volume_size = 50
  }
  bastion_upgrade             = false
  cluster_name                = local.cluster_name
  cluster_type                = "enhanced"
  cni_type                    = "flannel"
  control_plane_allowed_cidrs = flatten(tolist([var.control_plane_allowed_cidrs]))
  control_plane_is_public     = true
  create_bastion              = var.create_bastion
  create_cluster              = true
  create_iam_defined_tags     = false
  create_iam_resources        = false
  create_iam_tag_namespace    = false
  create_operator             = var.create_operator
  create_vcn                  = var.create_vcn
  kubernetes_version          = var.kubernetes_version
  load_balancers              = "internal"
  lockdown_default_seclist    = true
  # TODO input variable + schema for image selection
  #operator_image_type         = "custom"
  #operator_image_id = data.oci_core_images.linux.images.0.id
  operator_image_type                = "platform"
  operator_image_os                  = "Canonical Ubuntu" # Ignored when bastion_image_type = "custom"
  operator_image_os_version          = "22.04"
  operator_user                      = "ubuntu"
  operator_await_cloudinit           = false
  operator_install_oci_cli           = true
  operator_install_kubectl_from_repo = true
  operator_install_helm              = true
  operator_install_k9s               = true
  operator_install_kubectx           = true
  operator_shape = {
    shape            = var.operator_shape_name
    ocpus            = var.operator_shape_ocpus
    memory           = var.operator_shape_memory
    boot_volume_size = var.operator_shape_boot
  }
  output_detail = true
  pods_cidr     = "10.240.0.0/12" # TODO input var (but keep expanded default)
  # services_cidr                     = "10.96.0.0/16"
  #preferred_load_balancer           = "internal"
  ssh_public_key                    = trimspace(var.ssh_public_key)
  use_defined_tags                  = false
  vcn_cidrs                         = split(",", var.vcn_cidrs)
  vcn_create_internet_gateway       = "always"
  vcn_create_nat_gateway            = "always"
  vcn_create_service_gateway        = "always"
  vcn_id                            = var.vcn_id
  vcn_name                          = local.vcn_name
  worker_disable_default_cloud_init = true
  worker_is_public                  = false
  worker_pools                      = local.worker_pools
  subnets = {
    bastion  = { create = "always", newbits = 13 }
    cp       = { create = "always", newbits = 13 }
    operator = { create = "always", newbits = 13 }
    int_lb   = { create = "always", newbits = 11 }
    pub_lb   = { create = "always", newbits = 11 }
    fss      = { create = "always", newbits = 11 }
    workers  = { create = "always", newbits = 4 }
  }
  nsgs = {
    bastion  = { create = "always" }
    cp       = { create = "always" }
    operator = { create = "always" }
    int_lb   = { create = "always" }
    pub_lb   = { create = "always" }
    fss      = { create = "always" }
    workers  = { create = "always" }
  }
  allow_rules_internal_lb = {
    "Allow TCP ingress to internal load balancers from internal VCN/DRG" = {
      protocol = "all", port = -1, source = "10.0.0.0/8", source_type = "CIDR_BLOCK",
    }
  }
}
