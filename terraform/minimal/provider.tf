provider "oci" {
  config_file_profile = var.config_file_profile
  region              = var.region
  tenancy_ocid        = var.tenancy_id
}

provider "oci" {
  alias               = "home"
  config_file_profile = var.config_file_profile
  region              = var.home_region
  tenancy_ocid        = var.tenancy_id
}