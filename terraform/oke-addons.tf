# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  managed_addon_gate_enabled = anytrue([
    var.deploy_node_feature_discovery,
    var.deploy_nvidia_gpu_operator,
  ])

  managed_addon_non_gpu_pool_ids = compact([
    lookup(module.oke.worker_pool_ids, "oke-system", null),
    var.worker_cpu_enabled ? lookup(module.oke.worker_pool_ids, "oke-cpu", null) : null,
  ])

  nvidia_gpu_operator_addon_configurations = [
    for k, v in merge(var.nvidia_gpu_operator_configuration, {
      disableNvidiaGpuPlugin                  = tostring(var.nvidia_gpu_operator_disable_plugin)
      "cdi.enabled"                           = tostring(var.nvidia_gpu_operator_cdi_enabled)
      "toolkit.enabled"                       = tostring(var.nvidia_gpu_operator_toolkit_enabled)
      skipNodeFeatureDiscoveryDependencyCheck = tostring(var.nvidia_gpu_operator_skip_nfd_dependency_check)
      "migManager.enabled"                    = tostring(var.nvidia_gpu_operator_mig_manager_enabled)
      "mig.strategy"                          = var.nvidia_gpu_operator_mig_strategy
    }) : { key = k, value = v }
  ]
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
    oci_containerengine_addon.node_feature_discovery,
  ]
}
