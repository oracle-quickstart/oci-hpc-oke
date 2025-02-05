module "oke" {
  source  = "oracle-terraform-modules/oke/oci"
  version = "5.1.8"

  # Provider
  providers           = { oci.home = oci.home }
  config_file_profile = var.config_file_profile
  home_region         = var.home_region
  region              = var.region
  tenancy_id          = var.tenancy_id
  compartment_id      = var.compartment_id
  ssh_public_key_path = var.ssh_public_key_path
  ssh_private_key_path = var.ssh_private_key_path
  
  kubernetes_version = var.kubernetes_version
  cluster_type = var.cluster_type
  cluster_addons = {
    "NvidiaGpuPlugin" = {
      remove_addon_resources_on_delete = true
      override_existing                = true
      configurations = []
    }
  }    
  bastion_allowed_cidrs = ["0.0.0.0/0"]
  allow_worker_ssh_access     = true
  control_plane_allowed_cidrs = ["0.0.0.0/0"]

  control_plane_is_public = true
  
  # Resource creation
  assign_dns           = true
  create_vcn           = true
  create_bastion       = true
  create_cluster       = true
  create_operator      = true
  create_iam_resources = true
  use_defined_tags     = false

  worker_pools = {
    operational = {
      description = "Operational pool", enabled = true,
      disable_default_cloud_init=true,
      mode        = "node-pool",
      image_type = "custom",
      image_id = var.operational_pool_image,
      boot_volume_size = 150,
      shape = "VM.Standard.E4.Flex",
      ocpus = 16,
      memory = 64,
      size = 3,
      cloud_init = [{ content = "./cloud-init/ubuntu.sh" }],
  }

   gpu = {
     description = "GPU pool", enabled = true,
     disable_default_cloud_init=true,
     mode        = "cluster-network",
     size = 2,
     shape = var.gpu_shape
     boot_volume_size = 250,
     placement_ads = [1],
     image_type = "custom",
     image_id = var.gpu_image,
     node_labels = { "oci.oraclecloud.com/disable-gpu-device-plugin" : "true" },
     cloud_init = [{ content = "./cloud-init/ubuntu.sh" }],
     agent_config = {
        are_all_plugins_disabled = false,
        is_management_disabled   = false,
        is_monitoring_disabled   = false,
        plugins_config = {
          "Compute HPC RDMA Authentication"     = "ENABLED",
          "Compute HPC RDMA Auto-Configuration" = "ENABLED",
          "Compute Instance Monitoring"         = "ENABLED",
          "Compute Instance Run Command"        = "ENABLED",
          "Compute RDMA GPU Monitoring"         = "DISABLED",
          "Custom Logs Monitoring"              = "ENABLED",
          "Management Agent"                    = "ENABLED",
          "Oracle Autonomous Linux"             = "DISABLED",
          "OS Management Service Agent"         = "DISABLED",
        }
      }
    }
  }
}