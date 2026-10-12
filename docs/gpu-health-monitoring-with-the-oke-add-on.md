# GPU Health Monitoring with the OKE Add-on

> [!NOTE]
> Terraform installs the add-on when `deploy_gpu_health_monitoring` is `true` (the default) and the cluster has GPU node pools. Terraform also sets up the metrics, dashboards, and alerts in this guide.

The OKE GPU Health Monitoring add-on reports GPU node faults as node conditions and `NodeHealthReport` objects. OKE manages the add-on. Node Problem Detector (NPD) keeps running its checks next to the add-on.

## Overview

The add-on has two components in the `gpu-health-monitoring` namespace:

- The `gpu-health-monitoring-controller` Deployment enables the Oracle Cloud Agent (OCA) "Compute RDMA GPU Monitoring" plugin on each GPU node and manages the node repairs.
- The `gpu-fault-monitor` DaemonSet reads the health check results of the OCA plugin on each GPU node every 30 seconds.

The OCA plugin runs passive health checks every five minutes. It also reads the active faults of the node from the OCI Fault Management Service (FMS). The fault monitor publishes the critical results as node conditions and `NodeHealthReport` objects.

The add-on can also repair nodes. It reboots a node when a fault with the action `REBOOT` stays active for 10 minutes, and it tags and terminates a node on a user request. Repair needs a `NodeRepairConfig` resource. Terraform does not create this resource. See [Repairing GPU Hosts](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengautorepairgpuworkernodes.htm).

## Prerequisites

- An enhanced OKE cluster with Kubernetes 1.32 or later
- Managed GPU node pools
- The IAM policy that lets the worker nodes read the instance agent plugins. Terraform creates this policy.

## Node Conditions

| Condition | Healthy value | Description |
|---|---|---|
| `oci.oraclecloud.com/GpuHealthMonitoringConfigured` | `True` | The add-on enabled the OCA plugin on the node. |
| `oci.oraclecloud.com/GpuHealthMonitoringUnavailable` | `False` | The health check result files are present on the node. |
| `oci.oraclecloud.com/GpuHealthMonitoringFaultDetected` | `False` | The passive health checks found no active critical GPU fault. |

To list the nodes with an add-on problem:

```bash
kubectl get nodes -o json | jq -r '.items[] | .metadata.name as $n |
  .status.conditions[] | select(.type | startswith("oci.oraclecloud.com/GpuHealthMonitoring")) |
  select(((.type | endswith("Configured")) and .status != "True") or ((.type | endswith("Configured") | not) and .status != "False")) |
  [$n, .type, .status, .reason] | @tsv'
```

## Supported Shapes

The OCA plugin has health check rules for these shapes (Oracle Cloud Agent 1.64.0):

- `BM.GPU.A100-v2.8`, `BM.GPU4.8`, `BM.GPU.B4.8`
- `BM.GPU.H100.8`, `BM.GPU.H100T.8`, `BM.GPU.H200.8`, `BM.GPU.H200-LM.8`
- `BM.GPU.B200.8`, `BM.GPU.B300.8`, `BM.GPU.B300.HS.8`
- `BM.GPU.GB200.4`, `BM.GPU.GB200-v2.4`, `BM.GPU.GB200-v3.4`, `BM.GPU.GB300.4`
- `BM.GPU.L40S.4`, `BM.GPU.L40S-NC.4`, `BM.GPU.RTXPRO.8`
- `BM.GPU.MI300X.8`, `BM.GPU.MI355X.8`, `BM.GPU.MI355X-v1.8`

## Health Checks

The OCA plugin selects the checks for the node shape. On `BM.GPU.B300.8`, it runs these checks:

| Area | Checks |
|---|---|
| GPU | `gpu_count`, `gpu_driver`, `gpu_mode`, `gpu_clk`, `gpu_xid`, `bar1_util`, `peermem` |
| GPU memory | `dram`, `sram`, `remap`, `retired_pages` |
| NVLink and fabric | `nvlink`, `nvlink_err`, `fabric`, `fabricmanager` |
| PCIe | `walk_pcie` (all PCIe devices), `pcie` (RDMA NICs) |
| RDMA | `link`, `rdma_count`, `rdma_link_flap`, `auth`, `gid_index`, `rx_discards` |
| Other | `eth_link`, `hpc_info` |

A check result that is not trustworthy (`TEST_ERROR`) gets the action `IGNORE`. The fault monitor does not publish these results. It writes a warning to its log.

## Node Health Reports

The add-on creates a cluster-scoped `NodeHealthReport` for a node when it has a fault or a repair. The report has these signal lists:

| Signal | Source | Fields |
|---|---|---|
| `clusterHealthCheck` | Passive health checks | `faultCode`, `faultDescription`, `action`, `firstObservedAt`, `lastObservedAt` |
| `hpcFault` | OCI Fault Management Service | `faultCode`, `firstObservedAt`, `lastObservedAt` |
| `customer` | User-initiated repair label | `action`, `firstObservedAt`, `lastObservedAt` |
| `maintenanceEvent` | OCI maintenance events | `faultCodes`, `action`, `maintenanceLifecycleState` |

The report also has `status.repair` (the active repair) and `status.lastRepairAttempt`.

To list the reports and show the signals of one node:

```bash
kubectl get nodehealthreports.oci.oraclecloud.com

NODE=<node-name>
kubectl get nodehealthreports.oci.oraclecloud.com "node-$(kubectl get node "${NODE}" -o jsonpath='{.metadata.uid}')" \
  -o jsonpath='{.status.signals}' | jq
```

If the node has no fault and no repair, the second command returns `NotFound`.

The node repair controller also writes Kubernetes events on the report, for example `NodeCordoned`, `NodeDrained`, and `RepairCompleted`. The events of cluster-scoped objects are in the `default` namespace:

```bash
kubectl get events -n default --field-selector involvedObject.kind=NodeHealthReport
```

The report does not show which device failed. To see the device and the measured values, read the health check result files on the node:

| File | Content |
|---|---|
| `/var/lib/oci-dr-hpc-v2/current/passive_results.json` | Result of each check for each device |
| `/var/lib/oci-dr-hpc-v2/current/passive_events.json` | Measured values for each GPU and NIC |
| `/var/lib/oci-dr-hpc-v2/current/passive_remediation.json` | Recommendations that the fault monitor reads |
| `/var/log/oracle-cloud-agent/plugins/oci-hpc/oci-hpc-monitoring/fault-data/oci-hpc-faults.json` | Active FMS faults, with the PCIe address of each fault |

The node keeps the results of the last three runs only (15 minutes).

## Metrics and Dashboards

kube-state-metrics exports the reports as `oke_node_health_report_*` metrics:

| Metric | Description |
|---|---|
| `oke_node_health_report_repair_info` | Active repair: action, phase, terminal state, dry run, admission |
| `oke_node_health_report_repair_started_timestamp_seconds` | Start time of the active repair |
| `oke_node_health_report_last_repair_info` | Last repair: action, result, dry run |
| `oke_node_health_report_last_repair_completed_timestamp_seconds` | End time of the last repair |
| `oke_node_health_report_signal_first_observed_timestamp_seconds` | First time of each signal, with `source`, `fault_code`, `description`, and `action` labels. `hpcFault` signals have no description or action. |
| `oke_node_health_report_signal_last_observed_timestamp_seconds` | Last time of each signal |
| `oke_node_health_report_maintenance_event_last_observed_timestamp_seconds` | Last time of each maintenance event, with `maintenance_event_id`, `action`, and `maintenance_state` labels |

Prometheus also scrapes the fault monitor pods. The `gfm_*` metrics show the scan results and the age of the health check files, for example `gfm_passive_result_age_seconds` and `gfm_scan_total`.

The `node_health_status` recording rule includes the add-on:

- A node with `GpuHealthMonitoringFaultDetected=True` is `0` (Failed).
- A node with `GpuHealthMonitoringUnavailable=True`, or with `GpuHealthMonitoringConfigured` not `True`, is `2` (Unknown).

These dashboards show the add-on data:

- **GPU Node Repairs**: faults, repairs, repair results, maintenance events, and fault monitor health. Every panel covers the dashboard time range. Set the range to the last 15 minutes to see what is active now.
- **GPU Health Status**: the "GPU Health Add-on" panel for each node
- **Command Center**: node health and the `GpuHealthMonitoringFaultDetected` condition in the node issues history

## Alerts

| Alert | Fires when |
|---|---|
| GPU Health Fault | `GpuHealthMonitoringFaultDetected` is `True` for 1 minute. |
| GPU Health Monitoring Unavailable | The add-on does not monitor the node for 30 minutes. |
| GPU Node Repair Failed | A node repair failed in the last hour. |
| GPU Fault Monitor Stale or Missing | The health check files on a node are older than 15 minutes, or a configured node has no healthy fault monitor scrape, for 10 minutes. |

The alerts are in the `GPU Health Monitoring` group of the `Alerts` folder. They use the `ons-webhook` contact point.

## Troubleshooting

### GpuHealthMonitoringConfigured Is Unknown

The reason `ActionTerminalRetryHold` means that the controller could not enable the OCA plugin on the node and stopped retrying for 24 hours. `GpuHealthMonitoringUnavailable` is then `True`, because the health check files are missing. Read the logs of both controller pods for the node:

```bash
NODE=<node-name>
for pod in $(kubectl get pods -n gpu-health-monitoring -o name | grep gpu-health-monitoring-controller); do
  kubectl logs -n gpu-health-monitoring "${pod}" | grep "${NODE}"
done
```

### A Fault Has No Details

Read the health check result files on the node. See [Node Health Reports](#node-health-reports).
