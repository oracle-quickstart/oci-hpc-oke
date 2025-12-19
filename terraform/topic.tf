# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "oci_ons_notification_topic" "grafana_alerts" {
  count =  alltrue([var.create_cluster, var.install_monitoring, var.setup_alerting, var.install_node_problem_detector_kube_prometheus_stack]) ? 1 : 0

  compartment_id = var.compartment_ocid
  name           = format("oke-grafana-alerts-%v", local.state_id)

  description    = "Notification Topic used for OKE Grafana Alerts of the cluster: ${format("%v-%v", var.cluster_name, local.state_id)}"

  lifecycle {
    ignore_changes = [defined_tags]
  }
}