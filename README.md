# Running RDMA (remote direct memory access) GPU workloads on OKE using GPU Operator and Network Operator

> [!IMPORTANT]  
> Using virtual functions for RDMA is currently not a supported configuration on OKE.

## Instructions for deploying an OKE cluster with GPUs and RDMA connectivity

You will need a CPU and a GPU pool. The Terraform template deploys an operational/system worker pool (CPU) and a GPU worker pool.

The GPU pool requires you to use an image provided by the Oracle HPC team, you can find the import link below. This image included the OFED drivers and necessary packages configured for RDMA.

For the non-GPU worker pools, you can use the default OKE images (no need to specify them in the Terraform template).

#### Images to use
It's important to have the below settings in your image. The GPU image listed below has those already, so you can use it without needing any changes.

- Set RDMA subsystem namespace awareness mode to `exclusive` via `ib_core` module parameter:
```
echo "options ib_core netns_mode=0" >> /etc/modprobe.d/ib_core.conf
```

**Image to use for non-GPU nodes**

- [Link to import the image](https://objectstorage.us-chicago-1.oraclecloud.com/p/O1VP9Rx0p7uWKRQW6739ZzTbnUPK5F8cvlN0apUaiO_cF5x9R2ESYN6yskW0FUVq/n/hpc_limited_availability/b/oke-images-do-not-delete/o/Canonical-Ubuntu-22.04-2025.03.28-0-OKE)

**Images for NVIDIA shapes**

- [GPU driver 570 & CUDA 12.8](https://objectstorage.us-ashburn-1.oraclecloud.com/p/_DA3uxLCkOCLniSkfce_xyS1AOyBsqxHyWpLHkjb3lNshklPur2VuX3jLkLPcbPZ/n/hpc_limited_availability/b/images/o/Canonical-Ubuntu-22.04-2024.10.04-0-OCA-OFED-24.10-1.1.4.0-GPU-570-CUDA-12.8-2025.03.26-0-VF)

### Wait until you see all nodes in the cluster

```sh
kubectl get nodes

NAME            STATUS   ROLES    AGE     VERSION
10.140.48.77    Ready    node     4h32m   v1.32.1
10.140.49.170   Ready    <none>   4h22m   v1.32.1
10.140.51.249   Ready    node     4h33m   v1.32.1
10.140.57.93    Ready    <none>   4h22m   v1.32.1
10.140.58.183   Ready    node     4h32m   v1.32.1
```

### Get the latest Helm 3 version
```sh
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

### Add Helm repos for Network Operator and GPU Operator
```sh
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### Deploy GPU Operator
```
helm install --wait \
  -n gpu-operator --create-namespace \
  gpu-operator nvidia/gpu-operator \
  --version v25.3.0 \
  --set driver.enabled=false \
  --set driver.rdma.enabled=true \
  --set driver.rdma.useHostMofed=true \
  --set dcgmExporter.version=4.2.3-4.1.1-ubuntu22.04
```

Wait until all network operator pods are running with `kubectl get pods -n gpu-operator`.

### Deploy Network Operator

```
helm install network-operator nvidia/network-operator \
   -n nvidia-network-operator \
   --create-namespace \
   --version v25.1.0 \
   --set nfd.enabled=false \
   --set sriovNetworkOperator.enabled=true
```

Wait until all network operator pods are running with `kubectl get pods -n nvidia-network-operator`.

### Create a NIC Cluster Policy

```yaml
cat <<EOF > nic-cluster-policy.yaml
apiVersion: mellanox.com/v1alpha1
kind: NicClusterPolicy
metadata:
   name: nic-cluster-policy
spec:
   secondaryNetwork:
     cniPlugins:
       image: plugins
       repository: ghcr.io/k8snetworkplumbingwg
       version: v1.5.0
       imagePullSecrets: []
     multus:
       image: multus-cni
       repository: ghcr.io/k8snetworkplumbingwg
       version: v4.1.0
       imagePullSecrets: []
   nvIpam:
     image: nvidia-k8s-ipam
     repository: ghcr.io/mellanox
     version: v0.3.7
     enableWebhook: false
EOF
```

```
kubectl apply -f nic-cluster-policy.yaml
```

### Enable Parallel NIC Configuration for SR-IOV and change configuration mode to `systemd` (optional but recommended)

```
kubectl patch sriovoperatorconfigs.sriovnetwork.openshift.io -n nvidia-network-operator default --patch '{ "spec": { "featureGates": { "parallelNicConfig": true  } } }' --type='merge'

kubectl patch sriovoperatorconfigs.sriovnetwork.openshift.io -n nvidia-network-operator default --patch '{ "spec": { "configurationMode": "systemd"} }' --type='merge'
```

### Create an SRIOV Network Node Policy to create the Virtual Functions (VFs)
After the VFs are created, the nodes will be drained and rebooted by the SRIOV Network Operator. Below is an example for the BM.GPU.B4.8 A100 shape.

You can find the node policies in the [manifests/sriov-network-node-policy](manifests/sriov-network-node-policy) directory.

```yaml
cat <<EOF > BM.GPU.B4.8-policy.yaml
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

```
kubectl apply -f BM.GPU.B4.8-policy.yaml
```

### Create an SRIOV Network Pool Config
As mentioned in the previous step, the nodes will reboot after the VFs are created. You can create the percentage of concurrent reboots using a SRIOV Network Pool Config. Below example reboots all nodes that VFs are configured.

```yaml
cat <<EOF > sriov-network-pool-config-percentage.yaml
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

```
kubectl apply -f sriov-network-pool-config-percentage.yaml
```

### Create an IP Pool for Nvidia IPAM

```yaml
cat <<EOF > nv-ipam-ip-pool.yaml
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: IPPool
metadata:
  name: my-pool
  namespace: nvidia-network-operator
spec:
  subnet: 192.168.0.0/16
  perNodeBlockSize: 100
  gateway: 192.168.0.1
EOF
```

```
kubectl apply -f nv-ipam-ip-pool.yaml
```

### Create a Network Attachment Definition

```yaml
cat <<EOF > network-attachment-definition.yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  annotations:
    k8s.v1.cni.cncf.io/resourceName: nvidia.com/sriov-rdma-vf
  name: sriov-rdma-vf
  namespace: default
spec:
  config: |-
    {
      "cniVersion": "1.0.0",
      "name": "sriov-rdma-vf",
      "plugins": [
        {
          "type": "sriov",
          "spoofchk": "off",
          "ipam": {
            "type": "nv-ipam",
            "poolName": "my-pool"
          }
        },
        { "type": "tuning",
          "sysctl": {
            "net.ipv4.conf.all.arp_announce": "2",
            "net.ipv4.conf.all.arp_filter": "1",
            "net.ipv4.conf.all.arp_ignore": "1",
            "net.ipv4.conf.all.rp_filter": "0",
            "net.ipv4.conf.all.accept_local": "1"
          },
          "mtu": 4220
        },
        { "type": "rdma" },
        { "type": "sbr" }
      ]
    }
EOF
```

```
kubectl apply -f network-attachment-definition.yaml
```

### Deploy RDMA CNI daemonset

```yaml
cat <<EOF > rdma-cni-daemonset.yaml
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-rdma-cni-ds
  namespace: kube-system
  labels:
    tier: node
    app: rdma-cni
    name: rdma-cni
spec:
  selector:
    matchLabels:
      name: rdma-cni
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        tier: node
        app: rdma-cni
        name: rdma-cni
    spec:
      hostNetwork: true
      tolerations:
        - operator: Exists
          effect: NoSchedule
      containers:
        - name: rdma-cni
          image: ghcr.io/k8snetworkplumbingwg/rdma-cni
          imagePullPolicy: IfNotPresent
          securityContext:
            privileged: true
          resources:
            requests:
              cpu: "100m"
              memory: "50Mi"
            limits:
              cpu: "100m"
              memory: "50Mi"
          volumeMounts:
            - name: cnibin
              mountPath: /host/opt/cni/bin
      volumes:
        - name: cnibin
          hostPath:
            path: /opt/cni/bin
EOF
```

```
kubectl apply -f rdma-cni-daemonset.yaml
```

### Confirm that the GPUs are Virtual Functions (VFs) are correctly exposed
Once the Network Operator pods are deployed, the GPU nodes with RDMA NICs will start reporting `nvidia.com/sriov-rdma-vf` as an available resource. You can request that resource in your pod manifests for assigning RDMA VFs to pods.

By default, we create one Virtual Function per Physical Function. So for the H100 and A100 bare metal shapes, you will see 16 VFs per node exposed as a resource.

```
kubectl get nodes -l 'node.kubernetes.io/instance-type in (BM.GPU.H100.8, BM.GPU.A100-v2.8, BM.GPU4.8, BM.GPU.B4.8)' --sort-by=.status.capacity."nvidia\.com/gpu" -o=custom-columns='NODE:metadata.name,GPUs:status.capacity.nvidia\.com/gpu,RDMA-VFs:status.capacity.nvidia\.com/sriov-rdma-vf'
```

```
NODE            GPUs   RDMA-VFs
10.79.148.115   8      16
10.79.151.167   8      16
10.79.156.205   8      16
```

### Requesting VFs in manifests
Network Operator exposes the RDMA Virtual Functions (VFs) as allocatable resources. To use them, you need to add the following annotation to your manifests. The next step in this guide has an example for running the NCCL test, you can use that manifest as an example.

```yaml
      template:
        metadata:
          annotations:
            k8s.v1.cni.cncf.io/networks: sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf
```

### Optional - Deploy Volcano and run the NCCL test
Volcano is needed for running the optional NCCL test. It's not required for the regular operation of the cluster, you can remove it after you finish running the NCCL test.

#### Deploy Volcano
```sh
helm repo add volcano-sh https://volcano-sh.github.io/helm-charts
helm install volcano volcano-sh/volcano -n volcano-system --create-namespace

kubectl create serviceaccount -n default mpi-worker-view
kubectl create rolebinding default-view --namespace default --serviceaccount default:mpi-worker-view --clusterrole view
```

#### Run the NCCL test

```yaml
cat <<'EOF' > nccl-tests-nv-ipam-ippool.yaml
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: nccl-allreduce-job0
spec:
  minAvailable: 1
  schedulerName: volcano
  plugins:
    ssh: []
    svc: []
  queue: default
  tasks:
    - replicas: 1
      name: mpimaster
      policies:
        - event: TaskCompleted
          action: CompleteJob
      template:
        spec:
          volumes:
            - name: root
              hostPath:
                path: /
                type: Directory
          initContainers:
            - command:
                - /bin/bash
                - -c
                - |
                  until [[ "$(kubectl get pod -l volcano.sh/job-name=nccl-allreduce-job0,volcano.sh/task-spec=mpiworker -o json | jq '.items | length')" != 0 ]]; do
                    echo "Waiting for MPI worker pods..."
                    sleep 3
                  done
                  echo "Waiting for MPI worker pods to be ready..."
                  kubectl wait pod -l volcano.sh/job-name=nccl-allreduce-job0,volcano.sh/task-spec=mpiworker --for=condition=Ready --timeout=600s && sleep 2
              image: aga.ocir.io/hpc_limited_availability/oke/kubectl:latest
              name: wait-for-workers
          serviceAccount: mpi-worker-view
          terminationGracePeriodSeconds: 2
          tolerations:
            - key: nvidia.com/gpu
              operator: Exists
          containers:
            - command:
                - /bin/bash
                - -c
                - |
                  MPI_HOST=$(cat /etc/volcano/mpiworker.host | tr "\n" ",")
                  mkdir -p /var/run/sshd; /usr/sbin/sshd
                  mpirun --allow-run-as-root \
                    -np 16 -npernode 8 --bind-to numa \
                    -hostfile /etc/volcano/mpiworker.host \
                    --mca pml ucx -mca coll ^hcoll \
                    -x HCOLL_ENABLE_MCAST_ALL=0 \
                    -x coll_hcoll_enable=0 \
                    -x UCX_NET_DEVICES=eth0 \
                    -x NCCL_IB_GID_INDEX=3 \
                    -x NCCL_IB_QPS_PER_CONNECTION=4 \
                    -x NCCL_IB_TC=41 \
                    -x NCCL_IB_SL=0 \
                    -x NCCL_IB_HCA=mlx5 \
                    /workspace/nccl-tests/build/all_reduce_perf -b 8 -f 2 -g 1 -e 8G -c 1; sleep 3600
              image: iad.ocir.io/hpc_limited_availability/nccl-tests:pytorch-25.03-nccl-2.26.6-1
              volumeMounts:
              - { mountPath: /host, name: root }
              securityContext:
                capabilities:
                  add: ["IPC_LOCK"]
              name: mpimaster
              ports:
                - containerPort: 22
                  name: mpijob-port
              workingDir: /workspace
              resources:
                requests:
                  cpu: 2
                  memory: 128Mi 
                  ephemeral-storage: 16Gi
          restartPolicy: OnFailure
    - replicas: 2
      minAvailable: 2
      name: mpiworker
      template:
        metadata:
          annotations:
            k8s.v1.cni.cncf.io/networks: sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf,sriov-rdma-vf
        spec:
          containers:
            - name: mpiworker
              command:
                - /bin/bash
                - -c
                - mkdir -p /var/run/sshd; /usr/sbin/sshd -D;
              image: iad.ocir.io/hpc_limited_availability/nccl-tests:pytorch-25.03-nccl-2.26.6-1
              securityContext:
                capabilities:
                  add: ["IPC_LOCK"]
              ports:
                - containerPort: 22
                  name: mpijob-port
              workingDir: /workspace
              resources:
                requests:
                  nvidia.com/gpu: 8
                  nvidia.com/sriov-rdma-vf: 16
                  ephemeral-storage: 1Gi
                limits:
                  nvidia.com/gpu: 8
                  nvidia.com/sriov-rdma-vf: 16
                  ephemeral-storage: 1Gi
              volumeMounts:
              - mountPath: /dev/shm
                name: shm
          restartPolicy: OnFailure
          terminationGracePeriodSeconds: 15
          tolerations:
            - key: nvidia.com/gpu
              operator: Exists
          volumes:
          - name: root
            hostPath:
              path: /
              type: Directory
          - name: shm
            emptyDir:
              medium: Memory
              sizeLimit: 8Gi
EOF
```

```
kubectl apply -f nccl-tests-nv-ipam-ippool.yaml
```

The initial pull of the container will take long. Once the master pod `nccl-allreduce-job0-mpimaster-0` starts running, you can check it logs for the NCCL test result.

```sh
Defaulted container "mpimaster" out of: mpimaster, wait-for-workers (init)
Warning: Permanently added 'nccl-allreduce-job0-mpiworker-0.nccl-allreduce-job0' (ED25519) to the list of known hosts.
Warning: Permanently added 'nccl-allreduce-job0-mpiworker-1.nccl-allreduce-job0' (ED25519) to the list of known hosts.
# nThread 1 nGpus 1 minBytes 8 maxBytes 8589934592 step: 2(factor) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid     43 on nccl-allreduce-job0-mpiworker-0 device  0 [0x0f] NVIDIA A100-SXM4-40GB
#  Rank  1 Group  0 Pid     44 on nccl-allreduce-job0-mpiworker-0 device  1 [0x15] NVIDIA A100-SXM4-40GB
#  Rank  2 Group  0 Pid     45 on nccl-allreduce-job0-mpiworker-0 device  2 [0x51] NVIDIA A100-SXM4-40GB
#  Rank  3 Group  0 Pid     46 on nccl-allreduce-job0-mpiworker-0 device  3 [0x54] NVIDIA A100-SXM4-40GB
#  Rank  4 Group  0 Pid     47 on nccl-allreduce-job0-mpiworker-0 device  4 [0x8d] NVIDIA A100-SXM4-40GB
#  Rank  5 Group  0 Pid     48 on nccl-allreduce-job0-mpiworker-0 device  5 [0x92] NVIDIA A100-SXM4-40GB
#  Rank  6 Group  0 Pid     49 on nccl-allreduce-job0-mpiworker-0 device  6 [0xd6] NVIDIA A100-SXM4-40GB
#  Rank  7 Group  0 Pid     50 on nccl-allreduce-job0-mpiworker-0 device  7 [0xda] NVIDIA A100-SXM4-40GB
#  Rank  8 Group  0 Pid     43 on nccl-allreduce-job0-mpiworker-1 device  0 [0x0f] NVIDIA A100-SXM4-40GB
#  Rank  9 Group  0 Pid     44 on nccl-allreduce-job0-mpiworker-1 device  1 [0x15] NVIDIA A100-SXM4-40GB
#  Rank 10 Group  0 Pid     45 on nccl-allreduce-job0-mpiworker-1 device  2 [0x51] NVIDIA A100-SXM4-40GB
#  Rank 11 Group  0 Pid     46 on nccl-allreduce-job0-mpiworker-1 device  3 [0x54] NVIDIA A100-SXM4-40GB
#  Rank 12 Group  0 Pid     47 on nccl-allreduce-job0-mpiworker-1 device  4 [0x8d] NVIDIA A100-SXM4-40GB
#  Rank 13 Group  0 Pid     48 on nccl-allreduce-job0-mpiworker-1 device  5 [0x92] NVIDIA A100-SXM4-40GB
#  Rank 14 Group  0 Pid     49 on nccl-allreduce-job0-mpiworker-1 device  6 [0xd6] NVIDIA A100-SXM4-40GB
#  Rank 15 Group  0 Pid     50 on nccl-allreduce-job0-mpiworker-1 device  7 [0xda] NVIDIA A100-SXM4-40GB
#
#                                                              out-of-place                       in-place
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
           8             2     float     sum      -1    36.47    0.00    0.00      0    34.74    0.00    0.00      0
          16             4     float     sum      -1    38.86    0.00    0.00      0    35.65    0.00    0.00      0
          32             8     float     sum      -1    38.53    0.00    0.00      0    35.41    0.00    0.00      0
          64            16     float     sum      -1    39.25    0.00    0.00      0    37.05    0.00    0.00      0
         128            32     float     sum      -1    38.85    0.00    0.01      0    37.21    0.00    0.01      0
         256            64     float     sum      -1    40.68    0.01    0.01      0    38.52    0.01    0.01      0
         512           128     float     sum      -1    39.27    0.01    0.02      0    39.35    0.01    0.02      0
        1024           256     float     sum      -1    41.97    0.02    0.05      0    40.56    0.03    0.05      0
        2048           512     float     sum      -1    43.36    0.05    0.09      0    41.29    0.05    0.09      0
        4096          1024     float     sum      -1    44.54    0.09    0.17      0    43.36    0.09    0.18      0
        8192          2048     float     sum      -1    48.16    0.17    0.32      0    46.51    0.18    0.33      0
       16384          4096     float     sum      -1    49.40    0.33    0.62      0    48.00    0.34    0.64      0
       32768          8192     float     sum      -1    49.66    0.66    1.24      0    49.17    0.67    1.25      0
       65536         16384     float     sum      -1    51.69    1.27    2.38      0    50.09    1.31    2.45      0
      131072         32768     float     sum      -1    54.86    2.39    4.48      0    53.31    2.46    4.61      0
      262144         65536     float     sum      -1    67.95    3.86    7.23      0    65.81    3.98    7.47      0
      524288        131072     float     sum      -1    73.94    7.09   13.29      0    72.87    7.20   13.49      0
     1048576        262144     float     sum      -1    85.58   12.25   22.97      0    84.50   12.41   23.27      0
     2097152        524288     float     sum      -1    99.19   21.14   39.64      0    100.1   20.94   39.27      0
     4194304       1048576     float     sum      -1    127.0   33.03   61.93      0    127.8   32.81   61.52      0
     8388608       2097152     float     sum      -1    174.3   48.13   90.25      0    168.4   49.80   93.38      0
    16777216       4194304     float     sum      -1    282.7   59.35  111.29      0    265.9   63.11  118.32      0
    33554432       8388608     float     sum      -1    452.3   74.18  139.08      0    452.0   74.24  139.19      0
    67108864      16777216     float     sum      -1    821.7   81.67  153.13      0    812.7   82.57  154.83      0
   134217728      33554432     float     sum      -1   1542.0   87.04  163.20      0   1546.1   86.81  162.76      0
   268435456      67108864     float     sum      -1   3042.7   88.22  165.42      0   3065.9   87.55  164.16      0
   536870912     134217728     float     sum      -1   6436.0   83.42  156.41      0   6070.5   88.44  165.82      0
  1073741824     268435456     float     sum      -1   9187.8  116.87  219.12      0   9073.4  118.34  221.89      0
  2147483648     536870912     float     sum      -1    18289  117.42  220.16      0    17557  122.31  229.34      0
  4294967296    1073741824     float     sum      -1    34176  125.67  235.63      0    34417  124.79  233.98      0
  8589934592    2147483648     float     sum      -1    67689  126.90  237.94      0    67811  126.68  237.52      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 66.4834
#
```
