# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      configuration_aliases = [oci.home]
      source                = "oracle/oci"
      version               = ">= 7.16.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.3"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl" # https://github.com/hashicorp/terraform-provider-kubernetes/issues/1782#issuecomment-1687357821
      version = "~> 1.19"             # https://github.com/hashicorp/terraform-provider-kubernetes/issues/1391
    }
  }
}
