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

### Disable the Nvidia GPU device plugin

```sh
kubectl label nodes -l node.kubernetes.io/instance-type=BM.GPU.MI300X.8 oci.oraclecloud.com/disable-gpu-device-plugin=true
```

### Label and taint the BM.GPU.MI300X.8 nodes with the necessary values

```sh
kubectl label nodes -l node.kubernetes.io/instance-type=BM.GPU.MI300X.8 amd.com/gpu=true
```

```sh
kubectl taint nodes -l node.kubernetes.io/instance-type=BM.GPU.MI300X.8 amd.com/gpu=present:NoSchedule
```
### Remove the Nvidia taint

```sh
kubectl taint nodes -l node.kubernetes.io/instance-type=BM.GPU.MI300X.8 nvidia.com/gpu=present:NoSchedule-
```

### Deploy the AMD GPU device plugin
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/mi300x/manifests/ds-amdgpu-deviceplugin.yaml
