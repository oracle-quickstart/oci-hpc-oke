# Running cluster-healthchecks Workloads

This chart deploys a **DaemonSet** that runs continuous passive checks on GPU nodes, managed by Terraform.

## Prerequisites

- Access to the Kubernetes cluster used by this stack.

## Deploy via Terraform

Set the following variables:

- `install_cluster_healthchecks = true`
- `cluster_healthchecks_image_repository = "iad.ocir.io/iduyx1qnmway/lens-metric-collector/oci-dr-hpc-v2"`
- `cluster_healthchecks_image_tag = "cuda-12.6.0-1.0.103"`

Optional:

- `cluster_healthchecks_image_pull_secrets = ["cluster-healthchecks-ocir-secret"]` (if your OCIR repo requires auth)
- `cluster_healthcheck_verbose`

## Terraform Note

Terraform creates the Object Storage bucket and passes its name/namespace into the Helm values automatically.

## CLI Quick Actions

Start active test:

1. Set test name and apply the on-demand Job:

```bash
TESTNAME=mytest envsubst < manifests/cluster-health-checks/cluster-healthchecks-active-job.yaml | kubectl apply -f -
```

2. If Kueue is enabled and the Job is suspended, unsuspend it:

```bash
kubectl patch job cluster-healthchecks-active -n cluster-healthchecks -p '{"spec":{"suspend":false}}'
```

Stop passive test:

1. Disable the Helm release via Terraform:

```bash
# in tfvars or UI
install_cluster_healthchecks = false
```

2. Re-apply Terraform.

Check results:

1. List recent pods:

```bash
kubectl get pods -n cluster-healthchecks
```

2. View logs:

```bash
kubectl logs -n cluster-healthchecks -l app=cluster-healthchecks-passive --tail=200
```

## Node Label Controls

Disable passive checks on specific nodes:

```bash
kubectl label node <node> cluster-healthchecks=disabled
```

Enable active checks only on labeled nodes:

```bash
kubectl label node <node> cluster-healthchecks-active=true
```

## Full Workflow

Select nodes:

1. List GPU nodes:

```bash
kubectl get nodes -l nvidia.com/gpu=true
kubectl get nodes -l amd.com/gpu=true
```

2. (Optional) Exclude passive checks on specific nodes:

```bash
kubectl label node <node> cluster-healthchecks=disabled
```

3. (Required for active tests) Mark nodes eligible for active jobs:

```bash
kubectl label node <node> cluster-healthchecks-active=true
```

Install passive checks:

1. Set `install_cluster_healthchecks = true` in your stack inputs.
2. Apply Terraform.

Active checks (on-demand):

1. Set a test name and apply the Job manifest:

```bash
TESTNAME=mytest envsubst < manifests/cluster-health-checks/cluster-healthchecks-active-job.yaml | kubectl apply -f -
```

2. If Kueue is enabled and the Job is suspended, unsuspend it:

```bash
kubectl patch job cluster-healthchecks-active -n cluster-healthchecks -p '{"spec":{"suspend":false}}'
```

Disable passive checks:

Option A: Disable all passive checks (remove the DaemonSet):

1. Set `install_cluster_healthchecks = false`.
2. Apply Terraform.

Option B: Disable passive checks on specific nodes:

```bash
kubectl label node <node> cluster-healthchecks=disabled
```
