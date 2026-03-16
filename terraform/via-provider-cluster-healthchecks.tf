# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "cluster_healthchecks" {
  count = alltrue([var.install_cluster_healthchecks, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  name             = "cluster-healthchecks"
  namespace        = var.cluster_healthchecks_namespace
  chart            = "${path.module}/files/cluster-healthchecks"
  create_namespace = true
  force_update     = true
  wait             = true
  max_history      = 1

  values = [
    yamlencode(
      {
        image = {
          repository = var.cluster_healthchecks_image_repository
          tag        = var.cluster_healthchecks_image_tag
          pullPolicy = var.cluster_healthchecks_image_pull_policy
          pullSecrets = [for s in var.cluster_healthchecks_image_pull_secrets : { name = s }]
        }
        passive = {
          enabled  = true
          verbose  = var.cluster_healthcheck_verbose
        }
        results = {
          mountPath  = "/results"
          bucketName = local.cluster_healthchecks_results_bucket_name
          namespace  = local.cluster_healthchecks_results_namespace
        }
      }
    )
  ]
}
