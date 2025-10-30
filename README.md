# Running RDMA GPU Workloads on OKE with NVIDIA GPU Operator and Network Operator

> [!IMPORTANT]
> Using Virtual Functions (VFs) for RDMA is currently not a supported configuration on OKE. This guide is provided for experimental and testing purposes only.

## Overview

This guide provides step-by-step instructions for deploying an Oracle Kubernetes Engine (OKE) cluster with GPU nodes and RDMA (Remote Direct Memory Access) connectivity. The setup enables high-performance GPU workloads with low-latency RDMA networking using SR-IOV Virtual Functions.

## Prerequisites

- An OKE cluster with both CPU and GPU node pools
- `kubectl` configured to access your cluster
- Cluster admin permissions

## Node Images

### GPU Node Requirements

GPU nodes require a specialized image with pre-configured OFED drivers and RDMA packages. The image must have RDMA subsystem namespace awareness mode set to `exclusive`:

```bash
echo "options ib_core netns_mode=0" >> /etc/modprobe.d/ib_core.conf
```

### Available Images

**CPU Nodes (Non-GPU)**
- [Canonical Ubuntu 22.04 - OKE Optimized (2025.03.28)](https://objectstorage.us-chicago-1.oraclecloud.com/p/O1VP9Rx0p7uWKRQW6739ZzTbnUPK5F8cvlN0apUaiO_cF5x9R2ESYN6yskW0FUVq/n/hpc_limited_availability/b/oke-images-do-not-delete/o/Canonical-Ubuntu-22.04-2025.03.28-0-OKE)

**GPU Nodes (NVIDIA Shapes)**
- [Ubuntu 22.04 with GPU Driver 570, CUDA 12.8, OFED 24.10 (2025.03.26)](https://objectstorage.us-ashburn-1.oraclecloud.com/p/_DA3uxLCkOCLniSkfce_xyS1AOyBsqxHyWpLHkjb3lNshklPur2VuX3jLkLPcbPZ/n/hpc_limited_availability/b/images/o/Canonical-Ubuntu-22.04-2024.10.04-0-OCA-OFED-24.10-1.1.4.0-GPU-570-CUDA-12.8-2025.03.26-0-VF)

> [!NOTE]
> For non-GPU worker pools, you can use the default OKE images without modifications.

## Deployment Steps

### 1. Verify Cluster Nodes

Wait for all nodes to be in `Ready` state:

```bash
kubectl get nodes
```

Example output:
```
NAME            STATUS   ROLES    AGE     VERSION
10.140.48.77    Ready    node     4h32m   v1.32.1
10.140.49.170   Ready    <none>   4h22m   v1.32.1
10.140.51.249   Ready    node     4h33m   v1.32.1
```

### 2. Install Helm 3

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

### 3. Add NVIDIA Helm Repository

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### 4. Deploy NVIDIA GPU Operator

Install the GPU Operator with RDMA support enabled:

```bash
helm install --wait \
  -n gpu-operator --create-namespace \
  gpu-operator nvidia/gpu-operator \
  --version v25.10.0 \
  --set driver.enabled=false \
  --set driver.rdma.enabled=true \
  --set driver.rdma.useHostMofed=true
```

Verify all GPU Operator pods are running:

```bash
kubectl get pods -n gpu-operator
```

### 5. Deploy NVIDIA Network Operator

Install the Network Operator with SR-IOV support:

```bash
helm install network-operator nvidia/network-operator \
  -n nvidia-network-operator \
  --create-namespace \
  --version v25.7.0 \
  --set nfd.enabled=false \
  --set sriovNetworkOperator.enabled=true
```

Verify all Network Operator pods are running:

```bash
kubectl get pods -n nvidia-network-operator
```

### 6. Configure NIC Cluster Policy

Create the NIC Cluster Policy to enable secondary network capabilities:

```yaml
cat <<'EOF' > nic-cluster-policy.yaml
apiVersion: mellanox.com/v1alpha1
kind: NicClusterPolicy
metadata:
  name: nic-cluster-policy
spec:
  nvIpam:
    image: nvidia-k8s-ipam
    repository: nvcr.io/nvidia/mellanox
    version: network-operator-v25.7.0
    enableWebhook: false
  secondaryNetwork:
    cniPlugins:
      image: plugins
      repository: nvcr.io/nvidia/mellanox
      version: network-operator-v25.7.0
    multus:
      image: multus-cni
      repository: nvcr.io/nvidia/mellanox
      version: network-operator-v25.7.0
EOF
```

Apply the policy:

```bash
kubectl apply -f nic-cluster-policy.yaml
```

### 7. Enable additinonal configuration for SRIOV Network Operator (Recommended)

Enable parallel NIC configuration for faster deployment:

```bash
kubectl patch sriovoperatorconfigs.sriovnetwork.openshift.io \
  -n nvidia-network-operator default \
  --patch '{"spec": {"featureGates": {"parallelNicConfig": true}}}' \
  --type='merge'
```

Change configuration mode to `systemd` for better reliability:

```bash
kubectl patch sriovoperatorconfigs.sriovnetwork.openshift.io \
  -n nvidia-network-operator default \
  --patch '{"spec": {"configurationMode": "systemd"}}' \
  --type='merge'
```

### 8. Create IP Pool for NVIDIA IPAM

Configure the IP address pool for SR-IOV network interfaces:

```yaml
cat <<'EOF' > nv-ipam-ip-pool.yaml
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: IPPool
metadata:
  name: sriov-pool
  namespace: nvidia-network-operator
spec:
  subnet: 192.168.0.0/16
  perNodeBlockSize: 100
  gateway: 192.168.0.1
EOF
```

Apply the IP pool:

```bash
kubectl apply -f nv-ipam-ip-pool.yaml
```

## SR-IOV Configuration

### 9. Create SR-IOV Network Node Policy

This step creates Virtual Functions (VFs) on your GPU nodes.

> [!IMPORTANT]
> After applying the SR-IOV Network Node Policy, the affected nodes will be **drained and rebooted** automatically by the SR-IOV Network Operator. This is expected behavior.

The example below configures VFs for the `BM.GPU.B4.8` (A100) shape. For other GPU shapes, see:
- [All GPU shapes combined policy](./manifests/sriov-network-node-policy.yaml)
- [Individual shape policies](./manifests/sriov-network-node-policy/)

**Example for BM.GPU.B4.8:**

```yaml
cat <<'EOF' > BM.GPU.B4.8-policy.yaml
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
  name: bm-gpu-b4-8
  namespace: nvidia-network-operator
spec:
  deviceType: netdevice
  mtu: 4220
  nicSelector:
    rootDevices:
    - 0000:0c:00.0
    - 0000:0c:00.1
    - 0000:16:00.0
    - 0000:16:00.1
    - 0000:47:00.0
    - 0000:47:00.1
    - 0000:4b:00.0
    - 0000:4b:00.1
    - 0000:89:00.0
    - 0000:89:00.1
    - 0000:93:00.0
    - 0000:93:00.1
    - 0000:c3:00.0
    - 0000:c3:00.1
    - 0000:d1:00.0
    - 0000:d1:00.1
    vendor: "15b3"
  nodeSelector:
    node.kubernetes.io/instance-type: "BM.GPU.B4.8"
  isRdma: true
  numVfs: 1
  priority: 90
  resourceName: sriov-rdma-vf
EOF
```

Apply the policy:

```bash
kubectl apply -f BM.GPU.B4.8-policy.yaml
```

### 10. Configure Node Reboot Behavior

Control the percentage of nodes that can reboot concurrently during VF configuration. The example below allows 100% of `BM.GPU.B4.8` nodes to reboot simultaneously.

> [!TIP]
> For production environments, consider using a lower percentage (e.g., `25%` or `50%`) to maintain cluster availability during VF configuration.

```yaml
cat <<'EOF' > sriov-network-pool-config-percentage.yaml
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkPoolConfig
metadata:
  name: bm-gpu-b4-8
  namespace: nvidia-network-operator
spec:
  maxUnavailable: "100%"
  nodeSelector:
    matchExpressions:
      - key: node.kubernetes.io/instance-type
        operator: In
        values:
          - BM.GPU.B4.8
EOF
```

Apply the configuration:

```bash
kubectl apply -f sriov-network-pool-config-percentage.yaml
```

### 11. Create SR-IOV Network Resource

Define the SR-IOV network that pods can attach to:

```yaml
cat <<'EOF' > sriovnetwork.yaml
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetwork
metadata:
  name: sriov-rdma-vf
  namespace: nvidia-network-operator
spec:
  resourceName: sriov-rdma-vf
  networkNamespace: default
  spoofChk: "off"
  ipam: |
    {
      "type": "nv-ipam",
      "poolName": "sriov-pool"
    }
  metaPlugins: |
    {
      "type": "tuning",
      "sysctl": {
        "net.ipv4.conf.all.arp_announce": "2",
        "net.ipv4.conf.all.arp_filter": "1",
        "net.ipv4.conf.all.arp_ignore": "1",
        "net.ipv4.conf.all.rp_filter": "0",
        "net.ipv4.conf.all.accept_local": "1"
      },
      "mtu": 4220
    },
    {
      "type": "rdma"
    },
    {
      "type": "sbr"
    }
EOF
```

Apply the network definition:

```bash
kubectl apply -f sriovnetwork.yaml
```

## Verification

### 12. Verify VF Allocation

After the nodes reboot and SR-IOV configuration completes, verify that Virtual Functions are correctly exposed:

```bash
kubectl get nodes -l 'nvidia.com/gpu=true' \
  --sort-by=.status.capacity.\"nvidia\\.com/gpu\" \
  -o=custom-columns='NODE:metadata.name,GPUs:status.capacity.nvidia\\.com/gpu,RDMA-VFs:status.capacity.nvidia\\.com/sriov-rdma-vf'
```

Expected output:
```
NODE            GPUs   RDMA-VFs
10.79.148.115   8      16
10.79.151.167   8      16
10.79.156.205   8      16
```

> [!NOTE]
> By default, one Virtual Function is created per Physical Function. For H100 and A100 bare metal shapes with 16 physical NICs, you will see 16 VFs per node.

### Using RDMA VFs in Pod Manifests

To attach RDMA VFs to your pods, add the network annotation and resource limits. Each `sriov-rdma-vf` entry in the annotation requests one VF:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rdma-test
spec:
  containers:
  - name: app
    image: your-image
    resources:
      limits:
        nvidia.com/gpu: 8
        nvidia.com/sriov-rdma-vf: 16
  template:
    metadata:
      annotations:
        # Request 16 RDMA VFs (one per comma-separated entry)
        k8s.v1.cni.cncf.io/networks: sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf
```

## Running the NCCL tests (Optional)

### 13. Deploy Kueue & MPI Operator

To validate RDMA connectivity and GPU performance, install Kueue for job queueing and the MPI Operator for multi-node workloads:

```bash
# Install MPI Operator
kubectl apply --server-side -f https://raw.githubusercontent.com/kubeflow/mpi-operator/v0.6.0/deploy/v2beta1/mpi-operator.yaml

# Install Kueue
helm install kueue oci://registry.k8s.io/kueue/charts/kueue \
  --version="0.14.2" \
  --create-namespace \
  --namespace=kueue-system
```

### 14. Run NCCL tests

The NCCL test validates RDMA performance between GPU nodes. Deploy the test with the following manifest:

```yaml
cat <<'EOF' > nccl-tests.yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata:
  name: bm-gpu-b4-8
spec:
  nodeLabels:
    node.kubernetes.io/instance-type: BM.GPU.B4.8
    nvidia.com/gpu: "true"
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: bm-gpu-b4-8-nccl-tests-queue
spec:
  namespaceSelector: {}
  resourceGroups:
  - coveredResources: ["cpu", "memory", "nvidia.com/gpu", "nvidia.com/sriov-rdma-vf", "ephemeral-storage"]
    flavors:
    - name: bm-gpu-b4-8
      resources:
      - name: cpu
        nominalQuota: "20000"
      - name: memory
        nominalQuota: "102400Gi"
      - name: nvidia.com/gpu
        nominalQuota: "1600"
      - name: nvidia.com/sriov-rdma-vf
        nominalQuota: "3200"
      - name: ephemeral-storage
        nominalQuota: "6400Gi"
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: bm-gpu-b4-8-nccl-tests
spec:
  clusterQueue: bm-gpu-b4-8-nccl-tests-queue
---
apiVersion: kubeflow.org/v2beta1
kind: MPIJob
metadata:
  name: nccl-test
  labels:
    kueue.x-k8s.io/queue-name: bm-gpu-b4-8-nccl-tests
spec:
  slotsPerWorker: 8
  runPolicy:
    cleanPodPolicy: "Running"
  sshAuthMountPath: /root/.ssh
  mpiReplicaSpecs:
    Launcher:
      replicas: 1
      template:
        metadata:
          labels:
            nccl-test-replica: mpi-launcher
        spec:
          hostNetwork: true
          dnsPolicy: ClusterFirstWithHostNet
          containers:
          - name: mpi-launcher
            image: iad.ocir.io/hpc_limited_availability/nccl-tests:pytorch-25.03-nccl-2.26.6-1
            ports:
            - { name: mpijob-port, containerPort: 2222, protocol: TCP }
            command: ["bash", "-c"]
            args:
              - |
                set -e -o pipefail; trap 'exit=1' SIGINT
                NUM_GPUS=8
                NUM_HOSTS=$(sed -n '$=' /etc/mpi/hostfile)
                NP=$(($NUM_HOSTS*$NUM_GPUS))
                while ! (for host in $(awk '{print $1}' /etc/mpi/hostfile); do ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p 2222 $host exit 2>/dev/null || exit 1; done); do
                  echo "Waiting for workers to be ready..."
                  sleep 5
                done
                echo "All workers are ready!"
                mpirun --allow-run-as-root \
                  -mca coll ^hcoll  -mca plm_rsh_args "-p 2222" \
                  -mca coll_hcoll_enable 0 \
                  -np $NP -npernode $NUM_GPUS --bind-to numa \
                  -x NCCL_DEBUG=WARN \
                  -x NCCL_IB_SPLIT_DATA_ON_QPS=0 \
                  -x NCCL_IB_QPS_PER_CONNECTION=4 \
                  -x NCCL_IB_GID_INDEX=3 \
                  -x NCCL_IB_HCA==mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_14,mlx5_15,mlx5_16,mlx5_17,mlx5_9,mlx5_10,mlx5_11,mlx5_12 \
                  -x NCCL_IB_TC=41 \
                  -x NCCL_IB_SL=0 \
                  -x NCCL_IB_TIMEOUT=22 \
                  -x HCOLL_ENABLE_MCAST_ALL=0 \
                  -x UCX_TLS=tcp \
                  -x UCX_NET_DEVICES=eth0 \
                  /workspace/nccl-tests/build/all_reduce_perf -b 1G -f 2 -g 1 -e 4G -c 1
    Worker:
      replicas: 2
      template:
        metadata:
          labels:
            nccl-test-replica: mpi-worker
          annotations:
            k8s.v1.cni.cncf.io/networks: sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf
        spec:
          hostNetwork: true
          dnsPolicy: ClusterFirstWithHostNet
          volumes:
          - { name: devinf, hostPath: { path: /dev/infiniband }}
          - { name: shm, emptyDir: { medium: Memory, sizeLimit: 32Gi }}
          containers:
          - name: mpi-worker
            ports:
            - { name: mpijob-port, containerPort: 2222, protocol: TCP }
            volumeMounts:
            - { mountPath: /dev/infiniband, name: devinf }
            - { mountPath: /dev/shm, name: shm }
            securityContext:
              privileged: true
              capabilities:
                add: ["IPC_LOCK"]
            image: iad.ocir.io/hpc_limited_availability/nccl-tests:pytorch-25.03-nccl-2.26.6-1
            command:
              - /bin/bash
              - -c
              - mkdir -p /var/run/sshd; /usr/sbin/sshd -D -p 2222;
            resources:
              limits:
                nvidia.com/gpu: 8
                nvidia.com/sriov-rdma-vf: 16
EOF
```

Apply the manifest:

```bash
kubectl apply -f nccl-tests.yaml
```

### 15. Monitor NCCL tests Results

Wait for the container image to pull (this may take several minutes on first run). Once the launcher pod starts, check the logs:

```bash
# Wait for pods to be ready
kubectl get pods -l nccl-test-replica

# View launcher logs
kubectl logs -f nccl-test-launcher-<pod-id>
```

Expected output excerpt:

```
# nThread 1 nGpus 1 minBytes 8 maxBytes 8589934592 step: 2(factor) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid     43 on nccl-allreduce-job0-mpiworker-0 device  0 [0x0f] NVIDIA A100-SXM4-40GB
#  Rank  1 Group  0 Pid     44 on nccl-allreduce-job0-mpiworker-0 device  1 [0x15] NVIDIA A100-SXM4-40GB
#  ...
#  Rank 15 Group  0 Pid     50 on nccl-allreduce-job0-mpiworker-1 device  7 [0xda] NVIDIA A100-SXM4-40GB
#
#                                                              out-of-place                       in-place
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
  ...
  8589934592    2147483648     float     sum      -1    67689  126.90  237.94      0    67811  126.68  237.52      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 66.4834
#
```
