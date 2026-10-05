# Installing Dranet Manually on OKE (Preview)

> [!NOTE]
> This is a preview feature. Do not use it for production workloads.

[Dranet](https://github.com/kubernetes-sigs/dranet) gives pods IPvlan children of the RDMA NICs of a node. The stack installs it when you set `install_dranet = true` (see [Using Dranet for RDMA Network Interfaces](using-dranet.md)). Use the steps below on an OKE cluster that the stack did not create.

## Requirements

- Kubernetes 1.34 or later. Dranet uses the `resource.k8s.io/v1` Dynamic Resource Allocation (DRA) API.
- A single-stack IPv4 cluster. Dranet does not support IPv6 yet. The exception is a GPU Memory Cluster with the `BM.GPU.GB200.4` shape, which uses native InfiniBand.
- Bare metal GPU nodes with RDMA NICs. Oracle Cloud Agent (OCA) must configure the RDMA NICs, which the OKE GPU images do.
- No NVIDIA Network Operator with SR-IOV. Its virtual functions need the exclusive RDMA network namespace mode, and Dranet needs the shared mode.
- Helm 3.8 or later, and `kubectl` access to the cluster.

## Step 1: Set the shared RDMA network namespace mode

Dranet claims need the RDMA subsystem in shared network namespace mode (`netns_mode=1` for `ib_core`). The worker images use the exclusive mode. The mode cannot change at runtime while pods exist, so set it before the node starts its pods.

### New nodes

Add these commands to the cloud-init of the node pool, before the command that bootstraps the node (on the OKE Ubuntu images, `oke bootstrap`):

```yaml
runcmd:
  - curl -sL -o /var/run/oke-rdma-netns.sh https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/terraform/files/rdma/rdma-netns.sh
  - bash /var/run/oke-rdma-netns.sh shared
```

The script does nothing on nodes without RDMA NICs. On RDMA nodes, it writes `options ib_core netns_mode=1` to `/etc/modprobe.d/ib_core.conf`, updates the initramfs, and sets the mode for the current boot. The stack uses the same script.

### Existing nodes

Do these steps on each RDMA node:

1. Move the workloads off the node:

   ```sh
   kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
   ```

2. On the node, set the mode and reboot. These commands are for the OKE Ubuntu images:

   ```sh
   echo "options ib_core netns_mode=1" | sudo tee /etc/modprobe.d/ib_core.conf
   sudo update-initramfs -u
   sudo reboot
   ```

3. After the reboot, make sure that the mode is shared:

   ```sh
   rdma system show netns
   ```

   The output starts with `netns shared`.

4. Let the node take workloads again:

   ```sh
   kubectl uncordon <node>
   ```

## Step 2: Install Dranet

```sh
helm install dranet oci://registry.k8s.io/networking/charts/dranet --version v1.5.0 \
  --namespace kube-system
```

The chart tolerates all `NoSchedule` taints, so Dranet also runs on the GPU nodes.

> [!NOTE]
> On the `BM.GPU.GB200.4` shape, add `--set args.moveIBInterfaces=false` to the command. This shape uses native InfiniBand NICs, and Dranet claims for them fail without this setting. The setting keeps the NICs on the host, where the OKE health checks read them. It has no effect on the other shapes, which use RoCE NICs.

## Step 3: Create the DeviceClass

The chart does not create a DeviceClass. Create the `dra.net` DeviceClass that the claims and the test manifests use:

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/terraform/files/dranet/deviceclass.yaml
```

The file contains:

```yaml
apiVersion: resource.k8s.io/v1
kind: DeviceClass
metadata:
  name: dra.net
spec:
  selectors:
  - cel:
      expression: device.driver == "dra.net"
```

## Step 4: Check the installation

```sh
kubectl -n kube-system rollout status daemonset/dranet
kubectl get resourceslices --field-selector spec.driver=dra.net \
  -o 'custom-columns=NODE:.spec.nodeName,NICS:.spec.devices[*].attributes.dra\.net/ifName.string'
```

Each RDMA node lists its RDMA NICs, for example `rdma0` to `rdma15`. The names depend on the shape.

## Step 5 (optional): Configure Kueue

Kueue v0.18 and later reject pods with Dranet claims unless Kueue maps the `dra.net` DeviceClass to a resource. To run the Dranet test manifests through Kueue:

- Install or upgrade Kueue with the stack values file, which maps the DeviceClass to the `dra.net/nic` resource. Kueue v0.20 no longer serves the `v1beta1` API. If Kueue is already installed, do the stored version check in [Deploy MPI Operator and Kueue](running-nccl-rccl-tests.md#deploy-mpi-operator-and-kueue) before you upgrade.

  ```sh
  helm upgrade --install kueue oci://registry.k8s.io/kueue/charts/kueue --version="0.20.0" \
    --create-namespace --namespace=kueue-system \
    -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/terraform/files/kueue/values.yaml
  ```

- Add `dra.net/nic` to the `coveredResources` of each ClusterQueue that admits Dranet jobs. Also add a `dra.net/nic` quota to each flavor of that resource group, in the same order as `coveredResources`. Otherwise, Kueue rejects the ClusterQueue. The flavor of the workers needs a quota of at least the number of RDMA NICs that the job claims. For an example, see the [Dranet NCCL test manifest](../manifests/nccl-tests/dranet/kueue/BM.GPU4.8.yaml).

Without Kueue, use an MPI Operator only test manifest:

- [manifests/nccl-tests/dranet/mpi-operator/BM.GPU4.8.yaml](https://github.com/oracle-quickstart/oci-hpc-oke/blob/main/manifests/nccl-tests/dranet/mpi-operator/BM.GPU4.8.yaml)
- [manifests/rccl-tests/dranet/mpi-operator/BM.GPU.MI300X.8.yaml](https://github.com/oracle-quickstart/oci-hpc-oke/blob/main/manifests/rccl-tests/dranet/mpi-operator/BM.GPU.MI300X.8.yaml)

## Run a test

To run the Dranet tests, see [NCCL Tests with Dranet](../manifests/nccl-tests/dranet/) and [RCCL Tests with Dranet](../manifests/rccl-tests/dranet/). For a claim example, see [Using Dranet for RDMA Network Interfaces](using-dranet.md).

## Uninstall

```sh
helm uninstall dranet --namespace kube-system
kubectl delete deviceclass dra.net
```

To return a node to the exclusive mode, write `options ib_core netns_mode=0` to `/etc/modprobe.d/ib_core.conf`, run `sudo update-initramfs -u`, and reboot the node.
