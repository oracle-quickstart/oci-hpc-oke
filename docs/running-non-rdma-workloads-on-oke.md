# Running non-RDMA GPU workloads on OKE

For running GPU workloads that do not require the use of RDMA, you have two alternative options.

## Option #1: Running workloads on GPU nodes without using the GPU Operator
If you don't need to deploy the GPU driver as a container in your OKE cluster with the GPU Operator, you can just create a worker pool using on of the support GPU shapes. OKE will configure the GPU nodes automatically. You can refer to the [OKE documentation here](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengrunninggpunodes.htm) for more information.

## Option #2: Running workloads on GPU nodes with using the GPU Operator
The second option is using the [GPU Operator](https://github.com/NVIDIA/gpu-operator) for deploying the GPU driver and other components.

### Deploy the cluster using the Terraform template
You can find the template in the [terraform directory](../terraform/non-rdma/).

Make sure to update the image IDs in the `worker pools` blocks.

The template will deploy a `bastion` instance and an `operator` instance. The `operator` instance will have access to the OKE cluster. You can connect to the `operator` instance via SSH with `ssh -J opc@<bastion IP> opc@<operator IP>`.

### Build the GPU driver container image
For deploying the GPU Operator to your cluster, you will need to build a GPU driver container image for Oracle Linux. Follow the instructions [here](building-ol7-gpu-operator-driver-image.md). After you built the GPU driver container image, continue with the instructions below.

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
Use the container image you built in the `Build the GPU Operator driver container image for Oracle Linux` earlier.

Change the `driver.repository` and `driver.version` in the Helm command below.

```
helm install --wait \
  -n gpu-operator --create-namespace \
  gpu-operator nvidia/gpu-operator \
  --version v23.3.2 \
  --set operator.defaultRuntime=crio \
  --set driver.repository=<The repository that you pushed your image> \
  --set driver.version=<The driver version in your pushed image. Only the version, don't add ol7.9 at the end> \
  --set toolkit.version=v1.13.5-centos7 \
  --set driver.rdma.enabled=true \
  --set driver.rdma.useHostMofed=true
```

Wait until all network operator pods are running with `kubectl get pods -n gpu-operator`.

### Test the GPU Operator image you built
Save the following manifest as yaml and then deploy it.

```
apiVersion: v1
kind: Pod
metadata:
  name: nvidia-version-check
spec:
  restartPolicy: OnFailure
  containers:
  - name: nvidia-version-check
    image: nvidia/cuda:11.7.1-base-ubuntu20.04
    command: ["nvidia-smi"]
    resources:
      limits:
         nvidia.com/gpu: "1"
```

Get the logs from the above pod by running `kubectl logs nvidia-version-check`, you should see the `nvidia-smi` output correctly listing the GPU driver and CUDA version.