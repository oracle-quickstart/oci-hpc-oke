# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

data "oci_identity_region_subscriptions" "home" {
  tenancy_id = var.tenancy_ocid
  filter {
    name   = "is_home_region"
    values = [true]
  }
}

provider "oci" {
  alias               = "home"
  auth                = try(replace(var.oci_auth, "_", ""), null)
  config_file_profile = var.oci_profile
  fingerprint         = var.api_fingerprint
  region              = try(one(data.oci_identity_region_subscriptions.home.region_subscriptions[*].region_name), var.region)
  tenancy_ocid        = var.tenancy_ocid
  user_ocid           = var.current_user_ocid
}

provider "oci" {
  auth                = try(replace(var.oci_auth, "_", ""), null)
  config_file_profile = var.oci_profile
  fingerprint         = var.api_fingerprint
  region              = var.region
  tenancy_ocid        = var.tenancy_ocid
  user_ocid           = var.current_user_ocid
}

provider "helm" {
  kubernetes {
    host                   = local.cluster_public_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca_cert)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "oci"
      args        = local.kube_exec_args
    }
  }
}

provider "kubernetes" {
  host                   = local.cluster_public_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca_cert)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "oci"
    args        = local.kube_exec_args
  }
}
