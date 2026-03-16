# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

data "oci_objectstorage_namespace" "cluster_healthchecks" {
  count          = var.install_cluster_healthchecks ? 1 : 0
  compartment_id = var.tenancy_ocid
}

resource "oci_objectstorage_bucket" "cluster_healthchecks" {
  count          = var.install_cluster_healthchecks ? 1 : 0
  compartment_id = var.compartment_ocid
  namespace      = one(data.oci_objectstorage_namespace.cluster_healthchecks[*].namespace)
  name           = format("cluster-health-checks-%s", local.state_id)
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = "Disabled"
}

locals {
  cluster_healthchecks_results_bucket_name = try(one(oci_objectstorage_bucket.cluster_healthchecks[*].name), null)
  cluster_healthchecks_results_namespace   = try(one(data.oci_objectstorage_namespace.cluster_healthchecks[*].namespace), null)
}
