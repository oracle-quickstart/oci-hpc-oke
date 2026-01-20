# Running RDMA GPU workloads on OKE with GB200s

### Prerequisites
- Your k8s version of the cluster must be at least v1.32.
- If you're planning to use DRA, do not use k8s versions v1.34.0 and v1.34.1 as there's a bug that affects DRA.
- There's a known issue with using the OKE VCN Native CNI for pod networking. With Grace Blackwell clusters, use Flannel for pod networking.

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
oci compute compute-gpu-memory-fabric list --compartment-id $TENANCY_ID
```

### Create cloud-init
Follow the instructions [here](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcloudinitforselfmanagednodes.htm#contengcloudinitforselfmanagednodes) for getting the API Server Host IP and CA cert.

```yaml
#cloud-config
apt:
  sources:
    oke-node: {source: 'deb [trusted=yes] https://objectstorage.us-sanjose-1.oraclecloud.com/p/_Zaa2khW3lPESEbqZ2JB3FijAd0HeKmiP-KA2eOMuWwro85dcG2WAqua2o_a-PlZ/n/odx-oke/b/okn-repositories-private/o/prod/ubuntu-jammy/kubernetes-1.33 stable main'}
packages:
  - oci-oke-node-all-1.33.1
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
#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# REQUIRED VARIABLES
# (Fill these in)
# -----------------------------
REGION=""
COMPARTMENT_ID=""
AD=""
WORKER_SUBNET_ID=""
WORKER_SUBNET_NSG_ID=""
POD_SUBNET_ID=""
POD_SUBNET_NSG_ID=""
IMAGE_ID=""
SHAPE=""

# -----------------------------
# Encode cloud-init
# -----------------------------
BASE64_ENCODED_CLOUD_INIT=$(base64 -w 0 cloud-init.yml)

# -----------------------------
# Create Instance Configuration
# -----------------------------
oci --region "${REGION}" \
  compute-management instance-configuration create \
  --compartment-id "${COMPARTMENT_ID}" \
  --display-name gb200-oke \
  --instance-details "$(cat <<EOF
{
  "instanceType": "compute",
  "launchDetails": {
    "availabilityDomain": "${AD}",
    "compartmentId": "${COMPARTMENT_ID}",
    "createVnicDetails": {
      "assignIpv6Ip": false,
      "assignPublicIp": false,
      "assignPrivateDnsRecord": true,
      "subnetId": "${WORKER_SUBNET_ID}",
      "nsgIds": [
        "${WORKER_SUBNET_NSG_ID}"
      ]
    },
    "metadata": {
      "user_data": "${BASE64_ENCODED_CLOUD_INIT}",
      "oke-native-pod-networking": "true",
      "oke-max-pods": "60",
      "pod-subnets": "${POD_SUBNET_ID}",
      "pod-nsgids": "${POD_SUBNET_NSG_ID}"
    },
    "shape": "${SHAPE}",
    "sourceDetails": {
      "bootVolumeSizeInGBs": "512",
      "bootVolumeVpusPerGB": "20",
      "sourceType": "image",
      "imageId": "${IMAGE_ID}"
    },
    "agentConfig": {
      "isMonitoringDisabled": false,
      "isManagementDisabled": false,
      "pluginsConfig": [
        { "name": "WebLogic Management Service", "desiredState": "DISABLED" },
        { "name": "Vulnerability Scanning", "desiredState": "DISABLED" },
        { "name": "Oracle Java Management Service", "desiredState": "DISABLED" },
        { "name": "Oracle Autonomous Linux", "desiredState": "DISABLED" },
        { "name": "OS Management Service Agent", "desiredState": "DISABLED" },
        { "name": "OS Management Hub Agent", "desiredState": "DISABLED" },
        { "name": "Management Agent", "desiredState": "DISABLED" },
        { "name": "Custom Logs Monitoring", "desiredState": "ENABLED" },
        { "name": "Compute RDMA GPU Monitoring", "desiredState": "ENABLED" },
        { "name": "Compute Instance Run Command", "desiredState": "ENABLED" },
        { "name": "Compute Instance Monitoring", "desiredState": "ENABLED" },
        { "name": "Compute HPC RDMA Auto-Configuration", "desiredState": "ENABLED" },
        { "name": "Compute HPC RDMA Authentication", "desiredState": "ENABLED" },
        { "name": "Cloud Guard Workload Protection", "desiredState": "DISABLED" },
        { "name": "Block Volume Management", "desiredState": "DISABLED" },
        { "name": "Bastion", "desiredState": "DISABLED" }
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
}
EOF
)"

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

### Delete the OCI GPU device plugin

```
oci ce cluster disable-addon --cluster-id $CLUSTER_ID --addon-name NvidiaGpuPlugin --is-remove-existing-add-on true
```

### Install GPU Operator
```
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

```
helm install gpu-operator nvidia/gpu-operator \
    --version=v25.10.1 \
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
    --version=25.8.1 \
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

### Install MPI Operator

```
kubectl apply --server-side -f https://raw.githubusercontent.com/kubeflow/mpi-operator/v0.6.0/deploy/v2beta1/mpi-operator.yaml
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
    image: docker.io/library/ubuntu:22.04
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

### RUN NCCL tests

#### Install MPI Operator
```
kubectl create -f https://github.com/kubeflow/mpi-operator/releases/download/v0.7.0/mpi-operator.yaml
```

Run the manifest that matches your shape.

#### BM.GPU.GB200-v3.4
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.GB200-v3.4.yaml
```

#### BM.GPU.GB200-v2.4
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.GB200-v2.4.yaml
```

#### BM.GPU.GB200.4
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.GB200.4.yaml
```

Example results from 32 BM.GPU.GB200-v3.4 nodes across two racks.

```
#  Rank 127 Group  0 Pid    137 on instance20260116093132 device  3 [0019:06:00] NVIDIA GB200
NCCL version 2.29.2+cuda13.1
#
#                                                              out-of-place                       in-place
#       size         count      type   redop    root     time   algbw   busbw  #wrong     time   algbw   busbw  #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)             (us)  (GB/s)  (GB/s)
           8             2     float     sum      -1   183.82    0.00    0.00       0   184.74    0.00    0.00       0
          16             4     float     sum      -1   182.39    0.00    0.00       0   180.02    0.00    0.00       0
          32             8     float     sum      -1   186.04    0.00    0.00       0   185.23    0.00    0.00       0
          64            16     float     sum      -1   188.40    0.00    0.00       0   188.34    0.00    0.00       0
         128            32     float     sum      -1   189.93    0.00    0.00       0   191.67    0.00    0.00       0
         256            64     float     sum      -1   195.43    0.00    0.00       0   194.25    0.00    0.00       0
         512           128     float     sum      -1   196.14    0.00    0.01       0   195.68    0.00    0.01       0
        1024           256     float     sum      -1   196.95    0.01    0.01       0   197.64    0.01    0.01       0
        2048           512     float     sum      -1   198.13    0.01    0.02       0   196.26    0.01    0.02       0
        4096          1024     float     sum      -1   200.63    0.02    0.04       0   199.78    0.02    0.04       0
        8192          2048     float     sum      -1   203.86    0.04    0.08       0   201.84    0.04    0.08       0
       16384          4096     float     sum      -1   202.63    0.08    0.16       0   201.77    0.08    0.16       0
       32768          8192     float     sum      -1   204.44    0.16    0.32       0   203.14    0.16    0.32       0
       65536         16384     float     sum      -1   202.89    0.32    0.64       0   204.08    0.32    0.64       0
      131072         32768     float     sum      -1   209.01    0.63    1.24       0   207.46    0.63    1.25       0
      262144         65536     float     sum      -1   231.46    1.13    2.25       0   230.43    1.14    2.26       0
      524288        131072     float     sum      -1   227.34    2.31    4.58       0   226.52    2.31    4.59       0
     1048576        262144     float     sum      -1   291.13    3.60    7.15       0   291.53    3.60    7.14       0
     2097152        524288     float     sum      -1   309.86    6.77   13.43       0   311.71    6.73   13.35       0
     4194304       1048576     float     sum      -1   314.13   13.35   26.50       0   314.72   13.33   26.45       0
     8388608       2097152     float     sum      -1   340.95   24.60   48.82       0   340.21   24.66   48.93       0
    16777216       4194304     float     sum      -1   394.98   42.48   84.29       0   394.45   42.53   84.40       0
    33554432       8388608     float     sum      -1   503.72   66.61  132.19       0   500.67   67.02  132.99       0
    67108864      16777216     float     sum      -1   654.11  102.60  203.59       0   654.58  102.52  203.44       0
   134217728      33554432     float     sum      -1   976.10  137.50  272.86       0   975.42  137.60  273.05       0
   268435456      67108864     float     sum      -1  1555.75  172.54  342.39       0  1558.13  172.28  341.87       0
   536870912     134217728     float     sum      -1  2592.03  207.12  411.01       0  2593.05  207.04  410.85       0
  1073741824     268435456     float     sum      -1  7487.21  143.41  284.58       0  7468.65  143.77  285.29       0
  2147483648     536870912     float     sum      -1  7758.06  276.81  549.29       0  7787.58  275.76  547.21       0
  4294967296    1073741824     float     sum      -1  13341.2  321.93  638.83       0  13322.7  322.38  639.72       0
  8589934592    2147483648     float     sum      -1  25812.5  332.78  660.36       0  26264.9  327.05  648.99       0
 17179869184    4294967296     float     sum      -1  50409.2  340.81  676.29       0  50431.7  340.66  675.99       0
 34359738368    8589934592     float     sum      -1  99744.6  344.48  683.57       0  99756.3  344.44  683.49       0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 152.682
#
# Collective test concluded: all_reduce_perf
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
