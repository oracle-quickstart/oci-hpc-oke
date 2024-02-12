variable "config_file_profile" { type = string }
variable "home_region" { type = string }
variable "region" { type = string }
variable "tenancy_id" { type = string }
variable "compartment_id" { type = string }
variable "ssh_public_key_path" { type = string }
variable "ssh_private_key_path" { type = string }

variable system_pool_image { default = "ocid1.image.oc1.ap-osaka-1.aaaaaaaaevy2p4nljkr3rzqo4fxkial5zq27slz2f5pwsj3klwqmkarlqdaa" }
variable a100_image { default = "ocid1.image.oc1.ap-osaka-1.aaaaaaaab45fxm72yi3to46ik6vmhestzny3qwsgk2mpvg7uvoidva6eqoqq" }
variable a100_shape { default = "BM.GPU.B4.8" }
variable kubernetes_version { default = "v1.27.2" }
variable cluster_type { default = "enhanced" }
variable cluster_name { default = "a100-cluster" }
variable cni_type {default = "flannel"}
