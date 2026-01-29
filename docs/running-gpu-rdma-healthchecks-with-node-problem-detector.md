# Running GPU & RDMA Health Checks with Node Problem Detector

Node Problem Detector is a Kubernetes add-on that monitors node health and reports problems as node conditions and events. This guide explains how to deploy Node Problem Detector with custom health checks designed specifically for OKE GPU and RDMA nodes.

## Overview

These health checks provide continuous monitoring of GPU and RDMA functionality on your worker nodes. Issues are reported as Kubernetes node conditions, making them visible through standard kubectl commands and enabling integration with monitoring and alerting systems.

## Prerequisites

- OKE cluster with GPU nodes
- kubectl access with cluster-admin privileges
- Helm 3.x installed
- `jq` installed (for filtering node status)

## Available Health Checks

The following health checks are included. Note that depending on the node shape and configuration, some checks may not run. For example, RDMA checks only run on nodes deployed in a [Cluster Network](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/managingclusternetworks.htm#top).

| Name | Description |
|------|-------------|
| GpuCount | Checks if the node has the expected number of GPUs available |
| GpuEcc | Checks for GPU ECC errors |
| GpuRowRemap | Checks for GPU row remapping errors |
| GpuBus | Checks if any GPU has fallen off the bus |
| GpuPcie | Checks if PCIe has the expected bandwidth |
| GpuFabricManager | Checks if Fabric Manager is running (NVIDIA multi-GPU systems) |
| GpuBadPages | Checks if any AMD GPU has bad pages |
| GpuXid | Checks for GPU Xid errors in dmesg |
| NvlinkSpeed | Checks if NVLink speeds match expected values |
| DcgmiHealth | Runs DCGMI health check (NVIDIA GPUs) |
| Rocminfo | Runs rocminfo health check (AMD GPUs) |
| RdmaLink | Checks if RDMA links are up |
| RdmaLinkFlapping | Checks if any RDMA links are flapping |
| RdmaWpaAuth | Checks if all RDMA interfaces are authenticated |
| RdmaRttcc | Checks if RTTCC is disabled on the RDMA interfaces |
| IpAddress | Checks if all RDMA interfaces have an IP address |
| OcaVersion | Checks if the node has the correct Oracle Cloud Agent version |
| CpuProfile | Checks if the CPU profile is set to performance |

### Health Check Frequency

By default, health checks run every 5 minutes. You can modify the frequency by editing the `values.yaml` file before deployment.

## Deployment

Deploy Node Problem Detector using the Helm chart with the OKE-specific health check configuration:

```bash
helm install gpu-rdma-node-problem-detector oci://ghcr.io/deliveryhero/helm-charts/node-problem-detector --version 2.4.0 \
    -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/terraform/files/node-problem-detector/values.yaml
```

The health check scripts are included in the `values.yaml` file as a ConfigMap and will be automatically deployed to all GPU nodes.

### Verify Deployment

Check that the Node Problem Detector pods are running:

```bash
kubectl get pods -l app.kubernetes.io/name=node-problem-detector
```

**Example output:**

```
NAME                              READY   STATUS    RESTARTS   AGE
node-problem-detector-abc123      1/1     Running   0          2m
node-problem-detector-def456      1/1     Running   0          2m
node-problem-detector-ghi789      1/1     Running   0          2m
```

## Monitoring Node Health

> [!NOTE]
> After deployment, wait approximately 10 minutes before checking results. RDMA interfaces require time to configure during node boot, so initial checks like `RdmaLink` may report false positives.

### View Node Conditions

Health check results are reported as node conditions. View the conditions for a specific node:

```bash
kubectl describe node <node-name>
```

Look for the new condition types in the output. **Example output** (showing relevant sections):

```
Conditions:     
                                                                                                                                                                                                                  
    Type                    Status    Reason                        Message   
    ----                    ------    ------                        -------                  
    RdmaLinkFlapping        False     RdmaLinkFlappingHasNoIssues   No flapping RDMA links                    
    OcaVersion              False     OcaVersionHasNoIssues         OCA version is up to date   
    GpuRowRemap             False     GpuRowRemapHasNoIssues        No Row Remapping issues detected with GPUs
    RdmaWpaAuth             False     RdmaWpaAuthHasNoIssues        All RDMA links are authenticated          
    RdmaRttcc               False     RdmaRttccHasNoIssues          RTCCC is disabled on all RDMA interfaces  
    GpuEcc                  False     GpuEccHasNoIssues             No ECC issues detected with GPUs          
    GpuBus                  False     GpuBusHasNoIssues             No GPU Bus issues detected with GPUs      
    GpuCount                True      GpuCountHasIssues             Node has missing GPU(s)                   
    RdmaLink                False     RdmaLinkHasNoIssues           All RDMA links are up                     
```

In this example, the node has one issue: `GpuCount` shows `Status: True` with `Reason: GpuCountHasIssues`, indicating the node is missing one or more GPUs. All other checks show `Status: False`, meaning they passed (no issues detected).

### List Nodes with Issues

To get a summary of all GPU nodes with problems:

```bash
kubectl get nodes -o json | jq -r '.items[]
| select (.metadata.labels."nvidia.com/gpu" == "true" or .metadata.labels."amd.com/gpu" == "true")
| { name: .metadata.name, ocid: .spec.providerID, serial: .metadata.labels["oci.oraclecloud.com/host.serial_number"], error: .status.conditions[]
| select(.reason | test("^(Gpu|Rdma|Oca|Cpu).*HasIssues$")) | .message }
| "\(.name)\t\(.ocid)\t\(.serial)\t\(.error)"'
```

**Example output:**

```
10.140.30.89    ocid1.instance.oc1.ap-melbourne-1.anww...   2210xcr0bv  Node has missing GPU(s)
```

This command filters GPU nodes and displays only those with issues, showing the node name, OCID, serial number, and the specific error message.

### Understanding Node Conditions

Node conditions use the following format:

- **Type**: The name of the health check (e.g., `GpuCount`, `RdmaLink`)
- **Status**: 
  - `False` = No issues detected (healthy)
  - `True` = Issues detected (unhealthy)
- **Reason**: A coded reason (e.g., `GpuCountHasNoIssues`, `GpuCountHasIssues`)
- **Message**: A human-readable description of the issue

## Uninstalling

To remove Node Problem Detector:

```bash
helm uninstall gpu-rdma-node-problem-detector
```

> [!NOTE]
> Node conditions created by health checks will remain on nodes after uninstalling. They will eventually be removed by Kubernetes garbage collection or can be manually removed.
