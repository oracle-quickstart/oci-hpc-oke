# Running Active Health Checks for GPU Nodes (Preview)

> [!NOTE]  
> This is a preview feature. Additional tests are being actively developed and added.

Active health checks provide automated, periodic validation of GPU & RDMA functionality on OKE nodes. These checks run as CronJobs that test GPU nodes during idle periods and apply labels indicating the health status of each node.

## Overview

### Available Health Check Types

Five types of active health checks are available:

1. **NCCL Tests** - Multi-node GPU communication tests using NVIDIA NCCL (NVIDIA GPUs)
2. **RCCL Tests** - Multi-node GPU communication tests using AMD RCCL (AMD GPUs)
3. **GPU Fryer** - Single-node GPU stress testing (NVIDIA GPUs)
4. **RVS** - Single-node GPU validation using ROCm Validation Suite (AMD GPUs)
5. **DCGM Diagnostics** - Host-level GPU diagnostics using NVIDIA DCGM (NVIDIA GPUs)

### How It Works

Each health check runs as a CronJob that:
- Identifies idle GPU nodes that have not been tested in the last 24 hours
- Executes the appropriate test workload
- Applies labels to nodes with pass/fail results and timestamps
- Automatically cleans up completed jobs after 5 minutes

## Prerequisites

- OKE cluster with GPU nodes
- kubectl access with cluster-admin privileges
- Kueue installed
- MPI Operator installed (for NCCL and RCCL tests)
- Monitoring namespace (or permission to create it)

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
| RCCL Tests | `oke.oraclecloud.com/active-health-checks-rccl-tests` | `oke.oraclecloud.com/active-health-checks-rccl-tests-last-run` |
| GPU Fryer | `oke.oraclecloud.com/active-health-checks-gpu-fryer` | `oke.oraclecloud.com/active-health-checks-gpu-fryer-last-run` |
| RVS | `oke.oraclecloud.com/active-health-checks-rvs` | `oke.oraclecloud.com/active-health-checks-rvs-last-run` |
| DCGM Diagnostics | `oke.oraclecloud.com/active-health-checks-dcgm-diag` | `oke.oraclecloud.com/active-health-checks-dcgm-diag-last-run` |

Label values:
- Pass/Fail: `pass` or `fail`
- Timestamp: ISO 8601 format with hyphens, e.g., `2025-10-01T14-30-00Z`

## RBAC Permissions

All five health checks use the same RBAC configuration:

- **ServiceAccount**: `active-health-checks-runner` (in `monitoring` namespace)
- **ClusterRole**: `active-health-checks-runner-role`

The RBAC permissions allow the health check jobs to:
- List and describe nodes
- Read pod information to determine GPU allocation
- Label nodes with test results

## Deployment

### Step 1: Install Prerequisites

Install Kueue and MPI Operator (required for NCCL tests):

```bash
helm install kueue oci://registry.k8s.io/kueue/charts/kueue --version="0.14.2" --create-namespace --namespace=kueue-system

kubectl apply --server-side -f https://raw.githubusercontent.com/kubeflow/mpi-operator/v0.6.0/deploy/v2beta1/mpi-operator.yaml
```

### Step 2: Deploy Active Health Checks

Deploy all health check CronJobs:

**For NVIDIA GPU clusters:**
```bash
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/active-health-checks/active-health-checks-nccl-tests.yaml
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/active-health-checks/active-health-checks-gpu-fryer.yaml
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/active-health-checks/active-health-checks-dcgm-diag.yaml
```

**For AMD GPU clusters:**
```bash
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/active-health-checks/active-health-checks-rccl-tests.yaml
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/active-health-checks/active-health-checks-rvs.yaml
```

### Step 3: Verify Deployment

Check that the CronJobs have been created:

```bash
kubectl get cronjobs -n monitoring
```

**Example output (NVIDIA GPU clusters):**

```
NAME                                       SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
active-health-checks-dcgm-diag-applier     0 * * * *     False     0        <none>          10s
active-health-checks-gpu-fryer-applier     0 * * * *     False     0        <none>          10s
active-health-checks-nccl-tests-applier    0 * * * *     False     0        <none>          10s
```

**Example output (AMD GPU clusters):**

```
NAME                                       SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
active-health-checks-rccl-tests-applier    0 * * * *     False     0        <none>          10s
active-health-checks-rvs-applier           0 * * * *     False     0        <none>          10s
```

## Node Selection Logic

All health checks follow this selection process:

1. **Find GPU Nodes**: Query nodes with appropriate GPU label
   - NVIDIA tests: `nvidia.com/gpu=true` label
   - AMD tests: `amd.com/gpu=true` label
2. **Check Idle Status**: Calculate GPU usage from pod requests
   - Only nodes with 0 GPU allocation are considered
3. **Check Last Run**: Parse `*-last-run` timestamp label
   - Skip nodes tested today (same UTC date)
4. **Select Nodes**:
   - NCCL/RCCL: Pick 2+ nodes of same shape
   - GPU Fryer: Pick 1 node
   - RVS: Pick 1 node
   - DCGM: Pick 1 node

This ensures:
- Production workloads are never disrupted
- Each node is tested at most once per day
- Tests run on available capacity

## Monitoring Health Check Results

### View Node Labels

Check the health status labels on a specific node:

```bash
kubectl get node <node-name> --show-labels | grep active-health-checks
```

View all nodes with their health check labels:

**For NVIDIA GPU nodes:**
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,NCCL:.metadata.labels.oke\.oraclecloud\.com/active-health-checks-nccl-tests,GPU_FRYER:.metadata.labels.oke\.oraclecloud\.com/active-health-checks-gpu-fryer,DCGM:.metadata.labels.oke\.oraclecloud\.com/active-health-checks-dcgm-diag
```

**For AMD GPU nodes:**
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,RCCL:.metadata.labels.oke\.oraclecloud\.com/active-health-checks-rccl-tests,RVS:.metadata.labels.oke\.oraclecloud\.com/active-health-checks-rvs
```

### Identify Failed Nodes

List nodes that have failed any health check:

```bash
# NVIDIA GPU nodes
kubectl get nodes -l oke.oraclecloud.com/active-health-checks-nccl-tests=fail -o wide
kubectl get nodes -l oke.oraclecloud.com/active-health-checks-gpu-fryer=fail -o wide
kubectl get nodes -l oke.oraclecloud.com/active-health-checks-dcgm-diag=fail -o wide

# AMD GPU nodes
kubectl get nodes -l oke.oraclecloud.com/active-health-checks-rccl-tests=fail -o wide
kubectl get nodes -l oke.oraclecloud.com/active-health-checks-rvs=fail -o wide
```

### View Health Check Job Logs

Check the logs of recent health check jobs:

```bash
# List recent jobs
kubectl get jobs -n monitoring

# View logs from a specific job
kubectl logs -n monitoring job/<job-name>
```

## Manual Test Execution

To manually trigger a health check outside the regular schedule:

```bash
# Create a one-off job from the CronJob
# NVIDIA GPU tests
kubectl create job -n monitoring manual-nccl-test --from=cronjob/active-health-checks-nccl-tests-applier
kubectl create job -n monitoring manual-fryer-test --from=cronjob/active-health-checks-gpu-fryer-applier
kubectl create job -n monitoring manual-dcgm-test --from=cronjob/active-health-checks-dcgm-diag-applier

# AMD GPU tests
kubectl create job -n monitoring manual-rccl-test --from=cronjob/active-health-checks-rccl-tests-applier
kubectl create job -n monitoring manual-rvs-test --from=cronjob/active-health-checks-rvs-applier
```

To run a test immediately on a specific node, you can temporarily modify the node labels to remove the last-run timestamp:

```bash
# For NVIDIA nodes
kubectl label node <node-name> oke.oraclecloud.com/active-health-checks-nccl-tests-last-run-

# For AMD nodes
kubectl label node <node-name> oke.oraclecloud.com/active-health-checks-rccl-tests-last-run-
kubectl label node <node-name> oke.oraclecloud.com/active-health-checks-rvs-last-run-
```

The next CronJob execution will then select this node for testing.

## Configuration

### Adjusting Test Schedule

By default, health checks run every hour (`0 * * * *`). To modify the schedule:

1. Edit the CronJob:
   ```bash
   kubectl edit cronjob active-health-checks-nccl-tests-applier -n monitoring
   ```

2. Update the `schedule` field to your desired cron expression.

### Customizing Test Parameters

Each health check manifest can be customized with different parameters:
- **NCCL Tests**: Number of nodes, GPU count, NCCL parameters
- **RCCL Tests**: Number of nodes, GPU count, RCCL parameters
- **GPU Fryer**: Stress duration, temperature thresholds
- **RVS**: Test recipe, iterations, timeout, validation tests
- **DCGM Diagnostics**: Diagnostic level, specific tests to run

Download and modify the manifests locally before applying them for custom configurations.

## Suspending Health Checks

To temporarily disable health checks (e.g., during maintenance):

```bash
# Suspend a specific health check
kubectl patch cronjob active-health-checks-nccl-tests-applier -n monitoring -p '{"spec":{"suspend":true}}'

# Resume the health check
kubectl patch cronjob active-health-checks-nccl-tests-applier -n monitoring -p '{"spec":{"suspend":false}}'
```

## Uninstalling

To remove active health checks:

**For NVIDIA GPU clusters:**
```bash
kubectl delete -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/active-health-checks/active-health-checks-nccl-tests.yaml
kubectl delete -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/active-health-checks/active-health-checks-gpu-fryer.yaml
kubectl delete -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/active-health-checks/active-health-checks-dcgm-diag.yaml
```

**For AMD GPU clusters:**
```bash
kubectl delete -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/active-health-checks/active-health-checks-rccl-tests.yaml
kubectl delete -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/active-health-checks/active-health-checks-rvs.yaml
```

> [!NOTE]
> Node labels applied by health checks will remain after uninstalling. To remove them, manually delete the labels from each node.
