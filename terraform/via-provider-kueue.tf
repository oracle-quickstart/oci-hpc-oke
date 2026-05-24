# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  kueue_amd_shapes   = ["BM.GPU.MI300X.8", "BM.GPU.MI355X-v1.8", "BM.GPU.MI355X.8"]
  kueue_shape        = var.worker_gmc_enabled ? var.worker_gmc_shape : var.worker_rdma_shape
  kueue_is_amd       = contains(local.kueue_amd_shapes, local.kueue_shape)
  kueue_gpu_resource = local.kueue_is_amd ? "amd.com/gpu" : "nvidia.com/gpu"
  kueue_flavor_name  = "${lower(replace(local.kueue_shape, ".", "-"))}-rdma-topology-aware"
}

resource "helm_release" "kueue" {
  count = alltrue([var.install_kueue, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0
  depends_on = [
    module.oke,
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke
  ]
  namespace        = "kueue-system"
  name             = "kueue"
  chart            = "oci://registry.k8s.io/kueue/charts/kueue"
  version          = var.kueue_chart_version
  create_namespace = true
  wait             = true
  timeout          = 300
  max_history      = 1
}

# Kueue installs cluster-wide admission webhooks. Wait for the backing endpoint
# before other Helm releases create Deployments that the webhook mutates.
resource "terraform_data" "wait_for_kueue_webhook" {
  count = alltrue([var.install_kueue, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  input = {
    cluster_ca_certificate = local.cluster_ca_cert
    cluster_host           = local.deploy_from_orm ? local.cluster_orm_endpoint : (local.cluster_public_endpoint != "https://" ? local.cluster_public_endpoint : local.cluster_private_endpoint)
    cluster_id             = module.oke.cluster_id
    oci_auth               = var.oci_auth != null ? var.oci_auth : ""
    poll_interval_secs     = 5
    profile                = var.oci_profile != null ? var.oci_profile : ""
    region                 = var.region
    wait_timeout_secs      = 300
  }

  triggers_replace = [
    module.oke.cluster_id,
    var.kueue_chart_version,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      export PATH="$PATH:/usr/local/bin"

      if [ -n "${self.input.oci_auth}" ]; then
        export OCI_CLI_AUTH="${self.input.oci_auth}"
      fi

      tmpdir="$(mktemp -d)"
      trap 'rm -rf "$tmpdir"' EXIT
      ca_file="$tmpdir/cluster-ca.crt"
      printf '%s' "${self.input.cluster_ca_certificate}" | base64 --decode > "$ca_file"

      profile="${self.input.profile}"
      profile_args=()
      if [ -n "$profile" ]; then
        profile_args=(--profile "$profile")
      fi

      token="$(
        oci ce cluster generate-token \
          --cluster-id "${self.input.cluster_id}" \
          --region "${self.input.region}" \
          $${profile_args[@]+"$${profile_args[@]}"} | \
          python3 -c 'import json, sys; print(json.load(sys.stdin)["status"]["token"])'
      )"

      python3 - "${self.input.cluster_host}" "$ca_file" "$token" "${self.input.wait_timeout_secs}" "${self.input.poll_interval_secs}" <<'PY'
import json
import ssl
import sys
import time
import urllib.error
import urllib.request

host, ca_file, token = sys.argv[1], sys.argv[2], sys.argv[3]
timeout_secs, poll_interval_secs = int(sys.argv[4]), int(sys.argv[5])
context = ssl.create_default_context(cafile=ca_file)

def get_json(path):
    request = urllib.request.Request(
        host.rstrip("/") + path,
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(request, context=context, timeout=15) as response:
        return json.load(response)

def deployment_ready(deployment):
    spec = deployment.get("spec", {})
    status = deployment.get("status", {})
    metadata = deployment.get("metadata", {})
    desired = spec.get("replicas", 1)
    generation = metadata.get("generation", 0)

    return all([
        status.get("observedGeneration", 0) >= generation,
        status.get("updatedReplicas", 0) >= desired,
        status.get("readyReplicas", 0) >= desired,
        status.get("availableReplicas", 0) >= desired,
    ])

def endpoint_address_count(endpoints):
    return sum(
        len(subset.get("addresses", []) or [])
        for subset in endpoints.get("subsets", []) or []
    )

deadline = time.time() + timeout_secs
last_status = "not checked yet"

while time.time() < deadline:
    try:
        deployment = get_json("/apis/apps/v1/namespaces/kueue-system/deployments/kueue-controller-manager")
        endpoints = get_json("/api/v1/namespaces/kueue-system/endpoints/kueue-webhook-service")
        ready_addresses = endpoint_address_count(endpoints)

        if deployment_ready(deployment) and ready_addresses > 0:
            print(f"Kueue webhook is ready with {ready_addresses} endpoint address(es).")
            sys.exit(0)

        status = deployment.get("status", {})
        last_status = (
            f"updated={status.get('updatedReplicas', 0)}, "
            f"ready={status.get('readyReplicas', 0)}, "
            f"available={status.get('availableReplicas', 0)}, "
            f"endpoint_addresses={ready_addresses}"
        )
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        last_status = str(exc)

    print(f"Waiting for Kueue webhook readiness: {last_status}", flush=True)
    time.sleep(poll_interval_secs)

print(f"Timed out waiting for Kueue webhook readiness: {last_status}", file=sys.stderr)
sys.exit(1)
PY
    EOT
  }

  depends_on = [helm_release.kueue]
}

# Kueue Topology for RDMA-aware scheduling
resource "kubectl_manifest" "kueue_topology" {
  count = alltrue([var.install_kueue, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body  = file("${path.module}/files/kueue/topology.yaml")
  depends_on = [terraform_data.wait_for_kueue_webhook]
}

# ResourceFlavor matching the active GPU worker pool shape
resource "kubectl_manifest" "kueue_resource_flavor" {
  count = alltrue([var.install_kueue, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body = templatefile("${path.module}/files/kueue/resource-flavor.yaml.tpl", {
    flavor_name   = local.kueue_flavor_name
    shape         = local.kueue_shape
    gpu_label_key = local.kueue_gpu_resource
  })

  depends_on = [terraform_data.wait_for_kueue_webhook, kubectl_manifest.kueue_topology]
}

# ClusterQueue with resource quotas
resource "kubectl_manifest" "kueue_cluster_queue" {
  count = alltrue([var.install_kueue, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body = templatefile("${path.module}/files/kueue/cluster-queue.yaml.tpl", {
    flavor_name  = local.kueue_flavor_name
    gpu_resource = local.kueue_gpu_resource
  })

  depends_on = [terraform_data.wait_for_kueue_webhook, kubectl_manifest.kueue_resource_flavor]
}

# LocalQueue in the user-specified namespace
resource "kubectl_manifest" "kueue_local_queue" {
  count = alltrue([var.install_kueue, local.deploy_from_local || local.deploy_from_orm]) ? 1 : 0

  yaml_body = templatefile("${path.module}/files/kueue/local-queue.yaml.tpl", {
    flavor_name = local.kueue_flavor_name
    namespace   = var.kueue_local_queue_default_namespace
  })

  depends_on = [terraform_data.wait_for_kueue_webhook, kubectl_manifest.kueue_cluster_queue]
}
