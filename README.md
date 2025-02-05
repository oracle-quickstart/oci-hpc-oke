# Running RDMA (remote direct memory access) GPU workloads on OKE
Oracle Cloud Infrastructure Kubernetes Engine (OKE) is a fully-managed, scalable, and highly available service that you can use to deploy your containerized applications to the cloud.

Please visit the [OKE documentation page](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengoverview.htm) for more information.

### Supported Operating Systems
For the Nvidia A100 and H100 shapes (BM.GPU.H100.8, BM.GPU.A100-v2.8, BM.GPU4.8, BM.GPU.B4.8) and AMD MI300x shape (BM.GPU.MI300X.8), Ubuntu 22.04 is supported.

### Required policies
The OCI Resource Manager stack template uses the [Self Managed Nodes](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengworkingwithselfmanagednodes.htm) functionality of OKE.

Below policies are required. The OCI Resource Manager stack will create them for you if you have the necessary permissions. If you don't have the permissions, please find more information about the policies below.

- [Policy Configuration for Cluster Creation and Deployment](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengpolicyconfig.htm)
- [Creating a Dynamic Group and a Policy for Self-Managed Nodes](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdynamicgrouppolicyforselfmanagednodes.htm)

## Instructions for deploying an OKE cluster with GPUs and RDMA connectivity
You will need a CPU pool and a GPU pool. The OCI Resource Manager stack deploys an operational worker pool by default and you choose to deploy addidional CPU/GPU worker pools.

You can use the below images for both CPU and GPU pools.

> [!NOTE]  
> The GPU image has the GPU drivers pre-installed.

#### Image to import and use for the H100 and A100 nodes
You can use the instructions [here](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/imageimportexport.htm#Importing) for importing the below image to your tenancy.

**Images for NVIDIA shapes**

- [GPU driver 535.183.06 & CUDA 12.2](https://objectstorage.ca-toronto-1.oraclecloud.com/p/KOcEZeDpEAASLSKzumODnVr42mFwM_p9n1_Nra2FsV_F6BcpAkoH66HZxN4cCtIb/n/hpc_limited_availability/b/images/o/Ubuntu-22-OCA-OFED-23.10-2.1.3.1-GPU-535-CUDA-12.2-2024.09.18-0)

- [GPU driver 550.90.12 & CUDA 12.4](https://objectstorage.ca-toronto-1.oraclecloud.com/p/EDngSWYfn3HjrN0xbfBSVCctRVKVvNf3NOW7DdInKMtgiZwiUqy7PsA_xifmI1oq/n/hpc_limited_availability/b/images/o/Ubuntu-22-OCA-OFED-23.10-2.1.3.1-GPU-550-CUDA-12.4-2024.09.18-0)

- [GPU driver 560.35.03 & CUDA 12.6](https://objectstorage.ca-toronto-1.oraclecloud.com/p/a_KKMCajcBpt9EfqgmnZbtUInpc6gdC5s2g1wz7b0KUCLW28DSvTKwMeOSgW5O0R/n/hpc_limited_availability/b/images/o/Ubuntu-22-OCA-OFED-23.10-2.1.3.1-GPU-560-CUDA-12.6-2024.09.18-0)

**Image for AMD shapes**

- [ROCm 6.2](https://objectstorage.us-ashburn-1.oraclecloud.com/p/tpswnRAUmrJ49uLAGk_ku6B13hyGzf_Gv1vrggtDWhOywSM5YGzoMPiO88gc3Cv-/n/imagegen/b/GPU-imaging/o/Ubuntu-22-OFED-5.9-0.5.6.0.127-ROCM-6.2-90-2024.08.12-0.oci)


### Deploy the cluster using the Oracle Cloud Resource Manager template
You can easily deploy the cluster using the **Deploy to Oracle Cloud** button below.

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/oracle-quickstart/oci-hpc-oke/releases/download/v25.2.0/oke-rdma-quickstart-v25.2.0.zip)

For the image ID, use the ID of the image that you imported in the previous step.

The template will deploy a `bastion` instance and an `operator` instance. The `operator` instance will have access to the OKE cluster. You can connect to the `operator` instance via SSH with `ssh -J ubuntu@<bastion IP> ubuntu@<operator IP>`.

You can also find this information under the **Application information** tab in the OCI Resource Manager stack.

### Wait until you see all nodes in the cluster

```sh
kubectl get nodes

NAME           STATUS     ROLES    AGE     VERSION
10.0.103.73    Ready      <none>   2d23h   v1.25.6
10.0.127.206   Ready      node     2d3h    v1.25.6
10.0.127.32    Ready      node     2d3h    v1.25.6
10.0.83.93     Ready      <none>   2d23h   v1.25.6
10.0.96.82     Ready      node     2d23h   v1.25.6
```

### Add a Service Account Authentication Token (optional but recommended)
More info [here.](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengaddingserviceaccttoken.htm)

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
Here's a simple example. You can also look at the NCCL test manifests in the repo [here.](./manifests/)

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
> [!IMPORTANT]  
> The NCCL parameters are different between the H100 and A100 shapes. Please make sure that you are using the correct manifest for your bare metal GPU shapes.

##### BM.GPU.H100
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/BM.GPU.H100.8-nccl-test.yaml
```

##### BM.GPU.A100-v2.8
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/BM.GPU.A100-v2.8-nccl-test.yaml
```

##### BM.GPU4.8
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/BM.GPU4.8-nccl-test.yaml
```

##### BM.GPU.B4.8
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/BM.GPU.B4.8-nccl-test.yaml
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