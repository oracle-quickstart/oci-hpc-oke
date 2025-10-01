# Running RDMA (remote direct memory access) GPU workloads on OKE
Oracle Cloud Infrastructure Kubernetes Engine (OKE) is a fully-managed, scalable, and highly available service that you can use to deploy your containerized applications to the cloud.

### Supported Operating Systems
- Ubuntu 22.04
- Oracle Linux 8 (except for the GPU & RDMA worker pool)

### Required policies
The following policies are required. The OCI Resource Manager stack will create them for you if you have the necessary permissions. If you don't have the permissions, please find more information about the policies below.

- [Policy Configuration for Cluster Creation and Deployment](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengpolicyconfig.htm)
- [Creating a Dynamic Group and a Policy for Self-Managed Nodes](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdynamicgrouppolicyforselfmanagednodes.htm)

## Instructions for deploying an OKE cluster with GPUs and RDMA connectivity
You will need a CPU pool and a GPU pool. The OCI Resource Manager stack deploys an operational worker pool by default and you choose to deploy additional CPU/GPU worker pools.

You can use the following images for both CPU and GPU pools.

> [!NOTE]  
> The GPU image has the GPU drivers pre-installed.

#### Images to use
You can use the instructions [here](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/imageimportexport.htm#Importing) for importing the below image to your tenancy.

**Image to use for non-GPU nodes**

- [Link to import the image](https://objectstorage.us-chicago-1.oraclecloud.com/p/O1VP9Rx0p7uWKRQW6739ZzTbnUPK5F8cvlN0apUaiO_cF5x9R2ESYN6yskW0FUVq/n/hpc_limited_availability/b/oke-images-do-not-delete/o/Canonical-Ubuntu-22.04-2025.03.28-0-OKE)

**Images for NVIDIA shapes**

- [GPU driver 570 & CUDA 12.8](https://objectstorage.ca-montreal-1.oraclecloud.com/p/ts6fjAuj7hY4io5x_jfX3fyC70HRCG8-9gOFqAjuF0KE0s-6tgDZkbRRZIbMZmoN/n/hpc_limited_availability/b/images/o/Canonical-Ubuntu-22.04-2025.05.20-0-OFED-24.10-1.1.4.0-GPU-570-OPEN-CUDA-12.8-2025.07.22-0)

- [GPU driver 550 & CUDA 12.4](https://objectstorage.ca-montreal-1.oraclecloud.com/p/ts6fjAuj7hY4io5x_jfX3fyC70HRCG8-9gOFqAjuF0KE0s-6tgDZkbRRZIbMZmoN/n/hpc_limited_availability/b/images/o/Canonical-Ubuntu-22.04-2025.05.20-0-OFED-24.10-1.1.4.0-GPU-550-CUDA-12.4-2025.07.22-0)


**Image for AMD shapes**

- [ROCm 6.3.2](https://objectstorage.ca-montreal-1.oraclecloud.com/p/ts6fjAuj7hY4io5x_jfX3fyC70HRCG8-9gOFqAjuF0KE0s-6tgDZkbRRZIbMZmoN/n/hpc_limited_availability/b/images/o/Canonical-Ubuntu-22.04-2025.05.20-0-OFED-24.10-1.1.4.0-AMD-ROCM-632-2025.07.23-0)


### Deploy the cluster using the Oracle Cloud Resource Manager template
You can easily deploy the cluster using the **Deploy to Oracle Cloud** button below.

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/oracle-quickstart/oci-hpc-oke/releases/latest/download/oke-gpu-rdma-quickstart.zip)

For the image ID, use the ID of the image that you imported in the previous step.

The template will deploy a `bastion` instance and an `operator` instance by default. The `operator` instance will have access to the OKE cluster. You can connect to the `operator` instance via SSH with `ssh -J ubuntu@<bastion IP> ubuntu@<operator IP>`.

You can also find this information under the **Application information** tab in the OCI Resource Manager stack.

### Wait until you see all nodes in the cluster

```sh
kubectl get nodes

NAME           STATUS     ROLES    AGE     VERSION
10.0.103.73    Ready      <none>   2d23h   v1.31.1
10.0.127.206   Ready      node     2d3h    v1.31.1
10.0.127.32    Ready      node     2d3h    v1.31.1
10.0.83.93     Ready      <none>   2d23h   v1.31.1
10.0.96.82     Ready      node     2d23h   v1.31.1
```

### Add a Service Account Authentication Token (optional but recommended)
More info [here](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengaddingserviceaccttoken.htm).

```
kubectl -n kube-system create serviceaccount kubeconfig-sa

kubectl create clusterrolebinding add-on-cluster-admin --clusterrole=cluster-admin --serviceaccount=kube-system:kubeconfig-sa

kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/service-account/oke-kubeconfig-sa-token.yaml

TOKEN=$(kubectl -n kube-system get secret oke-kubeconfig-sa-token -o jsonpath='{.data.token}' | base64 --decode)

kubectl config set-credentials kubeconfig-sa --token=$TOKEN

kubectl config set-context --current --user=kubeconfig-sa
```

### Using the host RDMA network interfaces in manifests
In order to use the RDMA interfaces on the host in your pods, you should have the below sections in your manifests:

```yaml
spec:
  hostNetwork: true
  dnsPolicy: ClusterFirstWithHostNet
  volumes:
  - { name: devinf, hostPath: { path: /dev/infiniband }}
  - { name: shm, emptyDir: { medium: Memory, sizeLimit: 32Gi }}
```

```yaml
securityContext:
      privileged: true
      capabilities:
        add: [ "IPC_LOCK" ]
```
```yaml
    volumeMounts:
    - { mountPath: /dev/infiniband, name: devinf }
    - { mountPath: /dev/shm, name: shm }
```
Here's a simple example. You can also look at the NCCL test manifests in the repo [here](./manifests/).

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rdma-test-pod-1
spec:
  hostNetwork: true
  dnsPolicy: ClusterFirstWithHostNet
  volumes:
  - { name: devinf, hostPath: { path: /dev/infiniband }}
  - { name: shm, emptyDir: { medium: Memory, sizeLimit: 32Gi }}
  restartPolicy: OnFailure
  containers:
  - image: oguzpastirmaci/mofed-perftest:5.4-3.6.8.1-ubuntu20.04-amd64
    name: mofed-test-ctr
    securityContext:
      privileged: true
      capabilities:
        add: [ "IPC_LOCK" ]
    volumeMounts:
    - { mountPath: /dev/infiniband, name: devinf }
    - { mountPath: /dev/shm, name: shm }
    resources:
      requests:
        cpu: 8
        ephemeral-storage: 32Gi
        memory: 2Gi
    command:
    - sh
    - -c
    - |
      ls -l /dev/infiniband /sys/class/net
      sleep 1000000
```

### Optional - Deploy Kueue & MPI Operator to run NCCL tests
Kueue & MPI Operator are needed for running the optional NCCL tests.

#### Deploy MPI Operator & Kueue
```sh
kubectl apply --server-side -f https://raw.githubusercontent.com/kubeflow/mpi-operator/v0.6.0/deploy/v2beta1/mpi-operator.yaml

helm install kueue oci://registry.k8s.io/kueue/charts/kueue --version="0.13.4" --create-namespace --namespace=kueue-system
```

#### Run the NCCL/RCCL tests
> [!IMPORTANT]  
> The NCCL parameters are different between different shapes. Please make sure that you are using the correct manifest for your bare metal GPU shapes.

##### BM.GPU.GB200-v2.4
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.GB200-v2.4.yaml
```

##### BM.GPU.GB200.4
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.GB200.4.yaml
```

##### BM.GPU.H200
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.H200.8.yaml
```

##### BM.GPU.H100
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.H100.8.yaml
```

##### BM.GPU.A100-v2.8
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.A100-v2.8.yaml
```

##### BM.GPU4.8
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU4.8.yaml
```

##### BM.GPU.B4.8
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.B4.8.yaml
```

The initial pull of the container will take long. Once the launcher pod `nccl-test-launcher-XXXXX` starts running, you can check its logs for the NCCL test result.

```sh
Waiting for workers to be ready...
All workers are ready!
Warning: Permanently added '[nccl-test-worker-1.nccl-test.default.svc]:2222' (ED25519) to the list of known hosts.
Warning: Permanently added '[nccl-test-worker-0.nccl-test.default.svc]:2222' (ED25519) to the list of known hosts.
# nThread 1 nGpus 1 minBytes 1073741824 maxBytes 4294967296 step: 2(factor) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid     88 on inst-fufd1-oke-rdma device  0 [0000:0f:00] NVIDIA A100-SXM4-40GB
#  Rank  1 Group  0 Pid     89 on inst-fufd1-oke-rdma device  1 [0000:15:00] NVIDIA A100-SXM4-40GB
#  Rank  2 Group  0 Pid     90 on inst-fufd1-oke-rdma device  2 [0000:51:00] NVIDIA A100-SXM4-40GB
#  Rank  3 Group  0 Pid     91 on inst-fufd1-oke-rdma device  3 [0000:54:00] NVIDIA A100-SXM4-40GB
#  Rank  4 Group  0 Pid     92 on inst-fufd1-oke-rdma device  4 [0000:8d:00] NVIDIA A100-SXM4-40GB
#  Rank  5 Group  0 Pid     93 on inst-fufd1-oke-rdma device  5 [0000:92:00] NVIDIA A100-SXM4-40GB
#  Rank  6 Group  0 Pid     94 on inst-fufd1-oke-rdma device  6 [0000:d6:00] NVIDIA A100-SXM4-40GB
#  Rank  7 Group  0 Pid     95 on inst-fufd1-oke-rdma device  7 [0000:da:00] NVIDIA A100-SXM4-40GB
#  Rank  8 Group  0 Pid     88 on inst-aqu5j-oke-rdma device  0 [0000:0f:00] NVIDIA A100-SXM4-40GB
#  Rank  9 Group  0 Pid     89 on inst-aqu5j-oke-rdma device  1 [0000:15:00] NVIDIA A100-SXM4-40GB
#  Rank 10 Group  0 Pid     90 on inst-aqu5j-oke-rdma device  2 [0000:51:00] NVIDIA A100-SXM4-40GB
#  Rank 11 Group  0 Pid     91 on inst-aqu5j-oke-rdma device  3 [0000:54:00] NVIDIA A100-SXM4-40GB
#  Rank 12 Group  0 Pid     92 on inst-aqu5j-oke-rdma device  4 [0000:8d:00] NVIDIA A100-SXM4-40GB
#  Rank 13 Group  0 Pid     93 on inst-aqu5j-oke-rdma device  5 [0000:92:00] NVIDIA A100-SXM4-40GB
#  Rank 14 Group  0 Pid     94 on inst-aqu5j-oke-rdma device  6 [0000:d6:00] NVIDIA A100-SXM4-40GB
#  Rank 15 Group  0 Pid     96 on inst-aqu5j-oke-rdma device  7 [0000:da:00] NVIDIA A100-SXM4-40GB
NCCL version 2.25.1+cuda12.8
#
#                                                              out-of-place                       in-place          
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)       
  1073741824     268435456     float     sum      -1    10776   99.64  186.83      0    10781   99.60  186.75      0
  2147483648     536870912     float     sum      -1    21287  100.88  189.15      0    21299  100.82  189.05      0
  4294967296    1073741824     float     sum      -1    42381  101.34  190.02      0    42364  101.38  190.09      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 188.648 
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
Yes, you can use OCI's File Storage Service (FSS) with `skopeo` to accomplish that. You can find the instructions [here](./docs/importing-images-from-fss-skopeo.md).

### How can I run GPU & RDMA health checks in my nodes?
You can deploy the health check script with Node Problem Detector by following the instructions [here](./docs/running-gpu-rdma-healtchecks-with-node-problem-detector.md).

### Can I autoscale my RDMA enabled nodes in a Cluster Network?
You can set up autoscaling for your nodes in a Cluster Network using the instructions [here](./docs/using-cluster-autoscaler-with-cluster-networks.md).

### How do I use network locality information when running workloads on OKE?
You can follow the instructions [here](./docs/using-rdma-network-locality-when-running-workloads-on-oke.md).

## Contributing

This project welcomes contributions from the community. Before submitting a pull request, please [review our contribution guide](./CONTRIBUTING.md)

## Security

Please consult the [security guide](./SECURITY.md) for our responsible security vulnerability disclosure process
