# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  deploy_coredns_addon_override = local.total_worker_nodes > 50

  nvidia_gpu_operator_namespace         = "gpu-operator"
  nvidia_dcgm_exporter_metrics_config   = lookup(var.nvidia_gpu_operator_configuration, "dcgmExporter.config.name", "metrics-config")
  nvidia_dcgm_exporter_metrics_filename = "dcgm-metrics.csv"
  nvidia_dcgm_exporter_metrics          = file("${path.module}/files/nvidia-gpu-operator/${local.nvidia_dcgm_exporter_metrics_filename}")
  configure_nvidia_dcgm_metrics = alltrue([
    var.deploy_nvidia_gpu_operator,
    lookup(var.nvidia_gpu_operator_configuration, "dcgmExporter.enabled", "true") == "true",
    local.nvidia_dcgm_exporter_metrics_config != "",
  ])
  nvidia_dcgm_exporter_metrics_env = jsonencode(concat(
    [
      for env in try(jsondecode(lookup(var.nvidia_gpu_operator_configuration, "dcgmExporter.env", "[]")), []) : env
      if try(env.name, "") != "DCGM_EXPORTER_COLLECTORS"
    ],
    [{
      name  = "DCGM_EXPORTER_COLLECTORS"
      value = "/etc/dcgm-exporter/${local.nvidia_dcgm_exporter_metrics_filename}"
    }]
  ))
  nvidia_dcgm_exporter_service_monitor_additional_labels = try(
    jsondecode(lookup(var.nvidia_gpu_operator_configuration, "dcgmExporter.serviceMonitor.additionalLabels", "")),
    { release = "kube-prometheus-stack" },
  )
  nvidia_dcgm_exporter_service_monitor_default_relabelings = [
    {
      action       = "replace"
      sourceLabels = ["__meta_kubernetes_pod_node_name"]
      targetLabel  = "hostname"
    },
    {
      action       = "replace"
      sourceLabels = ["__meta_kubernetes_node_label_node_kubernetes_io_instance_type"]
      targetLabel  = "instance_shape"
    },
    {
      action       = "replace"
      sourceLabels = ["__meta_kubernetes_node_label_oci_oraclecloud_com_host_serial_number"]
      targetLabel  = "host_serial_number"
    },
    {
      action       = "replace"
      sourceLabels = ["__meta_kubernetes_node_label_displayName"]
      targetLabel  = "oci_name"
    }
  ]
  nvidia_dcgm_exporter_service_monitor_relabelings = try(
    jsondecode(lookup(var.nvidia_gpu_operator_configuration, "dcgmExporter.serviceMonitor.relabelings", "")),
    local.nvidia_dcgm_exporter_service_monitor_default_relabelings,
  )
  nvidia_dcgm_exporter_service_monitor_interval     = lookup(var.nvidia_gpu_operator_configuration, "dcgmExporter.serviceMonitor.interval", "15s")
  nvidia_dcgm_exporter_service_monitor_honor_labels = lookup(var.nvidia_gpu_operator_configuration, "dcgmExporter.serviceMonitor.honorLabels", "false") == "true"
  nvidia_dcgm_exporter_service_monitor_manifest = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "nvidia-dcgm-exporter"
      namespace = local.nvidia_gpu_operator_namespace
      labels    = local.nvidia_dcgm_exporter_service_monitor_additional_labels
    }
    spec = {
      attachMetadata = {
        node = true
      }
      selector = {
        matchLabels = {
          app = "nvidia-dcgm-exporter"
        }
      }
      namespaceSelector = {
        matchNames = [local.nvidia_gpu_operator_namespace]
      }
      endpoints = [
        {
          port          = "gpu-metrics"
          path          = "/metrics"
          interval      = local.nvidia_dcgm_exporter_service_monitor_interval
          scrapeTimeout = local.nvidia_dcgm_exporter_service_monitor_interval
          honorLabels   = local.nvidia_dcgm_exporter_service_monitor_honor_labels
          relabelings   = local.nvidia_dcgm_exporter_service_monitor_relabelings
        }
      ]
    }
  })
  nvidia_dcgm_exporter_metrics_addon_configurations = local.configure_nvidia_dcgm_metrics ? {
    "dcgmExporter.config.name"                     = local.nvidia_dcgm_exporter_metrics_config
    "dcgmExporter.env"                             = local.nvidia_dcgm_exporter_metrics_env
    "dcgmExporter.serviceMonitor.enabled"          = "false"
    "dcgmExporter.serviceMonitor.interval"         = local.nvidia_dcgm_exporter_service_monitor_interval
    "dcgmExporter.serviceMonitor.additionalLabels" = jsonencode(local.nvidia_dcgm_exporter_service_monitor_additional_labels)
    "dcgmExporter.serviceMonitor.relabelings"      = jsonencode(local.nvidia_dcgm_exporter_service_monitor_relabelings)
  } : {}

  coredns_addon_configurations = [
    {
      key   = "minReplica"
      value = tostring(min(3, max(1, var.worker_ops_pool_size)))
    },
    {
      key   = "nodesPerReplica"
      value = "8"
    },
    {
      key   = "coreDnsContainerResources"
      value = jsonencode({ requests = { cpu = "200m", memory = "300Mi" }, limits = { memory = "1Gi" } })
    },
    {
      key   = "tolerations"
      value = jsonencode([{ key = "nvidia.com/gpu", operator = "Exists" }, { key = "amd.com/gpu", operator = "Exists" }])
    }
  ]

  amd_gpu_plugin_shapes = ["BM.GPU.MI300X.8", "BM.GPU.MI355X-v1.8", "BM.GPU.MI355X.8"]
  deploy_amd_gpu_plugin_addon = anytrue([
    contains(local.amd_gpu_plugin_shapes, var.worker_rdma_shape),
    contains(local.amd_gpu_plugin_shapes, var.worker_gpu_shape)
  ])

  managed_addon_gate_enabled = anytrue([
    var.deploy_node_feature_discovery,
    var.deploy_nvidia_gpu_operator,
  ])

  managed_addon_non_gpu_pool_ids = compact([
    lookup(module.oke.worker_pool_ids, "oke-system", null),
    var.worker_cpu_enabled ? lookup(module.oke.worker_pool_ids, "oke-cpu", null) : null,
  ])

  nvidia_gpu_operator_addon_configurations = [
    for k, v in merge(
      var.nvidia_gpu_operator_configuration,
      local.nvidia_dcgm_exporter_metrics_addon_configurations,
      {
        disableNvidiaGpuPlugin                  = tostring(var.nvidia_gpu_operator_disable_plugin)
        "cdi.enabled"                           = tostring(var.nvidia_gpu_operator_cdi_enabled)
        "toolkit.enabled"                       = tostring(var.nvidia_gpu_operator_toolkit_enabled)
        skipNodeFeatureDiscoveryDependencyCheck = tostring(var.nvidia_gpu_operator_skip_nfd_dependency_check)
        "migManager.enabled"                    = tostring(var.nvidia_gpu_operator_mig_manager_enabled)
        "mig.strategy"                          = var.nvidia_gpu_operator_mig_strategy
      }
    ) : { key = k, value = v }
  ]
}

resource "kubectl_manifest" "gpu_operator_namespace" {
  count = alltrue([local.configure_nvidia_dcgm_metrics, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  apply_only = true
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = local.nvidia_gpu_operator_namespace
    }
  })

  depends_on = [
    module.oke,
    terraform_data.wait_for_non_gpu_workers,
  ]
}

resource "kubectl_manifest" "nvidia_dcgm_exporter_metrics" {
  count = alltrue([local.configure_nvidia_dcgm_metrics, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = local.nvidia_dcgm_exporter_metrics_config
      namespace = local.nvidia_gpu_operator_namespace
    }
    data = {
      (local.nvidia_dcgm_exporter_metrics_filename) = local.nvidia_dcgm_exporter_metrics
    }
  })

  depends_on = [kubectl_manifest.gpu_operator_namespace]
}

resource "null_resource" "nvidia_dcgm_exporter_metrics_via_operator" {
  count = alltrue([local.configure_nvidia_dcgm_metrics, local.deploy_from_operator]) ? 1 : 0

  triggers = {
    metrics_md5     = md5(local.nvidia_dcgm_exporter_metrics)
    config_name     = local.nvidia_dcgm_exporter_metrics_config
    config_key      = local.nvidia_dcgm_exporter_metrics_filename
    namespace       = local.nvidia_gpu_operator_namespace
    bastion_host    = module.oke.bastion_public_ip
    bastion_user    = local.bastion_user
    ssh_private_key = tls_private_key.stack_key.private_key_openssh
    operator_host   = module.oke.operator_private_ip
    operator_user   = local.operator_user
    metrics_target  = "/tmp/${local.nvidia_dcgm_exporter_metrics_filename}"
  }

  connection {
    bastion_host        = self.triggers.bastion_host
    bastion_user        = self.triggers.bastion_user
    bastion_private_key = self.triggers.ssh_private_key
    host                = self.triggers.operator_host
    user                = self.triggers.operator_user
    private_key         = self.triggers.ssh_private_key
    timeout             = "40m"
    type                = "ssh"
  }

  provisioner "file" {
    content     = local.nvidia_dcgm_exporter_metrics
    destination = self.triggers.metrics_target
  }

  provisioner "remote-exec" {
    inline = [
      "export OCI_CLI_AUTH=instance_principal",
      "export PYTHONWARNINGS=\"ignore:the 'strict' parameter::urllib3.poolmanager\"",
      "export PATH=$PATH:/usr/local/bin:/home/${self.triggers.operator_user}/bin",
      "kubectl create namespace ${self.triggers.namespace} --dry-run=client -o yaml | kubectl apply -f -",
      "kubectl create configmap ${self.triggers.config_name} --namespace ${self.triggers.namespace} --from-file=${self.triggers.config_key}=${self.triggers.metrics_target} --dry-run=client -o yaml | kubectl apply -f -",
      "rm -f ${self.triggers.metrics_target}",
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [
      "export OCI_CLI_AUTH=instance_principal",
      "export PYTHONWARNINGS=\"ignore:the 'strict' parameter::urllib3.poolmanager\"",
      "export PATH=$PATH:/usr/local/bin:/home/${self.triggers.operator_user}/bin",
      "kubectl delete configmap ${self.triggers.config_name} --namespace ${self.triggers.namespace} --ignore-not-found",
    ]
  }

  lifecycle {
    ignore_changes = [
      triggers["bastion_host"],
      triggers["bastion_user"],
      triggers["ssh_private_key"],
      triggers["operator_host"],
      triggers["operator_user"],
    ]
  }

  depends_on = [
    module.oke,
    terraform_data.wait_for_non_gpu_workers,
  ]
}

resource "oci_containerengine_addon" "coredns" {
  count = local.deploy_coredns_addon_override ? 1 : 0

  addon_name = "CoreDNS"
  cluster_id = module.oke.cluster_id

  override_existing                = true
  remove_addon_resources_on_delete = true

  dynamic "configurations" {
    for_each = local.coredns_addon_configurations

    content {
      key   = configurations.value.key
      value = configurations.value.value
    }
  }

  depends_on = [module.oke]
}

resource "oci_containerengine_addon" "amd_gpu_plugin" {
  count = local.deploy_amd_gpu_plugin_addon ? 1 : 0

  addon_name = "AmdGpuPlugin"
  cluster_id = module.oke.cluster_id

  override_existing                = true
  remove_addon_resources_on_delete = true

  depends_on = [module.oke]
}

resource "terraform_data" "wait_for_non_gpu_workers" {
  count = local.managed_addon_gate_enabled ? 1 : 0

  input = {
    region             = var.region
    profile            = var.oci_profile != null ? var.oci_profile : ""
    oci_auth           = var.oci_auth != null ? var.oci_auth : ""
    worker_pool_ids    = join(" ", local.managed_addon_non_gpu_pool_ids)
    wait_timeout_secs  = 1800
    poll_interval_secs = 20
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      export PATH="$PATH:/usr/local/bin"
      export PYTHONWARNINGS="ignore:the 'strict' parameter::urllib3.poolmanager"

      if [ -n "${self.input.oci_auth}" ]; then
        export OCI_CLI_AUTH="${self.input.oci_auth}"
      fi

      profile="${self.input.profile}"
      region="${self.input.region}"
      timeout_secs="${self.input.wait_timeout_secs}"
      poll_interval_secs="${self.input.poll_interval_secs}"
      pool_ids="${self.input.worker_pool_ids}"

      if [ -z "$pool_ids" ]; then
        echo "No non-GPU worker pools were found for add-on gating."
        exit 1
      fi

      profile_args=()
      if [ -n "$profile" ]; then
        profile_args=(--profile "$profile")
      fi

      deadline=$((SECONDS + timeout_secs))
      while [ "$SECONDS" -lt "$deadline" ]; do
        active_nodes=0

        for pool_id in $pool_ids; do
          count=$(
            oci ce node-pool get \
              --node-pool-id "$pool_id" \
              --region "$region" \
              "$${profile_args[@]}" \
              2>/dev/null | \
              python3 -c 'import json, sys; data = json.load(sys.stdin).get("data", {}); print(sum(1 for node in data.get("nodes", []) if node.get("lifecycle-state") == "ACTIVE"))' \
              || echo 0
          )

          active_nodes=$((active_nodes + count))
        done

        if [ "$active_nodes" -gt 0 ]; then
          echo "Detected $active_nodes ACTIVE non-GPU worker node(s)."
          exit 0
        fi

        echo "Waiting for at least one ACTIVE non-GPU worker node..."
        sleep "$poll_interval_secs"
      done

      echo "Timed out waiting for an ACTIVE node in the system/CPU worker pools." >&2
      exit 1
    EOT
  }

  depends_on = [module.oke]
}

resource "oci_containerengine_addon" "node_feature_discovery" {
  count = var.deploy_node_feature_discovery ? 1 : 0

  addon_name = "NodeFeatureDiscovery"
  cluster_id = module.oke.cluster_id

  override_existing                = true
  remove_addon_resources_on_delete = true

  depends_on = [
    module.oke,
    terraform_data.wait_for_non_gpu_workers,
  ]
}

resource "oci_containerengine_addon" "nvidia_gpu_operator" {
  count = var.deploy_nvidia_gpu_operator ? 1 : 0

  addon_name = "NvidiaGpuOperator"
  cluster_id = module.oke.cluster_id

  override_existing                = true
  remove_addon_resources_on_delete = true
  version                          = var.nvidia_gpu_operator_addon_version

  dynamic "configurations" {
    for_each = local.nvidia_gpu_operator_addon_configurations

    content {
      key   = configurations.value.key
      value = configurations.value.value
    }
  }

  depends_on = [
    module.oke,
    terraform_data.wait_for_non_gpu_workers,
    kubectl_manifest.nvidia_dcgm_exporter_metrics,
    null_resource.nvidia_dcgm_exporter_metrics_via_operator,
    oci_containerengine_addon.node_feature_discovery,
  ]
}
