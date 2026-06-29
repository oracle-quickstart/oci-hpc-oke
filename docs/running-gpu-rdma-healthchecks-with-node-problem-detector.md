# Running GPU and RDMA Health Checks with Node Problem Detector

> [!NOTE]
> If you deployed the monitoring stack using Terraform, Node Problem Detector is already installed and configured. Do not install a second copy manually.

Node Problem Detector (NPD) monitors node health and reports problems as Kubernetes node conditions and events. This guide explains the OKE-specific GPU and RDMA checks, their three-state result contract, and how to deploy the vendor-specific NPD releases manually.

## Overview

The deployment uses separate AMD and NVIDIA releases:

- `gpu-rdma-node-problem-detector-amd`
- `gpu-rdma-node-problem-detector-nvidia`

Each release has node affinity for its supported shapes and loads only the checks for that GPU vendor. A mixed-vendor cluster runs both releases.

The deployed image is multi-platform and supports `linux/amd64` and `linux/arm64`.

## Prerequisites

- An OKE cluster with supported GPU nodes
- `kubectl` access with permission to create cluster-scoped NPD resources
- Helm 3.8 or later
- `jq` for the status commands in this guide
- The `monitoring` namespace
- A local clone of this repository

Run all commands from the repository root.

## Health Checks

| Condition | Vendor | Description |
|---|---|---|
| `GpuCount` | AMD and NVIDIA | Verifies the expected GPU count |
| `GpuEcc` | AMD and NVIDIA | Checks uncorrectable GPU ECC errors |
| `GpuRowRemap` | NVIDIA | Checks row-remapping errors |
| `GpuBus` | AMD and NVIDIA | Checks for devices that have fallen off the PCIe bus |
| `GpuPcie` | AMD and NVIDIA | Checks GPU PCIe link width |
| `GpuFabricMgr` | NVIDIA | Checks Fabric Manager where required |
| `GpuBadPages` | AMD | Checks pending AMD GPU bad pages |
| `GpuXid` | NVIDIA | Checks kernel logs for NVIDIA XID errors |
| `NvlinkSpeed` | NVIDIA | Checks NVLink count and speed |
| `DcgmiHealth` | NVIDIA | Runs the DCGMI health check |
| `Rocminfo` | AMD | Validates ROCm discovery with `rocminfo` |
| `RdmaLink` | AMD and NVIDIA | Checks RDMA link state |
| `RdmaLinkFlapping` | AMD and NVIDIA | Checks RDMA link flapping |
| `RdmaWpaAuth` | AMD and NVIDIA | Checks RDMA interface authentication |
| `RdmaRttcc` | AMD and NVIDIA | Checks that RTTCC is disabled |
| `RdmaVfRoutes` | NVIDIA B300 and GB300 | Checks multi-plane RDMA VF addresses and routes |
| `RdmaVfCounters` | NVIDIA B300 and GB300 | Checks multi-plane RDMA VF error counters |
| `GpuImex` | NVIDIA GB300 | Checks IMEX service readiness |
| `IpAddress` | AMD and NVIDIA | Checks required RDMA interface addresses |
| `OcaVersion` | AMD and NVIDIA | Checks the Oracle Cloud Agent version |
| `CpuProfile` | AMD and NVIDIA | Checks that online CPUs use the performance governor |
| `NodeHasPcieErrors` | AMD and NVIDIA | Monitors kernel logs for PCIe AER errors |

Some checks return a passing result when they do not apply to the current shape. The vendor-specific monitor configuration prevents AMD-only and NVIDIA-only checks from running on the wrong vendor.

## Check Intervals and Concurrency

Checks are grouped instead of running as separate synchronized monitors.

Fast checks:

- Run every 60 seconds.
- Allow two concurrent checks.
- Use rule timeouts of 30 to 45 seconds.

Slow checks:

- Run every 300 seconds.
- Allow one concurrent check.
- Include CPU profile, OCA version, NVLink, DCGMI, and multi-plane configuration checks where applicable.

The exact monitor definitions are in:

- `terraform/files/node-problem-detector/values-amd.yaml`
- `terraform/files/node-problem-detector/values-nvidia.yaml`

## Result Contract

The wrapper and Python health checker use three results:

| Exit code | Result | Node condition status |
|---:|---|---|
| `0` | The check ran and passed | `False` |
| `1` | The check ran and found a confirmed problem | `True` |
| `2` | The result is unavailable or unreliable | `Unknown` |

NPD conditions describe problems. Therefore, `False` means healthy.

Missing commands, timeouts inside Python, parsing failures, invalid output, and Python exceptions return Unknown instead of Healthy.

## Protected Execution and Logs

Every invocation uses a unique root-owned work directory under:

```text
/var/lib/oke-npd/run
```

The wrapper stores one root-owned Python runner at `/var/lib/oke-npd/bin/uv` and stages it atomically once per NPD pod. It does not copy the runner into every work directory.

Each invocation removes abandoned work directories and incomplete runner staging files older than ten minutes. This cleanup handles directories left behind when NPD ends a check with `SIGKILL`, which cannot run the wrapper's exit trap.

Executable code is not copied to or executed from shared `/tmp`.

The wrapper publishes detailed logs atomically under:

```text
/var/log/oke-npd/latest-<check>.log
```

Examples:

```text
/var/log/oke-npd/latest-gpu-count.log
/var/log/oke-npd/latest-ecc-err.log
/var/log/oke-npd/latest-rdmalink-stat.log
```

Read a log directly on the GPU node:

```bash
sudo sed -n '1,160p' /var/log/oke-npd/latest-gpu-count.log
```

## Freshness Metrics

Before a check starts, the wrapper publishes an initial Unknown heartbeat. A completed check atomically replaces it with the final result.

The node-exporter textfile collector exposes:

```prometheus
oke_npd_check_last_run_timestamp_seconds{check="gpu-count"}
oke_npd_check_expected_interval_seconds{check="gpu-count"}
oke_npd_check_duration_seconds{check="gpu-count"}
oke_npd_check_status_code{check="gpu-count"}
```

Status codes are `0` for pass, `1` for fail, and `2` for Unknown.

The monitoring stack must configure node exporter with:

```text
--collector.textfile.directory=/host/root/var/lib/node_exporter/textfile_collector
```

Terraform configures this automatically. For a manual monitoring deployment, follow `docs/deploying-monitoring-stack-manually.md`.

## Manual Deployment

Create the namespace if it does not already exist:

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
```

Install the release that matches the cluster's GPU vendor. Install both releases for a mixed-vendor cluster.

### AMD

```bash
helm upgrade --install gpu-rdma-node-problem-detector-amd \
  oci://ghcr.io/deliveryhero/helm-charts/node-problem-detector \
  --version 2.4.1 \
  --namespace monitoring \
  --values terraform/files/node-problem-detector/values.yaml \
  --values terraform/files/node-problem-detector/values-amd.yaml \
  --wait
```

### NVIDIA

```bash
helm upgrade --install gpu-rdma-node-problem-detector-nvidia \
  oci://ghcr.io/deliveryhero/helm-charts/node-problem-detector \
  --version 2.4.1 \
  --namespace monitoring \
  --values terraform/files/node-problem-detector/values.yaml \
  --values terraform/files/node-problem-detector/values-nvidia.yaml \
  --wait
```

## Verify the Deployment

Check the releases and DaemonSets:

```bash
helm list -n monitoring | grep node-problem-detector
kubectl get daemonset -n monitoring | grep node-problem-detector
kubectl get pods -n monitoring \
  -l 'app.kubernetes.io/name in (gpu-rdma-node-problem-detector-amd,gpu-rdma-node-problem-detector-nvidia)' \
  -o wide
```

Check the image and pulled digest:

```bash
kubectl get pods -n monitoring \
  -l 'app.kubernetes.io/name in (gpu-rdma-node-problem-detector-amd,gpu-rdma-node-problem-detector-nvidia)' \
  -o json | jq -r '.items[] |
    [.metadata.name, .spec.nodeName, .spec.containers[0].image,
     .status.containerStatuses[0].imageID] | @tsv'
```

Wait for at least one complete monitor cycle before interpreting the conditions. Fast checks normally appear within one minute. Slow checks can take up to five minutes plus their execution time.

## View Node Conditions

View all conditions for one node:

```bash
kubectl describe node <node-name>
```

Show GPU and RDMA health conditions in a compact form:

```bash
kubectl get node <node-name> -o json | jq -r '
  .status.conditions[]
  | select(.type | test("^(CpuProfile|DcgmiHealth|Gpu|IpAddress|NvlinkSpeed|OcaVersion|Rdma|Rocminfo)"))
  | [.type, .status, .reason, .message, .lastTransitionTime]
  | @tsv'
```

Example:

```text
GpuCount       False    GpuCountHasNoIssues    Node has the expected number of GPUs
GpuEcc         Unknown  GpuEccHasNoIssues      ECC check failed: amd-smi returned invalid JSON
RdmaLink       True     RdmaLinkHasIssues      Healthcheck:: RDMA Link Error
```

Interpret the status as follows:

- `False`: the check ran and found no problem.
- `True`: the check confirmed a problem.
- `Unknown`: the check could not produce a reliable result.

## List Nodes with Failed or Unknown Checks

```bash
kubectl get nodes -o json | jq -r '
  .items[] as $node
  | $node.status.conditions[]
  | select(.type | test("^(CpuProfile|DcgmiHealth|Gpu|IpAddress|NvlinkSpeed|OcaVersion|Rdma|Rocminfo)"))
  | select(.status == "True" or .status == "Unknown")
  | [$node.metadata.name, $node.spec.providerID,
     $node.metadata.labels["oci.oraclecloud.com/host.serial_number"],
     .type, .status, .message]
  | @tsv'
```

## Verify Freshness Metrics

Port-forward Prometheus:

```bash
kubectl port-forward -n monitoring \
  service/kube-prometheus-stack-prometheus 9090:9090
```

In another terminal, query the check status and last-run timestamp:

```bash
curl -fsSG http://127.0.0.1:9090/api/v1/query \
  --data-urlencode 'query=oke_npd_check_status_code' | jq

curl -fsSG http://127.0.0.1:9090/api/v1/query \
  --data-urlencode 'query=oke_npd_check_last_run_timestamp_seconds' | jq
```

## Alert Behavior

Confirmed hardware or configuration failures use condition-specific alerts that select `status="true"`.

Checker failures use the `NPD Check Unknown` alert, which selects `status="unknown"`.

The `NPD Check Stale` alert fires when a check has not updated within:

```text
2 * expected interval + 60 seconds
```

This means:

- A 60-second check becomes stale after 180 seconds.
- A 300-second check becomes stale after 660 seconds.

GPU dashboards and the missing-NPD fallback use `kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu"}` as their GPU node inventory. This metric is independent of NPD, so a GPU node remains visible and the stale alert can detect it when NPD publishes no conditions or freshness metrics.

The `node_health_status` recording rule evaluates all 13 AMD or 19 NVIDIA conditions configured for the node. It records `0` for Failed, `1` for Healthy, and `2` for Unknown. A missing expected condition is Unknown, and confirmed failures take priority over Unknown. Command Center healthy node and GPU totals count only value `1`.

If NPD kills a command at the outer plugin timeout, NPD can retain the previous node condition. The initial heartbeat stops updating, allowing the stale alert to detect the hung check.

## Migrating from the Generic Release

Older deployments used one release named `gpu-rdma-node-problem-detector`.

Install and verify the vendor-specific release before removing the old release. For example, on AMD:

```bash
helm upgrade --install gpu-rdma-node-problem-detector-amd \
  oci://ghcr.io/deliveryhero/helm-charts/node-problem-detector \
  --version 2.4.1 \
  --namespace monitoring \
  --values terraform/files/node-problem-detector/values.yaml \
  --values terraform/files/node-problem-detector/values-amd.yaml \
  --wait

kubectl rollout status \
  daemonset/gpu-rdma-node-problem-detector-amd \
  -n monitoring --timeout=5m

helm uninstall gpu-rdma-node-problem-detector -n monitoring
```

Use the NVIDIA release and values file on NVIDIA clusters.

## Uninstalling

Uninstall the releases present in the cluster:

```bash
helm uninstall gpu-rdma-node-problem-detector-amd -n monitoring
helm uninstall gpu-rdma-node-problem-detector-nvidia -n monitoring
```

Node conditions written by NPD can remain after uninstalling the release. They are removed when another writer updates the node status or when the node is replaced. Do not assume that Kubernetes automatically removes custom conditions when NPD is deleted.
