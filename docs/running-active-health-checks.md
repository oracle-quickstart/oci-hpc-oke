# Running Active Health Checks for GPU Nodes (preview)

> [!NOTE]  
> This is a preview feature. We are actively adding more tests.

This repository contains Kubernetes manifests for automated active health checks on GPU nodes. These checks run periodically to validate GPU functionality and label nodes with their health status.

## Overview

Three types of active health checks are provided:

1. **NCCL Tests** - Multi-node GPU communication tests using NVIDIA NCCL
2. **GPU Fryer** - Single-node GPU stress testing
3. **DCGM Diagnostics** - Host-level GPU diagnostics using NVIDIA DCGM

Each health check runs as a CronJob that:
- Selects idle GPU nodes that haven't been tested in the last 24 hours
- Runs the appropriate test workload
- Labels nodes with pass/fail results and timestamps
- Automatically cleans up completed jobs

## Architecture

### Common Features

All health checks share these characteristics:

- **Low Priority**: Use `active-health-checks-low` PriorityClass to avoid disrupting production workloads
- **Idle Node Selection**: Only test nodes with zero GPU allocation
- **Daily Testing**: Skip nodes already tested today (based on UTC date)
- **Automatic Labeling**: Apply pass/fail labels and timestamps to tested nodes
- **Self-Cleaning**: Jobs auto-delete after completion (TTL 5 minutes)
- **Hourly Schedule**: Run every hour (configurable via `schedule` field)

### Node Labels

Each health check applies two labels to tested nodes:

| Health Check | Pass/Fail Label | Timestamp Label |
|--------------|----------------|-----------------|
| NCCL Tests | `oke.oraclecloud.com/active-health-checks-nccl-tests` | `oke.oraclecloud.com/active-health-checks-nccl-tests-last-run` |
| GPU Fryer | `oke.oraclecloud.com/active-health-checks-gpu-fryer` | `oke.oraclecloud.com/active-health-checks-gpu-fryer-last-run` |
| DCGM Diagnostics | `oke.oraclecloud.com/active-health-checks-dcgm-diag` | `oke.oraclecloud.com/active-health-checks-dcgm-diag-last-run` |

Label values:
- Pass/Fail: `pass` or `fail`
- Timestamp: ISO 8601 format with hyphens, e.g., `2025-10-01T14-30-00Z`

## RBAC Permissions

All three health checks use the same RBAC configuration:

- **ServiceAccount**: `active-health-checks-runner` (in `monitoring` namespace)
- **ClusterRole**: `active-health-checks-runner-role`

### Manual Test Execution

To manually trigger a test outside the schedule:

```bash
# Create a one-off job from the CronJob
kubectl create job -n monitoring manual-test --from=cronjob/active-health-checks-nccl-tests-applier
kubectl create job -n monitoring manual-test --from=cronjob/active-health-checks-gpu-fryer-applier
kubectl create job -n monitoring manual-test --from=cronjob/active-health-checks-dcgm-diag-applier
```

## Deployment

### Deploy Kueue and MPI Operator
```bash
helm install kueue oci://registry.k8s.io/kueue/charts/kueue --version="0.13.4" --create-namespace --namespace=kueue-system

kubectl apply --server-side -f https://raw.githubusercontent.com/kubeflow/mpi-operator/v0.6.0/deploy/v2beta1/mpi-operator.yaml
```

```bash
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/active-health-checks/active-health-checks-nccl-tests.yaml
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/active-health-checks/active-health-checks-gpu-fryer.yaml
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/active-health-checks/active-health-checks-dcgm-diag.yaml
```

## Node Selection Logic

All health checks follow this selection process:

1. **Find GPU Nodes**: Query nodes with `nvidia.com/gpu=true` label
2. **Check Idle Status**: Calculate GPU usage from pod requests
   - Only nodes with 0 GPU allocation are considered
3. **Check Last Run**: Parse `*-last-run` timestamp label
   - Skip nodes tested today (same UTC date)
4. **Select Nodes**:
   - NCCL: Pick 2+ nodes of same shape
   - GPU Fryer: Pick 1 node
   - DCGM: Pick 1 node

This ensures:
- Production workloads are never disrupted
- Each node is tested at most once per day
- Tests run on available capacity

