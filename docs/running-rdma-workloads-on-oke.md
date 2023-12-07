
# Running non-RDMA GPU workloads on OKE with the GPU Operator

The deployment uses the [GPU Operator](https://github.com/NVIDIA/gpu-operator) for deploying the GPU driver and other components.

### What is NVIDIA GPU Operator?
Kubernetes provides access to special hardware resources such as NVIDIA GPUs, NICs, Infiniband adapters and other devices through the device plugin framework. However, configuring and managing nodes with these hardware resources requires configuration of multiple software components such as drivers, container runtimes or other libraries which are difficult and prone to errors. The NVIDIA GPU Operator uses the operator framework within Kubernetes to automate the management of all NVIDIA software components needed to provision GPU. These components include the NVIDIA drivers (to enable CUDA), Kubernetes device plugin for GPUs, the NVIDIA Container Runtime, automatic node labelling, DCGM based monitoring and others.

### What is NVIDIA Network Operator?
NVIDIA Network Operator leverages Kubernetes CRDs and Operator SDK to manage Networking related Components in order to enable Fast networking, RDMA and GPUDirect for workloads in a Kubernetes cluster.

The Goal of Network Operator is to manage all networking related components to enable execution of RDMA and GPUDirect RDMA workloads in a kubernetes cluster including:

- Mellanox Networking drivers to enable advanced features
- Kubernetes device plugins to provide hardware resources for fast network
- Kubernetes secondary network for Network intensive workloads

### Deploy the cluster using the Terraform template
You can find the template in the [terraform directory](../terraform/rdma/).

Make sure to update the image IDs in the `worker pools` blocks.

You can find more information on setting up Terraform for OCI [here](https://docs.oracle.com/en-us/iaas/developer-tutorials/tutorials/tf-provider/01-summary.htm).

The template will deploy a `bastion` instance and an `operator` instance. The `operator` instance will have access to the OKE cluster. You can connect to the `operator` instance via SSH with `ssh -J opc@<bastion IP> opc@<operator IP>`.

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

You can change the `driver.version` in the Helm command below if you need to use a different version. Check [here](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html#gpu-operator-component-matrix) for supported versions.

```
helm install --wait \
  -n gpu-operator --create-namespace \
  gpu-operator nvidia/gpu-operator \
  --version v23.9.0 \
  --set operator.defaultRuntime=crio \
  --set driver.version=535.104.12
```

Wait until all network operator pods are running with `kubectl get pods -n gpu-operator`.

### Deploy Network Operator

```
helm install --wait \
  -n network-operator --create-namespace \
  network-operator nvidia/network-operator \
  --version v23.7.0 \
  --set deployCR=true \
  --set nfd.enabled=false \
  --set rdmaSharedDevicePlugin.deploy=false \
  --set nvPeerDriver.deploy=true \
  --set sriovDevicePlugin.deploy=true \
  --set-json sriovDevicePlugin.resources='[{"name": "sriov_rdma_vf", "drivers": ["mlx5_core"], "devices": ["101a"], "isRdma": [true]}]'
```

Wait until all network operator pods are running with `kubectl get pods -n network-operator`.

### Confirm that the GPUs are VFs are correctly exposed
```
kubectl get nodes -l 'node.kubernetes.io/instance-type in (BM.GPU.H100.8, BM.GPU.A100-v2.8, BM.GPU4.8, BM.GPU.B4.8)' --sort-by=.status.capacity."nvidia\.com/sriov_rdma_vf" -o=custom-columns='NODE:metadata.name,GPUs:status.allocatable.nvidia\.com/gpu,RDMA-VFs:status.allocatable.nvidia\.com/sriov_rdma_vf'

NODE            GPUs   RDMA-VFs
10.79.148.115   8      16
10.79.151.167   8      16
10.79.156.205   8      16
```

### Create Network Attachment Definition

```sh
kubectl apply -f 
```