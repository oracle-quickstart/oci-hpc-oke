# Running RDMA (remote direct memory access) GPU workloads on OKE using GPU Operator and Network Operator

This guide has the instructions for deploying an OKE cluster using H100 & A100 bare metal nodes with RDMA connectivity using the [GPU Operator](https://github.com/NVIDIA/gpu-operator) and [Network Operator](https://github.com/Mellanox/network-operator).

> [!IMPORTANT]  
> Currently, creating SR-IOV Virtual Functions is supported in limited regions. For H100, all regions with H100s are supported. For A100s, Phoenix (PHX) and Osaka (KIX) regions are supported. For other regions, please contact your sales representative.

### What is NVIDIA GPU Operator?
Kubernetes provides access to special hardware resources such as NVIDIA GPUs, NICs, Infiniband adapters and other devices through the device plugin framework. However, configuring and managing nodes with these hardware resources requires configuration of multiple software components such as drivers, container runtimes or other libraries which are difficult and prone to errors. The NVIDIA GPU Operator uses the operator framework within Kubernetes to automate the management of all NVIDIA software components needed to provision GPU. These components include the NVIDIA drivers (to enable CUDA), Kubernetes device plugin for GPUs, the NVIDIA Container Runtime, automatic node labelling, DCGM based monitoring and others.

### What is NVIDIA Network Operator?
NVIDIA Network Operator leverages Kubernetes CRDs and Operator SDK to manage Networking related Components in order to enable Fast networking, RDMA and GPUDirect for workloads in a Kubernetes cluster.

The Goal of Network Operator is to manage all networking related components to enable execution of RDMA and GPUDirect RDMA workloads in a kubernetes cluster.

### Supported Operating Systems
For the A100 and H100 shapes (BM.GPU.H100.8, BM.GPU.A100-v2.8, BM.GPU4.8), Oracle Linux 8 with the Red Hat Compatible Kernel (RHCK) is supported.

### Required policies
The Terraform deployment template uses the [Self Managed Nodes](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengworkingwithselfmanagednodes.htm) functionality of OKE.

You must create the necessary OKE policies:

[Policy Configuration for Cluster Creation and Deployment](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengpolicyconfig.htm)
[Creating a Dynamic Group and a Policy for Self-Managed Nodes](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdynamicgrouppolicyforselfmanagednodes.htm)

## Instructions for deploying an OKE cluster with GPUs and RDMA connectivity

You will need a CPU and a GPU pool. The Terraform template deploys an operational/system worker pool (CPU) and a GPU worker pool.

The GPU pool requires you to use an image provided by the Oracle HPC team, you can find the import link below. This image included the OFED drivers and necessary packages configured for RDMA.

For the non-GPU worker pools, you can use the default OKE images (no need to specify them in the Terraform template).

> [!NOTE]  
> The GPU image has the GPU drivers pre-installed (GPU driver version 535.154.05 with CUDA 12.2). Deploying the GPU driver as a container with the GPU Operator is currently not supported.

#### GPU nodes
[OracleLinux-8-OCA-RHCK-OFED-5.8-3.0.7.0-GPU-535-OKE-2024.02.12-0](https://objectstorage.us-ashburn-1.oraclecloud.com/p/f6mKO0d_OG7gL4EyE5rvOWObL6LBgQ1XXtpM2H67SYmFHQ-tBwxyg7Wmii94VYc8/n/hpc_limited_availability/b/images/o/OracleLinux-8-OCA-RHCK-OFED-5.8-3.0.7.0-GPU-535-OKE-2024.02.12-0)

### Deploy the cluster using the Terraform template
You can find the template in the [terraform directory](../terraform).

Make sure to update the image IDs in the `worker pools` blocks.

You can find more information on setting up Terraform for OCI [here](https://docs.oracle.com/en-us/iaas/developer-tutorials/tutorials/tf-provider/01-summary.htm).

The template will deploy a `bastion` instance and an `operator` instance. The `operator` instance will have access to the OKE cluster. You can connect to the `operator` instance via SSH with `ssh -J opc@<bastion IP> opc@<operator IP>`.

### Wait until you see all nodes in the cluster

```sh
kubectl get nodes

NAME           STATUS     ROLES    AGE     VERSION
10.0.103.73    Ready      <none>   2d23h   v1.25.6
10.0.127.206   Ready      node     2d3h    v1.25.6
10.0.127.32    Ready      node     2d3h    v1.25.6
10.0.83.93     Ready      <none>   2d23h   v1.25.6
10.0.96.81     Ready      node     2d23h   v1.25.6
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
  --version v23.9.1 \
  --set driver.enabled=false \
  --set operator.defaultRuntime=crio \
  --set toolkit.version=v1.14.5-ubi8 \
  --set driver.rdma.enabled=true \
  --set driver.rdma.useHostMofed=true
```

Wait until all network operator pods are running with `kubectl get pods -n gpu-operator`.

### Deploy Network Operator

> [!IMPORTANT]  
> The device name you will use when deploying the Network Operator is different between A100 and H100 shapes. Please make sure you're running the correct command based on your shape.

#### A100 shapes (BM.GPU.A100-v2.8, BM.GPU4.8)
```
helm install --wait \
  -n network-operator --create-namespace \
  network-operator nvidia/network-operator \
  --version v23.10.0 \
  --set deployCR=true \
  --set nfd.enabled=false \
  --set rdmaSharedDevicePlugin.deploy=false \
  --set nvPeerDriver.deploy=true \
  --set sriovDevicePlugin.deploy=true \
  --set secondaryNetwork.ipamPlugin.deploy=false \
  --set nvIpam.deploy=true \
  --set-json sriovDevicePlugin.resources='[{"name": "sriov_rdma_vf", "drivers": ["mlx5_core"], "devices": ["101a"], "isRdma": [true]}]'
```

#### H100 shapes (BM.GPU.H100.8)
```
helm install --wait \
  -n network-operator --create-namespace \
  network-operator nvidia/network-operator \
  --version v23.10.0 \
  --set deployCR=true \
  --set nfd.enabled=false \
  --set rdmaSharedDevicePlugin.deploy=false \
  --set nvPeerDriver.deploy=true \
  --set sriovDevicePlugin.deploy=true \
  --set secondaryNetwork.ipamPlugin.deploy=false \
  --set nvIpam.deploy=true \
  --set-json sriovDevicePlugin.resources='[{"name": "sriov_rdma_vf", "drivers": ["mlx5_core"], "devices": ["101e"], "isRdma": [true]}]'
```

Wait until all network operator pods are running with `kubectl get pods -n network-operator`.

### Deploy the Virtual Function Configuration daemonset
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/vf/manifests/vf-config.yaml
```

### Confirm that the GPUs are VFs are correctly exposed
Once the Network Operator pods are deployed, the GPU nodes with RDMA NICs will start reporting `nvidia.com/sriov_rdma_vf` as an available resource. You can request that resource in your pod manifests for assigning RDMA VFs to pods.

By default, we create one Virtual Function per Physical Function. So for the A100 bare metal shapes, you will see 16 VFs per node exposed as a resource.

```
kubectl get nodes -l 'node.kubernetes.io/instance-type in (BM.GPU.H100.8, BM.GPU.A100-v2.8, BM.GPU4.8, BM.GPU.B4.8)' --sort-by=.status.capacity."nvidia\.com/gpu" -o=custom-columns='NODE:metadata.name,GPUs:status.capacity.nvidia\.com/gpu,RDMA-VFs:status.capacity.nvidia\.com/sriov_rdma_vf'

NODE            GPUs   RDMA-VFs
10.79.148.115   8      16
10.79.151.167   8      16
10.79.156.205   8      16
```

### Create Network Attachment Definition

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/vf/manifests/network-attachment-definition.yaml
```

### Create the IP Pool for Nvidia IPAM
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/vf/manifests/ip-pool.yaml
```

### Create the topology config map
This step creates a ConfigMap that can be used as the NCCL topology file when running your jobs that use NCCL as the backend.

You can find the topology files in the [topology directory](../manifests/topology/) in this repo. Please make sure you use the correct topology file based on your shape when creating the ConfigMap.

```
SHAPE=<your GPU shape>

curl -s -o ./topo.xml https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/vf/manifests/topology/$SHAPE.xml

kubectl create configmap topology --from-file topo.xml
```

### Optional - Deploy Volcano
```sh
helm repo add volcano-sh https://volcano-sh.github.io/helm-charts
helm install volcano volcano-sh/volcano -n volcano-system --create-namespace

kubectl create serviceaccount -n default mpi-worker-view
kubectl create rolebinding default-view --namespace default --serviceaccount default:mpi-worker-view --clusterrole view
```

### Optional - Run the NCCL test

Run the test with `kubectl apply -f nccl-test.yaml`.

`nccl-test.yaml`

```yaml
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
            - name: topo
              configMap:
                name: topology
                items:
                - key: topo.xml
                  path: topo.xml
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
                    -mca coll ^hcoll \
                    -np 24 -npernode 8 --bind-to numa --map-by ppr:8:node \
                    -hostfile /etc/volcano/mpiworker.host \
                    -x NCCL_CROSS_NIC=0 \
                    -x NCCL_SOCKET_NTHREADS=16 \
                    -x NCCL_DEBUG=WARN \
                    -x NCCL_CUMEM_ENABLE=0 \
                    -x NCCL_IB_SPLIT_DATA_ON_QPS=0 \
                    -x NCCL_IB_QPS_PER_CONNECTION=16 \
                    -x NCCL_IB_GID_INDEX=3 \
                    -x NCCL_IB_TC=41 \
                    -x NCCL_IB_SL=0 \
                    -x NCCL_IB_TIMEOUT=22 \
                    -x NCCL_NET_PLUGIN=none \
                    -x HCOLL_ENABLE_MCAST_ALL=0 \
                    -x coll_hcoll_enable=0 \
                    -x UCX_TLS=tcp \
                    -x UCX_NET_DEVICES=eth0 \
                    -x RX_QUEUE_LEN=8192 \
                    -x IB_RX_QUEUE_LEN=8192 \
                    -x NCCL_SOCKET_IFNAME=eth0 \
                    -x NCCL_ALGO=auto \
                    -x NCCL_IGNORE_CPU_AFFINITY=1 \
                    -x NCCL_TOPO_FILE=/h100/topo.xml \
                    -mca coll_hcoll_enable 0 \
                    /workspace/nccl-tests/build/all_reduce_perf -b 8 -f 2 -g 1 -e 8G -c 1; sleep 3600
              image: iad.ocir.io/hpc_limited_availability/nccl-tests:pytorch-23.10-nccl-2.19.3-1
              volumeMounts:
              - { mountPath: /h100, name: topo }
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
                  cpu: 1
          restartPolicy: OnFailure
    - replicas: 3
      minAvailable: 3
      name: mpiworker
      template:
        metadata:
          annotations:
            k8s.v1.cni.cncf.io/networks: oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov
        spec:
          containers:
            - name: mpiworker
              command:
                - /bin/bash
                - -c
                - mkdir -p /var/run/sshd; /usr/sbin/sshd -D;
              image: iad.ocir.io/hpc_limited_availability/nccl-tests:pytorch-23.10-nccl-2.19.3-1
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
                  nvidia.com/sriov_rdma_vf: 16
                  ephemeral-storage: 1Gi
                limits:
                  nvidia.com/gpu: 8
                  nvidia.com/sriov_rdma_vf: 16
                  ephemeral-storage: 1Gi
              volumeMounts:
              - { mountPath: /h100, name: topo }
              - mountPath: /dev/shm
                name: shm
          restartPolicy: OnFailure
          terminationGracePeriodSeconds: 15
          tolerations:
            - key: nvidia.com/gpu
              operator: Exists
          volumes:
          - name: topo
            configMap:
              name: topology-h100
              items:
              - key: topo.xml
                path: topo.xml
          - name: root
            hostPath:
              path: /
              type: Directory
          - name: shm
            emptyDir:
              medium: Memory
              sizeLimit: 8Gi
```                

The initial pull of the container will take long.



```sh
Warning: Permanently added 'nccl-test-a100-worker-0.nccl-test-a100-worker.default.svc,10.244.0.253' (ECDSA) to the list of known hosts.
Warning: Permanently added 'nccl-test-a100-worker-1.nccl-test-a100-worker.default.svc,10.244.1.9' (ECDSA) to the list of known hosts.
# nThread 1 nGpus 1 minBytes 1073741824 maxBytes 10737418240 step: 9663676416(bytes) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid     17 on nccl-test-a100-worker-0 device  0 [0x0f] NVIDIA A100-SXM4-40GB
#  Rank  1 Group  0 Pid     18 on nccl-test-a100-worker-0 device  1 [0x15] NVIDIA A100-SXM4-40GB
#  Rank  2 Group  0 Pid     19 on nccl-test-a100-worker-0 device  2 [0x50] NVIDIA A100-SXM4-40GB
#  Rank  3 Group  0 Pid     20 on nccl-test-a100-worker-0 device  3 [0x53] NVIDIA A100-SXM4-40GB
#  Rank  4 Group  0 Pid     21 on nccl-test-a100-worker-0 device  4 [0x8c] NVIDIA A100-SXM4-40GB
#  Rank  5 Group  0 Pid     22 on nccl-test-a100-worker-0 device  5 [0x91] NVIDIA A100-SXM4-40GB
#  Rank  6 Group  0 Pid     23 on nccl-test-a100-worker-0 device  6 [0xd6] NVIDIA A100-SXM4-40GB
#  Rank  7 Group  0 Pid     24 on nccl-test-a100-worker-0 device  7 [0xda] NVIDIA A100-SXM4-40GB
#  Rank  8 Group  0 Pid     17 on nccl-test-a100-worker-1 device  0 [0x0f] NVIDIA A100-SXM4-40GB
#  Rank  9 Group  0 Pid     18 on nccl-test-a100-worker-1 device  1 [0x15] NVIDIA A100-SXM4-40GB
#  Rank 10 Group  0 Pid     19 on nccl-test-a100-worker-1 device  2 [0x50] NVIDIA A100-SXM4-40GB
#  Rank 11 Group  0 Pid     20 on nccl-test-a100-worker-1 device  3 [0x53] NVIDIA A100-SXM4-40GB
#  Rank 12 Group  0 Pid     21 on nccl-test-a100-worker-1 device  4 [0x8c] NVIDIA A100-SXM4-40GB
#  Rank 13 Group  0 Pid     22 on nccl-test-a100-worker-1 device  5 [0x91] NVIDIA A100-SXM4-40GB
#  Rank 14 Group  0 Pid     23 on nccl-test-a100-worker-1 device  6 [0xd6] NVIDIA A100-SXM4-40GB
#  Rank 15 Group  0 Pid     24 on nccl-test-a100-worker-1 device  7 [0xda] NVIDIA A100-SXM4-40GB
NCCL version 2.14.3+cuda11.7
#
#                                                              out-of-place                       in-place          
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)       
  1073741824     268435456     float     sum      -1    11774   91.20  170.99      0    11774   91.19  170.99      0
 10737418240    2684354560     float     sum      -1   111812   96.03  180.06      0   111797   96.04  180.08      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 175.531 
#
```

