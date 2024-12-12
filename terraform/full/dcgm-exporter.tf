# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  dcgm_exporter_version = one(helm_release.dcgm_exporter[*].version)
}

resource "helm_release" "dcgm_exporter" {
  count             = var.install_dcgm_exporter && var.install_monitoring ? 1 : 0
  depends_on        = [helm_release.prometheus]
  namespace         = var.monitoring_namespace
  name              = "dcgm-exporter"
  chart             = "dcgm-exporter"
  repository        = "https://nvidia.github.io/dcgm-exporter/helm-charts"
  version           = var.dcgm_exporter_chart_version
  values            = ["${file("./files/kube-dcgm-exporter-values.yaml")}"]
  create_namespace  = false
  recreate_pods     = true
  force_update      = true
  dependency_update = true
  wait              = false
  max_history       = 1
}
