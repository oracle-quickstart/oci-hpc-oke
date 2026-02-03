# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

data "kubernetes_service" "ingress_lb" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public", local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  depends_on = [time_sleep.wait_for_ingress_lb]

  metadata {
    name      = format("%s-envoy", one(helm_release.ingress.*.name))
    namespace = one(helm_release.ingress.*.namespace)
  }
}

data "oci_load_balancer_load_balancers" "lbs" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public", local.deploy_from_operator]) ? 1 : 0

  compartment_id = var.compartment_ocid

  filter {
    name   = "freeform_tags.state_id"
    values = [local.state_id]
  }

  filter {
    name   = "freeform_tags.application"
    values = ["contour"]
  }

  depends_on = [module.ingress]
}

data "oci_load_balancer_load_balancers" "internal_lbs" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "internal", local.deploy_from_operator]) ? 1 : 0

  compartment_id = var.compartment_ocid

  filter {
    name   = "freeform_tags.state_id"
    values = [local.state_id]
  }

  filter {
    name   = "freeform_tags.application"
    values = ["grafana"]
  }

  depends_on = [module.kube_prometheus_stack]
}