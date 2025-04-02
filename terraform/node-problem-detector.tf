resource "helm_release" "node-problem_detector" {
  count             = var.install_node_problem_detector_kube_prometheus_stack ? 1 : 0
  depends_on        = [helm_release.prometheus]
  namespace         = var.monitoring_namespace
  name              = "gpu-rdma-node-problem-detector"
  chart             = "node-problem-detector"
  repository        = "oci://ghcr.io/deliveryhero/helm-charts"
  version           = var.node_problem_detector_chart_version
  values            = ["${file("./files/node-problem-detector/values.yaml")}"]
  create_namespace  = true
  recreate_pods     = true
  force_update      = true
  dependency_update = true
  wait              = false
  max_history       = 1
}
