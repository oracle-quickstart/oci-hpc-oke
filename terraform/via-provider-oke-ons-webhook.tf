# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "oke-ons-webhook" {
  count             = alltrue([var.create_cluster, var.install_monitoring, var.setup_alerting, var.install_node_problem_detector_kube_prometheus_stack, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on        = [helm_release.prometheus]
  namespace         = var.monitoring_namespace
  name              = "oke-ons-webhook"
  chart             = "${path.module}/files/oke-ons-webhook"
  version           = var.oke_ons_webhook_chart_version
  set              = [
    {
      name  = "deploy.env.ONS_TOPIC_OCID"
      value = try(oci_ons_notification_topic.grafana_alerts[0].id, "")
    },
    {
      name  = "deploy.env.GRAFANA_INITIAL_PASSWORD"
      value = base64encode(random_password.grafana_admin_password[0].result)
    },
    {
      name  = "deploy.env.GRAFANA_SERVICE_URL"
      value = "http://kube-prometheus-stack-grafana"
    }
  ]
  create_namespace  = false
  recreate_pods     = true
  force_update      = true
  dependency_update = true
  wait              = false
  max_history       = 1
}
