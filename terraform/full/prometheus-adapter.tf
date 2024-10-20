# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  prometheus_adapter_version = one(helm_release.prometheus_adapter[*].version)
  prometheus_adapter_helm_values = {
    podDisruptionBudget = { enabled = true }
    # podLabels           = local.labels_istio_inject
    # podAnnotations      = local.labels_istio_inject
    replicas = 2
    prometheus = {
      url = format(
        "http://prom-kube-prometheus-stack-prometheus.%v.svc.cluster.local",
        var.monitoring_namespace
      )
      port = 9090
      path = ""
    }
    rules = {
      default = true
      custom  = []
      # - seriesQuery: '{__name__=~"^some_metric_count$"}'
      #   resources:
      #     template: <<.Resource>>
      #   name:
      #     matches: ""
      #     as: "my_custom_metric"
      #   metricsQuery: sum(<<.Series>>{<<.LabelMatchers>>}) by (<<.GroupBy>>)

      # Mounts a configMap with pre-generated rules for use. Overrides the
      # default, custom, external and resource entries
      #existing:
      external = []
      # - seriesQuery: '{__name__=~"^some_metric_count$"}'
      #   resources:
      #     template: <<.Resource>>
      #   name:
      #     matches: ""
      #     as: "my_external_metric"
      #   metricsQuery: sum(<<.Series>>{<<.LabelMatchers>>}) by (<<.GroupBy>>)

      resource = {
        cpu = {
          containerLabel = "container"
          containerQuery = "sum by (<<.GroupBy>>) (rate(container_cpu_usage_seconds_total{container!=\"\",<<.LabelMatchers>>}[3m]))"
          nodeQuery      = "sum  by (<<.GroupBy>>) (rate(node_cpu_seconds_total{mode!=\"idle\",mode!=\"iowait\",mode!=\"steal\",<<.LabelMatchers>>}[3m]))"
          resources = {
            overrides = {
              node      = { resource = "node" }
              namespace = { resource = "namespace" }
              pod       = { resource = "pod" }
            }
          }
        }
        memory = {
          containerQuery = "sum by (<<.GroupBy>>) (avg_over_time(container_memory_working_set_bytes{container!=\"\",<<.LabelMatchers>>}[3m]))"
          nodeQuery      = <<-EOT
            sum by (<<.GroupBy>>) (
              avg_over_time(node_memory_MemTotal_bytes{<<.LabelMatchers>>}[3m])
              -
              avg_over_time(node_memory_MemAvailable_bytes{<<.LabelMatchers>>}[3m])
            )
          EOT
          resources = {
            overrides = {
              node      = { resource = "node" }
              namespace = { resource = "namespace" }
              pod       = { resource = "pod" }
            }
          }
          containerLabel = "container"
        }
        window = "3m"
      }
    }
  }

  prometheus_adapter_helm_values_yaml = jsonencode(local.prometheus_adapter_helm_values)
}

resource "helm_release" "prometheus_adapter" {
  count            = var.install_monitoring && var.install_prometheus_adapter ? 1 : 0
  depends_on       = [helm_release.prometheus]
  namespace        = var.monitoring_namespace
  name             = "prometheus-adapter"
  chart            = "prometheus-adapter"
  repository       = "https://prometheus-community.github.io/helm-charts"
  version          = var.prometheus_adapter_chart_version
  create_namespace = false
  recreate_pods    = true
  force_update     = true
  max_history      = 1
  values           = [local.prometheus_adapter_helm_values_yaml]
}
