# # Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# # Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "helm_release" "prometheus" {
  count = var.install_node_problem_detector_kube_prometheus_stack ? 1 : 0
  depends_on = [
    module.oke,
    time_sleep.wait_for_lb_termination
  ]
  namespace         = var.monitoring_namespace
  name              = "kube-prometheus-stack"
  chart             = "kube-prometheus-stack"
  repository        = "https://prometheus-community.github.io/helm-charts"
  version           = var.prometheus_stack_chart_version
  values            = ["${file("./files/kube-prometheus/values.yaml")}"]
  create_namespace  = true
  recreate_pods     = false
  force_update      = true
  dependency_update = true
  wait              = true
  max_history       = 1
  set_sensitive {
    name  = "grafana.adminPassword"
    value = random_password.grafana_admin_password.result
  }
}

resource "time_sleep" "wait_for_lb_termination" {
  destroy_duration = "60s"
}