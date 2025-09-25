# Running RDMA GPU workloads on OKE with GB200s

### Prerequisites
- Your cluster needs to have v1.32+ and the `DynamicResourceAllocation` feature gate must be enabled on the cluster. Reach out to your cloud architect to enable it (needs a ticket with OKE).

- Once it's enabled, you will need to start kubelet with `--feature-gates=DynamicResourceAllocation=true`. You can find an example [below](https://github.com/oracle-quickstart/oci-hpc-oke/tree/gb200?tab=readme-ov-file#create-cloud-init).

### Required policies (any-user can be replaced by the group launching the cluster)

```python
Allow any-user to use compute-hpc-islands in tenancy
Allow any-user to use compute-network-blocks in tenancy
Allow any-user to use compute-local-blocks in tenancy
Allow any-user to use compute-bare-metal-hosts in tenancy
Allow any-user to use compute-gpu-memory-fabrics in tenancy
```

### Create a Compute Cluster

#### Python
```python
import oci
signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
compute_client = oci.core.ComputeClient(config={}, signer=signer)
cc_details=oci.core.models.CreateComputeClusterDetails(compartment_id="ocid1.compartment.oc1..,availability_domain="XXXX:AP-SYDNEY-1-AD-1",display_name=CN_name)
cn = compute_client.create_compute_cluster(create_compute_cluster_details=cc_details).data
cn_id=cn.id
```
#### OCI CLI

```
oci compute compute-cluster create --availability-domain $AD --compartment-id $COMPARTMENT_ID --display-name $DISPLAY_NAME
```

### List GPU Memory Fabric IDs

#### Python
```python
import oci
signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
compute_client = oci.core.ComputeClient(config={}, signer=signer)
compute_client.list_compute_gpu_memory_fabrics(compartment_id="ocid1.tenancy.oc1..").data
```

#### OCI CLI

```
oci compute compute-gpu-memory-fabric list --compartment-id $COMPARTMENT_ID
```

### Create cloud-init
Follow the instructions [here](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcloudinitforselfmanagednodes.htm#contengcloudinitforselfmanagednodes) for getting the API Server Host IP and CA cert.

```yaml
#cloud-config
apt:
  sources:
    oke-node: {source: 'deb [trusted=yes] https://objectstorage.us-sanjose-1.oraclecloud.com/p/45eOeErEDZqPGiymXZwpeebCNb5lnwzkcQIhtVf6iOF44eet_efdePaF7T8agNYq/n/odx-oke/b/okn-repositories-private/o/prod/ubuntu-jammy/kubernetes-1.32 stable main'}
packages:
  - oci-oke-node-all-1.32.1
write_files:
  - path: /etc/oke/oke-apiserver
    permissions: '0644'
    content: <API SERVER HOST IP>
  - encoding: b64
    path: /etc/kubernetes/ca.crt
    permissions: '0644'
    content: <CA cert>
runcmd:
  - oke bootstrap --apiserver-host <API SERVER HOST IP> --ca "<CA cert>" --kubelet-extra-args "--feature-gates=DynamicResourceAllocation=true"
  - systemctl disable --now nvidia-imex.service && systemctl mask nvidia-imex.service
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCqftxN9j+mN75JKR...
```

### Create an Instance Configuration

#### OCI CLI
```
REGION=
COMPARTMENT_ID=
AD=
WORKER_SUBNET_ID=
WORKER_SUBNET_NSG_ID=
POD_SUBNET_ID=
POD_SUBNET_NSG_ID=
IMAGE_ID=
BASE64_ENCODED_CLOUD_INIT=$(cat cloud-init.yml| base64 -b 0)

oci --region ${REGION} compute-management instance-configuration create --compartment-id ${COMPARTMENT_ID} --display-name gb200-oke --instance-details \
'{
  "instanceType": "compute",
  "launchDetails": {
    "availabilityDomain": "$AD",
    "compartmentId": "$COMPARTMENT_ID",
    "createVnicDetails": {
      "assignIpv6Ip": false,
      "assignPublicIp": false,
      "assignPrivateDnsRecord": true,
      "subnetId": "$SUBNET_ID",
      "nsgIds": [ "$SUBNET_NSG_ID" ]
    },
    "metadata": {
      "user_data": "$BASE64_ENCODED_CLOUD_INIT",
      "oke-native-pod-networking": "true", "oke-max-pods": "60",
      "pod-subnets": "$POD_SUBNET_ID$",
      "pod-nsgids": "$POD_SUBNET_NSG_ID$"
    },
    "displayName": "gb200-instance",
    "shape": "BM.GPU.GB200.4",
    "sourceDetails": {
      "sourceType": "image",
      "imageId": "$IMAGE_ID"
    },
    "agentConfig": {
      "isMonitoringDisabled": false,
      "isManagementDisabled": false,
      "pluginsConfig": [
        {
          "name": "WebLogic Management Service",
          "desiredState": "DISABLED"
        },
        {
          "name": "Vulnerability Scanning",
          "desiredState": "DISABLED"
        },
        {
          "name": "Oracle Java Management Service",
          "desiredState": "DISABLED"
        },
        {
          "name": "Oracle Autonomous Linux",
          "desiredState": "DISABLED"
        },
        {
          "name": "OS Management Service Agent",
          "desiredState": "DISABLED"
        },
        {
          "name": "OS Management Hub Agent",
          "desiredState": "DISABLED"
        },
        {
          "name": "Management Agent",
          "desiredState": "ENABLED"
        },
        {
          "name": "Custom Logs Monitoring",
          "desiredState": "ENABLED"
        },
        {
          "name": "Compute RDMA GPU Monitoring",
          "desiredState": "ENABLED"
        },
        {
          "name": "Compute Instance Run Command",
          "desiredState": "ENABLED"
        },
        {
          "name": "Compute Instance Monitoring",
          "desiredState": "ENABLED"
        },
        {
          "name": "Compute HPC RDMA Auto-Configuration",
          "desiredState": "ENABLED"
        },
        {
          "name": "Compute HPC RDMA Authentication",
          "desiredState": "ENABLED"
        },
        {
          "name": "Cloud Guard Workload Protection",
          "desiredState": "DISABLED"
        },
        {
          "name": "Block Volume Management",
          "desiredState": "DISABLED"
        },
        {
          "name": "Bastion",
          "desiredState": "DISABLED"
        }
      ]
    },
    "isPvEncryptionInTransitEnabled": false,
    "instanceOptions": {
      "areLegacyImdsEndpointsDisabled": false
    },
    "availabilityConfig": {
      "recoveryAction": "RESTORE_INSTANCE"
    }
  }
}'
```

### Create a GPU Memory Cluster

#### Python

```python
import oci
signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
compute_client = oci.core.ComputeClient(config={}, signer=signer)
details=oci.core.models.CreateComputeGpuMemoryClusterDetails(availability_domain="XXXX:AP-SYDNEY-1-AD-1",compartment_id="ocid1.compartment.oc1..",compute_cluster_id="ocid1.computecluster.oc1.ap-sydney-1.",instance_configuration_id="ocid1.instanceconfiguration.oc1.ap-sydney-1.",size=2,gpu_memory_fabric_id="ocid1.computegpumemoryfabric.oc1.ap-sydney-1.",display_name="memoryFabric1")
output=compute_client.create_compute_gpu_memory_cluster(details)
```

#### OCI CLI

```
oci compute compute-gpu-memory-cluster create \
  --availability-domain $AD \
  --compartment-id $COMPARTMENT_ID \
  --compute-cluster-id $CC_ID \
  --instance-configuration-id $IC_ID \
  --gpu-memory-fabric-id $GPU_MEMORY_FABRIC_ID \
  --size $GPU_MEMORY_CLUSTER_SIZE \
  --display-name $DISPLAY_NAME
```

### List GPU Memory Clusters

#### OCI CLI

```
oci compute compute-gpu-memory-cluster-collection list-compute-gpu-memory-clusters \
  --compartment-id $COMPARTMENT_ID
```

### Manage a GPU Memory Cluster

#### Python
Add a node

```python
import oci
signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
compute_client = oci.core.ComputeClient(config={}, signer=signer)
update_details=oci.core.models.UpdateComputeGpuMemoryClusterDetails(size=3)
output = compute_client.update_compute_gpu_memory_cluster("ocid1.computegpumemorycluster.oc1.....",update_details)
```

Remove a node randomly
```python
import oci
signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
compute_client = oci.core.ComputeClient(config={}, signer=signer)
update_details=oci.core.models.UpdateComputeGpuMemoryClusterDetails(size=1)
output = compute_client.update_compute_gpu_memory_cluster("ocid1.computegpumemorycluster.oc1.....",update_details)
```

#### OCI CLI

```
oci compute compute-gpu-memory-cluster update \
  --compute-gpu-memory-cluster-id $GPU_MEMORY_CLUSTER_ID \
  --size $GPU_MEMORY_CLUSTER_SIZE
```

You can also delete a node from the console and the size will be automatically updated. 

### Import the image
https://objectstorage.us-ashburn-1.oraclecloud.com/p/D62MHqp6A_NlJ-UAK2Yo2tKnrosEHyJmUzRMme4Z6LvarsBfbEeydI-PwAa-nvGD/n/imagegen/b/GPU-imaging/o/Canonical-Ubuntu-22.04-aarch64-2025.07.24-0-OCA-OFED-24.10-1.1.4.0-GPU-570-OPEN-CUDA-12.8-2025.08.12-0

### Deploy an OKE cluster
[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/oracle-quickstart/oci-hpc-oke/releases/latest/download/oke-gpu-rdma-quickstart.zip)

- Kubernetes version must be at least v1.32
- Choose VCN-native pod networking

### Install GPU Operator
```
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

```
helm install gpu-operator nvidia/gpu-operator \
    --version=v25.3.2 \
    --create-namespace \
    --namespace gpu-operator \
    --set cdi.enabled=true \
    --set driver.enabled=false \
    --set driver.rdma.enabled=true \
    --set driver.rdma.useHostMofed=true
```

### Install Dynamic Resource Allocation (DRA) driver

```
helm install nvidia-dra-driver-gpu nvidia/nvidia-dra-driver-gpu \
    --version=25.3.1 \
    --create-namespace \
    --namespace nvidia-dra-driver-gpu \
    -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/gb200/manifests/dra/values.yaml
```

### Validate that the DRA driver components are running and in a Ready state

```
kubectl get pod -n nvidia-dra-driver-gpu

NAME                                                           READY   STATUS    RESTARTS   AGE
nvidia-dra-driver-k8s-dra-driver-controller-67cb99d84b-5q7kj   1/1     Running   0          7m26s
nvidia-dra-driver-k8s-dra-driver-kubelet-plugin-7kdg9          1/1     Running   0          7m27s
nvidia-dra-driver-k8s-dra-driver-kubelet-plugin-bd6gn          1/1     Running   0          7m27s
nvidia-dra-driver-k8s-dra-driver-kubelet-plugin-bzm6p          1/1     Running   0          7m26s
nvidia-dra-driver-k8s-dra-driver-kubelet-plugin-xjm4p          1/1     Running   0          7m27s
```

### Confirm that all GPU nodes are labeled with clique ids

```
kubectl get nodes -l node.kubernetes.io/instance-type=BM.GPU.GB200.4 -o custom-columns="NODE:.metadata.name,CLIQUE:.metadata.labels.nvidia\.com/gpu\.clique"

NODE            CLIQUE
10.140.61.148   61248eac-4785-4fbf-9cbd-231635e37e9d.20663
10.140.63.103   61248eac-4785-4fbf-9cbd-231635e37e9d.20663
```

### Run a simple test to validate IMEX daemons are started and IMEX channels are injected

```yaml
cat <<'EOF' > imex-channel-injection.yaml
---
apiVersion: resource.nvidia.com/v1beta1
kind: ComputeDomain
metadata:
  name: imex-channel-injection
spec:
  numNodes: 1
  channel:
    resourceClaimTemplate:
      name: imex-channel-0
---
apiVersion: v1
kind: Pod
metadata:
  name: imex-channel-injection
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: nvidia.com/gpu.clique
            operator: Exists
  tolerations:
  - key: "nvidia.com/gpu"
    value: "present"
    operator: "Equal"
    effect: "NoSchedule"
  containers:
  - name: ctr
    image: ubuntu:22.04
    command: ["bash", "-c"]
    args: ["ls -la /dev/nvidia-caps-imex-channels; trap 'exit 0' TERM; sleep 9999 & wait"]
    resources:
      claims:
      - name: imex-channel-0
  resourceClaims:
  - name: imex-channel-0
    resourceClaimTemplateName: imex-channel-0
EOF
```

```
kubectl apply -f imex-channel-injection.yaml

computedomain.resource.nvidia.com/imex-channel-injection created
pod/imex-channel-injection created
```

```
kubectl get pods -n nvidia-dra-driver-gpu -l resource.nvidia.com/computeDomain

NAME                                 READY   STATUS    RESTARTS   AGE
imex-channel-injection-vmvtq-h7wls   1/1     Running   0          75s
```

```
kubectl logs imex-channel-injection

total 0
drwxr-xr-x 2 root root     60 May 24 05:59 .
drwxr-xr-x 6 root root    380 May 24 05:59 ..
crw-rw-rw- 1 root root 234, 0 May 24 05:59 channel0
```

```
kubectl delete -f imex-channel-injection.yaml

computedomain.resource.nvidia.com "imex-channel-injection" deleted
pod "imex-channel-injection" deleted
```

### Run a single rack `nvbandwidth` test

```yaml
cat <<EOF > nvbandwidth-test-job.yaml
---
apiVersion: resource.nvidia.com/v1beta1
kind: ComputeDomain
metadata:
  name: nvbandwidth-test-compute-domain
spec:
  numNodes: 2
  channel:
    resourceClaimTemplate:
      name: nvbandwidth-test-compute-domain-channel

---
apiVersion: kubeflow.org/v2beta1
kind: MPIJob
metadata:
  name: nvbandwidth-test
spec:
  slotsPerWorker: 4
  launcherCreationPolicy: WaitForWorkersReady
  runPolicy:
    cleanPodPolicy: Running
  sshAuthMountPath: /home/mpiuser/.ssh
  mpiReplicaSpecs:
    Launcher:
      replicas: 1
      template:
        metadata:
          labels:
            nvbandwidth-test-replica: mpi-launcher
        spec:
          affinity:
            nodeAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
                nodeSelectorTerms:
                - matchExpressions:
                  - key: node-role.kubernetes.io/node
                    operator: Exists
          containers:
          - image: ghcr.io/nvidia/k8s-samples:nvbandwidth-v0.7-8d103163
            name: mpi-launcher
            securityContext:
              runAsUser: 1000
            command:
            - mpirun
            args:
            - --bind-to
            - core
            - --map-by
            - ppr:4:node
            - -np
            - "8"
            - --report-bindings
            - -q
            - nvbandwidth
            - -t
            - multinode_device_to_device_memcpy_read_ce
    Worker:
      replicas: 2
      template:
        metadata:
          labels:
            nvbandwidth-test-replica: mpi-worker
        spec:
          affinity:
            podAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
              - labelSelector:
                  matchExpressions:
                  - key: nvbandwidth-test-replica
                    operator: In
                    values:
                    - mpi-worker
                topologyKey: nvidia.com/gpu.clique
          containers:
          - image: ghcr.io/nvidia/k8s-samples:nvbandwidth-v0.7-8d103163
            name: mpi-worker
            securityContext:
              runAsUser: 1000
            env:
            command:
            - /usr/sbin/sshd
            args:
            - -De
            - -f
            - /home/mpiuser/.sshd_config
            resources:
              limits:
                nvidia.com/gpu: 4
              claims:
              - name: compute-domain-channel
          resourceClaims:
          - name: compute-domain-channel
            resourceClaimTemplateName: nvbandwidth-test-compute-domain-channel
EOF
```

```
kubectl apply -f nvbandwidth-test-job.yaml
```

```
kubectl logs --tail=-1 -l job-name=nvbandwidth-test-launcher
Warning: Permanently added '[nvbandwidth-test-worker-0.nvbandwidth-test.default.svc]:2222' (ECDSA) to the list of known hosts.
Warning: Permanently added '[nvbandwidth-test-worker-1.nvbandwidth-test.default.svc]:2222' (ECDSA) to the list of known hosts.
[nvbandwidth-test-worker-0:00025] MCW rank 0 bound to socket 0[core 0[hwt 0]]: [B/././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.][./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.]
[nvbandwidth-test-worker-0:00025] MCW rank 1 bound to socket 0[core 1[hwt 0]]: [./B/./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.][./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.]
[nvbandwidth-test-worker-0:00025] MCW rank 2 bound to socket 0[core 2[hwt 0]]: [././B/././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.][./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.]
[nvbandwidth-test-worker-0:00025] MCW rank 3 bound to socket 0[core 3[hwt 0]]: [./././B/./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.][./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.]
[nvbandwidth-test-worker-1:00025] MCW rank 4 bound to socket 0[core 0[hwt 0]]: [B/././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.][./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.]
[nvbandwidth-test-worker-1:00025] MCW rank 5 bound to socket 0[core 1[hwt 0]]: [./B/./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.][./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.]
[nvbandwidth-test-worker-1:00025] MCW rank 6 bound to socket 0[core 2[hwt 0]]: [././B/././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.][./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.]
[nvbandwidth-test-worker-1:00025] MCW rank 7 bound to socket 0[core 3[hwt 0]]: [./././B/./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.][./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.]
nvbandwidth Version: v0.7
Built from Git version: v0.7

MPI version: Open MPI v4.1.4, package: Debian OpenMPI, ident: 4.1.4, repo rev: v4.1.4, May 26, 2022
CUDA Runtime Version: 12080
CUDA Driver Version: 12080
Driver Version: 570.124.06

Process 0 (nvbandwidth-test-worker-0): device 0: HGX GB200 (00000008:01:00)
Process 1 (nvbandwidth-test-worker-0): device 1: HGX GB200 (00000009:01:00)
Process 2 (nvbandwidth-test-worker-0): device 2: HGX GB200 (00000018:01:00)
Process 3 (nvbandwidth-test-worker-0): device 3: HGX GB200 (00000019:01:00)
Process 4 (nvbandwidth-test-worker-1): device 0: HGX GB200 (00000008:01:00)
Process 5 (nvbandwidth-test-worker-1): device 1: HGX GB200 (00000009:01:00)
Process 6 (nvbandwidth-test-worker-1): device 2: HGX GB200 (00000018:01:00)
Process 7 (nvbandwidth-test-worker-1): device 3: HGX GB200 (00000019:01:00)

Running multinode_device_to_device_memcpy_read_ce.
memcpy CE GPU(row) -> GPU(column) bandwidth (GB/s)
           0         1         2         3         4         5         6         7
 0       N/A    798.02    798.25    798.02    798.02    797.88    797.73    797.95
 1    798.10       N/A    797.80    798.02    798.02    798.25    797.88    798.02
 2    797.95    797.95       N/A    797.73    797.80    797.95    797.95    797.65
 3    798.10    798.02    797.95       N/A    798.02    798.10    797.88    797.73
 4    797.80    798.02    798.02    798.02       N/A    797.95    797.80    798.02
 5    797.80    797.95    798.10    798.10    797.95       N/A    797.95    797.88
 6    797.73    797.95    798.10    798.02    797.95    797.88       N/A    797.80
 7    797.88    798.02    797.95    798.02    797.88    797.95    798.02       N/A

SUM multinode_device_to_device_memcpy_read_ce 44685.29

NOTE: The reported results may not reflect the full capabilities of the platform.
Performance can vary with software drivers, hardware clocks, and system topology.
```

### RUN NCCL tests

#### Install MPI Operator
```
kubectl create -f https://github.com/kubeflow/mpi-operator/releases/download/v0.6.0/mpi-operator.yaml
```

#### Single rack test
```yaml
cat <<'EOF' > nccl-test-single-rack-job.yaml
---
apiVersion: resource.nvidia.com/v1beta1
kind: ComputeDomain
metadata:
  name: nccl-test-compute-domain
spec:
  numNodes: 2
  channel:
    resourceClaimTemplate:
      name: nccl-test-compute-domain-channel

---
apiVersion: kubeflow.org/v2beta1
kind: MPIJob
metadata:
  name: nccl-test
spec:
  slotsPerWorker: 4
  launcherCreationPolicy: WaitForWorkersReady
  runPolicy:
    cleanPodPolicy: Running
  sshAuthMountPath: /root/.ssh
  mpiReplicaSpecs:
    Launcher:
      replicas: 1
      template:
        metadata:
          labels:
            nccl-test-replica: mpi-launcher
        spec:
          containers:
          - name: mpi-launcher
            image: iad.ocir.io/hpc_limited_availability/nccl-tests:pytorch-25.03-nccl-2.26.6-1
            command: ["bash", "-c"]
            args:
              - |
                NUM_GPUS=4
                NUM_HOSTS=$(sed -n '$=' /etc/mpi/hostfile)
                NP=$(($NUM_HOSTS*$NUM_GPUS))
                mpirun --allow-run-as-root \
                --bind-to none \
                --map-by ppr:4:node \
                --mca coll ^hcoll \
                -x NCCL_DEBUG=WARN \
                -x NCCL_MNNVL_ENABLE=1 \
                -x NCCL_CUMEM_ENABLE=1 \
                -x NCCL_NET_PLUGIN=sys \
                -x NCCL_IB_HCA==mlx5_0,mlx5_1,mlx5_3,mlx5_4 \
                -x NCCL_NVLS_ENABLE=1 \
                -x NCCL_IB_DISABLE=1 \
                -x NCCL_SOCKET_IFNAME=eth0 \
                -np $NP \
                /workspace/nccl-tests/build/all_reduce_perf -b 8 -e 32G -f 2 -g 1
    Worker:
      replicas: 2
      template:
        metadata:
          labels:
            nccl-test-replica: mpi-worker
        spec:
          affinity:
            podAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
              - labelSelector:
                  matchExpressions:
                  - key: nccl-test-replica
                    operator: In
                    values:
                    - mpi-worker
                topologyKey: nvidia.com/gpu.clique
          containers:
          - name: mpi-worker
            image: iad.ocir.io/hpc_limited_availability/nccl-tests:pytorch-25.03-nccl-2.26.6-1
            command:
              - /bin/bash
              - -c
              - mkdir -p /var/run/sshd; /usr/sbin/sshd -D;
            resources:
              limits:
                nvidia.com/gpu: 4
              claims:
              - name: compute-domain-channel
          resourceClaims:
          - name: compute-domain-channel
            resourceClaimTemplateName: nccl-test-compute-domain-channel
EOF
```

#### Multi rack test

> [!NOTE]  
> Multi-rack NCCL tests in GB200 using DRA is still in early days. Let us know if you come across any issues.

```yaml
cat <<'EOF' > nccl-test-multi-rack-job.yaml
---
apiVersion: resource.nvidia.com/v1beta1
kind: ComputeDomain
metadata:
  name: nccl-test-compute-domain
spec:
  numNodes: 32
  channel:
    resourceClaimTemplate:
      name: nccl-test-compute-domain-channel
---
apiVersion: kubeflow.org/v2beta1
kind: MPIJob
metadata:
  name: nccl-test
spec:
  slotsPerWorker: 4
  launcherCreationPolicy: WaitForWorkersReady
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
                NUM_GPUS=4
                NUM_HOSTS=$(sed -n '$=' /etc/mpi/hostfile)
                NP=$(($NUM_HOSTS*$NUM_GPUS))
                mpirun --allow-run-as-root -mca plm_rsh_args "-p 2222" \
                --bind-to none \
                --map-by ppr:4:node \
                --mca coll ^hcoll \
                -x NCCL_DEBUG=WARN \
                -x NCCL_MNNVL_ENABLE=1 \
                -x NCCL_CUMEM_ENABLE=1 \
                -x NCCL_NET_PLUGIN=sys \
                -x NCCL_IB_HCA=mlx5_0,mlx5_1,mlx5_3,mlx5_4 \
                -x NCCL_NVLS_ENABLE=1 \
                -x NCCL_SOCKET_IFNAME=eth0 \
                -np $NP \
                /workspace/nccl-tests/build/all_reduce_perf -b 8 -e 32G -f 2 -g 1
    Worker:
      replicas: 32
      template:
        metadata:
          labels:
            nccl-test-replica: mpi-worker
        spec:
          hostNetwork: true
          dnsPolicy: ClusterFirstWithHostNet
          volumes:
          - { name: devinf, hostPath: { path: /dev/infiniband }}
          - { name: shm, emptyDir: { medium: Memory, sizeLimit: 32Gi }}
          affinity:
            nodeAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
                nodeSelectorTerms:
                - matchExpressions:
                  - key: node.kubernetes.io/instance-type
                    operator: In
                    values:
                    - BM.GPU.GB200.4
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
                nvidia.com/gpu: 4
              claims:
              - name: compute-domain-channel
          resourceClaims:
          - name: compute-domain-channel
            resourceClaimTemplateName: nccl-test-compute-domain-channel
EOF
```

Wait until the `nccl-test-launcher` pod is in `Running` state, it might take a couple of minutes. Seeing warnings that say `Failed to prepare dynamic resources: NodePrepareResources failed: rpc error: code = DeadlineExceeded desc = context deadline exceeded` in the `nccl-test-worker` pods is normal.

```
kubectl logs --tail=20 -f -l job-name=nccl-test-launcher
```

```
nccl-test-worker-0:60:109 [0] NCCL INFO Connected all rings, use ring PXN 0 GDR 1
           8             2     float     sum      -1    21.57    0.00    0.00      0    21.24    0.00    0.00      0
          16             4     float     sum      -1    21.06    0.00    0.00      0    20.90    0.00    0.00      0
          32             8     float     sum      -1    21.99    0.00    0.00      0    21.77    0.00    0.00      0
          64            16     float     sum      -1    24.87    0.00    0.00      0    24.70    0.00    0.00      0
         128            32     float     sum      -1    26.53    0.00    0.01      0    26.21    0.00    0.01      0
         256            64     float     sum      -1    26.77    0.01    0.02      0    26.31    0.01    0.02      0
         512           128     float     sum      -1    27.06    0.02    0.03      0    26.83    0.02    0.03      0
        1024           256     float     sum      -1    27.39    0.04    0.07      0    26.93    0.04    0.07      0
        2048           512     float     sum      -1    27.89    0.07    0.13      0    27.36    0.07    0.13      0
        4096          1024     float     sum      -1    27.96    0.15    0.26      0    27.67    0.15    0.26      0
        8192          2048     float     sum      -1    28.26    0.29    0.51      0    28.05    0.29    0.51      0
       16384          4096     float     sum      -1    28.49    0.57    1.01      0    28.13    0.58    1.02      0
       32768          8192     float     sum      -1    28.93    1.13    1.98      0    28.87    1.13    1.99      0
       65536         16384     float     sum      -1    29.95    2.19    3.83      0    29.35    2.23    3.91      0
      131072         32768     float     sum      -1    30.64    4.28    7.49      0    30.09    4.36    7.62      0
      262144         65536     float     sum      -1    30.58    8.57   15.00      0    30.18    8.69   15.20      0
      524288        131072     float     sum      -1    30.86   16.99   29.73      0    30.54   17.17   30.04      0
     1048576        262144     float     sum      -1    32.18   32.58   57.02      0    31.49   33.30   58.28      0
     2097152        524288     float     sum      -1    35.89   58.44  102.27      0    34.74   60.37  105.65      0
     4194304       1048576     float     sum      -1    52.72   79.55  139.22      0    52.39   80.06  140.10      0
     8388608       2097152     float     sum      -1    67.94  123.47  216.07      0    68.24  122.92  215.12      0
    16777216       4194304     float     sum      -1    102.8  163.15  285.52      0    100.5  166.96  292.18      0
    33554432       8388608     float     sum      -1    159.5  210.38  368.17      0    157.8  212.69  372.21      0
    67108864      16777216     float     sum      -1    265.3  252.91  442.59      0    264.6  253.66  443.90      0
   134217728      33554432     float     sum      -1    386.9  346.95  607.15      0    384.4  349.19  611.07      0
   268435456      67108864     float     sum      -1    698.9  384.07  672.13      0    697.3  384.95  673.67      0
   536870912     134217728     float     sum      -1   1314.7  408.37  714.65      0   1314.0  408.58  715.02      0
  1073741824     268435456     float     sum      -1   2544.0  422.06  738.61      0   2549.1  421.23  737.15      0
  2147483648     536870912     float     sum      -1   4557.5  471.20  824.59      0   4557.1  471.24  824.67      0
  4294967296    1073741824     float     sum      -1   9015.4  476.40  833.71      0   9019.7  476.18  833.31      0
  8589934592    2147483648     float     sum      -1    17887  480.23  840.41      0    17885  480.29  840.50      0
 17179869184    4294967296     float     sum      -1    35549  483.27  845.72      0    35568  483.01  845.27      0
 34359738368    8589934592     float     sum      -1    70981  484.07  847.12      0    70956  484.24  847.42      0
nccl-test-worker-0:61:113 [1] NCCL INFO comm 0xbae114ae20b0 rank 1 nranks 8 cudaDev 1 busId 901000 - Destroy COMPLETE
nccl-test-worker-1:62:114 [2] NCCL INFO comm 0xb1a0b3217270 rank 6 nranks 8 cudaDev 2 busId 1801000 - Destroy COMPLETE
nccl-test-worker-1:61:115 [1] NCCL INFO comm 0xb32f014e00f0 rank 5 nranks 8 cudaDev 1 busId 901000 - Destroy COMPLETE
nccl-test-worker-0:62:116 [2] NCCL INFO comm 0xb94bc7fa3350 rank 2 nranks 8 cudaDev 2 busId 1801000 - Destroy COMPLETE
nccl-test-worker-0:60:114 [0] NCCL INFO comm 0xb39ac578e8e0 rank 0 nranks 8 cudaDev 0 busId 801000 - Destroy COMPLETE
nccl-test-worker-0:63:115 [3] NCCL INFO comm 0xb3e5a8f93ba0 rank 3 nranks 8 cudaDev 3 busId 1901000 - Destroy COMPLETE
nccl-test-worker-1:63:113 [3] NCCL INFO comm 0xc72d0ce64500 rank 7 nranks 8 cudaDev 3 busId 1901000 - Destroy COMPLETE
nccl-test-worker-1:60:112 [0] NCCL INFO comm 0xaf585d78bbe0 rank 4 nranks 8 cudaDev 0 busId 801000 - Destroy COMPLETE
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 260.778
#
```






## Frequently Asked Questions

If you have a question that is not listed below, you can create an issue in the repo.

- [Are there any features that are not supported when using self-managed nodes?](#are-there-any-features-that-are-not-supported-when-using-self-managed-nodes)
- [I don't see my GPU nodes in the OKE page in the console under worker pools](#i-dont-see-my-gpu-nodes-in-the-oke-page-in-the-console-under-worker-pools)
- [I'm getting the "400-InvalidParameter, Shape <GPU BM shape> is incompatible with image" error](#im-getting-the-400-invalidparameter-shape--is-incompatible-with-image-error)
- [How can I add more SSH keys to my nodes besides the one I chose during deployment?](#how-can-i-add-more-ssh-keys-to-my-nodes-besides-the-one-i-chose-during-deployment)
- [I'm having an issue when running a PyTorch job using RDMA](#im-having-an-issue-when-running-a-pytorch-job-using-rdma)
- [I have large container images. Can I import them from a shared location instead of downloading them?](#i-have-large-container-images-can-i-import-them-from-a-shared-location-instead-of-downloading-them)
- [How can I run GPU & RDMA health checks in my nodes?](#how-can-i-run-gpu--rdma-health-checks-in-my-nodes)
- [Can I autoscale my RDMA enabled nodes in a Cluster Network?](#can-i-autoscale-my-rdma-enabled-nodes-in-a-cluster-network)
- [How do I use network locality information when running workloads on OKE?](#how-do-i-use-network-locality-information-when-running-workloads-on-oke)

### Are there any features that are not supported when using self-managed nodes?
Some features and capabilities are not available, or not yet available, when using self-managed nodes. Please see [this link](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengworkingwithselfmanagednodes.htm) for a list of features and capabilities that are not available for self-managed nodes.

### I don't see my GPU nodes in the OKE page in the console under worker pools
This is expected. Currently, only the worker pools with the `node-pool` mode are listed. Self-managed nodes (`cluster-network` and `instance-pool` modes in worker pools) are not listed in the console in the OKE page.

### I'm getting the "400-InvalidParameter, Shape <GPU BM shape> is incompatible with image" error
Please follow the instructions [here](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/configuringimagecapabilities.htm#configuringimagecapabilities_topic-using_the_console) to add the capability of the shape that you are getting the error to your imported image.

### How can I add more SSH keys to my nodes besides the one I chose during deployment?
You can follow the instructions [here](./docs/adding-ssh-keys-to-worker-nodes.md) to add more SSH keys to your nodes.

### I'm having an issue when running a PyTorch job using RDMA
Please see the instructions [here](./docs/running-pytorch-jobs-on-oke-using-hostnetwork-with-rdma.md) for the best practices on running PyTorch jobs.

### I have large container images. Can I import them from a shared location instead of downloading them?
Yes, you can use OCI's File Storage Service (FSS) with `skopeo` to accomplish that. You can find the instructions [here.](./docs/importing-images-from-fss-skopeo.md)

### How can I run GPU & RDMA health checks in my nodes?
You can deploy the health check script with Node Problem Detector by following the instructions [here.](./docs/running-gpu-rdma-healtchecks-with-node-problem-detector.md)

### Can I autoscale my RDMA enabled nodes in a Cluster Network?
You can setup autoscaling for your nodes in a Cluster Network using the instructions [here.](./docs/using-cluster-autoscaler-with-cluster-networks.md)

### How do I use network locality information when running workloads on OKE?
You can follow the instructions [here.](./docs/using-rdma-network-locality-when-running-workloads-on-oke.md)
