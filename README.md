# Running RDMA (remote direct memory access) GPU workloads on OKE using AMD MI300X

### Supported Operating Systems
Please contact your sales representative for getting the image compatible with AMD MI300X.

### Required policies
The OCI Resource Manager stack template uses the [Self Managed Nodes](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengworkingwithselfmanagednodes.htm) functionality of OKE.

Below policies are required. The OCI Resource Manager stack will create them for you if you have the necessary permissions. If you don't have the permissions, please find more information about the policies below.

- [Policy Configuration for Cluster Creation and Deployment](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengpolicyconfig.htm)
- [Creating a Dynamic Group and a Policy for Self-Managed Nodes](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdynamicgrouppolicyforselfmanagednodes.htm)

## Instructions for deploying an OKE cluster with GPUs and RDMA connectivity
You will need a CPU pool and a GPU pool. The OCI Resource Manager stack deploys an operational worker pool by default and you choose to deploy addidional CPU/GPU worker pools.

#### Image to import and use for the H100 and A100 nodes
Please contact your sales representative for getting the image compatible with AMD MI300X.

### Deploy the cluster using the Oracle Cloud Resource Manager template
You can easily deploy the cluster using the **Deploy to Oracle Cloud** button below.

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/oracle-quickstart/oci-hpc-oke/releases/download/v24.7.1/oke-rdma-quickstart-v24.7.1.zip)

For the image ID, use the ID of the image that you imported in the previous step.

The template will deploy a `bastion` instance and an `operator` instance. The `operator` instance will have access to the OKE cluster. You can connect to the `operator` instance via SSH with `ssh -J opc@<bastion IP> opc@<operator IP>`.

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

### Deploy the AMD GPU device plugin
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/mi300x/manifests/ds-amdgpu-deviceplugin.yaml
```

### Run the test pod to confirm the GPUs are available
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/mi300x/manifests/amd-smi.yaml
```
After the container finished running, run `kubectl logs amd-version-check`.

```
kubectl logs amd-version-check

AMDSMI Tool: 24.5.1+c5106a9 | AMDSMI Library version: 24.5.2.0 | ROCm version: 6.1.2
GPU: 0
    BDF: 0000:11:00.0
    UUID: d4ff74a1-0000-1000-80b1-dbb1e6a69543

GPU: 1
    BDF: 0000:2f:00.0
    UUID: ccff74a1-0000-1000-8097-03f9b4bc331b

GPU: 2
    BDF: 0000:46:00.0
    UUID: 91ff74a1-0000-1000-80ee-7b68b869c2f7

GPU: 3
    BDF: 0000:5d:00.0
    UUID: 55ff74a1-0000-1000-801c-58461786bea3

GPU: 4
    BDF: 0000:8b:00.0
    UUID: 43ff74a1-0000-1000-80a6-10e214063eb5

GPU: 5
    BDF: 0000:aa:00.0
    UUID: a8ff74a1-0000-1000-80e5-4939c30a8ee2

GPU: 6
    BDF: 0000:c2:00.0
    UUID: aeff74a1-0000-1000-80fe-27257d976fb0

GPU: 7
    BDF: 0000:da:00.0
    UUID: 99ff74a1-0000-1000-8026-2e7bfcd71f9a
```

### Run the RCCL test

#### Deploy Volcano
```
helm repo add volcano-sh https://volcano-sh.github.io/helm-charts
helm install volcano volcano-sh/volcano -n volcano-system --create-namespace

kubectl create serviceaccount -n default mpi-worker-view
kubectl create rolebinding default-view --namespace default --serviceaccount default:mpi-worker-view --clusterrole view
```

#### Deploy the RCCL test pods
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/mi300x/manifests/BM.GPU.MI300X.8.yaml
```
#### Exec into the `mpimaster` pod and run the RCCL test

```
kubectl exec -it rccl-tests-job0-mpimaster-0 -- bash
```

When you're inside the `mpimaster` pods, run the following command to run the RCCL test:

```
NUM_GPUS=8
NUM_HOSTS=$(sed -n '$=' /etc/volcano/mpiworker.host)
NP=$(($NUM_HOSTS*$NUM_GPUS))
mpirun --allow-run-as-root \
  -mca plm_rsh_args "-p 2222" \
  -mca pml ucx \
  -np $NP -npernode $NUM_GPUS --bind-to numa \
  -hostfile /etc/volcano/mpiworker.host \
  -x NCCL_DEBUG=WARN \
  -x NCCL_MIN_CHANNEL=32 \
  -x NCCL_IB_QPS_PER_CONNECTION=1 \
  -x NCCL_IB_GID_INDEX=3 \
  -x NCCL_IB_HCA="=mlx5_0,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_7,mlx5_8,mlx5_9" \
  -x NCCL_IB_HCA=^="mlx5_1,mlx5_6" \
  -x NCCL_IB_SL=0 \
  -x NCCL_IB_TIMEOUT=22 \
  -x UCX_TLS=tcp \
  -x UCX_NET_DEVICES=eth0 \
  -x NCCL_NET_GDR_LEVEL=3 \
  -x NCCL_SOCKET_IFNAME=eth0 \
  -x NCCL_IGNORE_CPU_AFFINITY=1 \
  -x RX_QUEUE_LEN=8192 \
  -x IB_RX_QUEUE_LEN=8192 \
  -x LD_LIBRARY_PATH=$LD_LIBRARY_PATH \
  all_reduce_perf -b 1G -f 2 -e 16G -g 1
```



