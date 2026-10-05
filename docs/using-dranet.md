# Using Dranet for RDMA Network Interfaces (Preview)

> [!NOTE]
> This is a preview feature. Do not use it for production workloads.

[Dranet](https://github.com/kubernetes-sigs/dranet) is a Kubernetes network driver that uses Dynamic Resource Allocation (DRA). On OKE, a pod claims an RDMA NIC of the node. Dranet gives the pod an IPvlan child of the RDMA NIC with its own address. The RDMA NIC stays on the host.

## What the stack installs

Set `install_dranet = true`. In Resource Manager, the option is in the **Preview Features** section.

To install Dranet on a cluster that the stack did not create, see [Installing Dranet Manually on OKE](installing-dranet-manually.md).

The stack then:

- Installs the Dranet Helm chart (`dranet_chart_version`, default `v1.5.0`) in the `kube-system` namespace, with `args.moveIBInterfaces=false`. Native InfiniBand NICs stay on the host for the OKE health checks.
- Creates the DeviceClass `dra.net`.
- Sets the RDMA subsystem to shared network namespace mode on worker nodes with RDMA NICs. A step (`files/rdma/rdma-netns.sh shared`) runs before the OKE bootstrap. It writes `options ib_core netns_mode=1` to `/etc/modprobe.d/ib_core.conf`, updates the initramfs, and runs `rdma system set netns shared`. The switch fails while any other network namespace exists, so the step retries it for up to 90 seconds. If it still fails, the node uses shared mode after its next reboot. Dranet claims fail in exclusive mode.

The setting applies to nodes created after you enable the option. Replace existing nodes to apply it to them.

## Requirements

- A single-stack IPv4 cluster (`enable_ipv6 = false`). Dranet does not support IPv6 yet.
- The exception is a GPU Memory Cluster pool with the `BM.GPU.GB200.4` shape, which uses native InfiniBand.
- No NVIDIA Network Operator (`deploy_nvidia_network_operator = false`). Its SR-IOV VFs need exclusive RDMA network namespace mode, which the stack sets when the Network Operator is enabled.

## Claim an RDMA NIC

The RDMA NIC names depend on the shape. Most GPU shapes use `rdma0`, `rdma1`, and so on. BM.Optimized3.36 keeps the OS name `ens800f0np0`. On such a shape, create claims only after Oracle Cloud Agent assigns the RDMA address. A claim prepared earlier moves the RDMA NIC into the pod.

```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: rdma0
spec:
  devices:
    requests:
    - name: rdma
      exactly:
        deviceClassName: dra.net
        selectors:
        - cel:
            expression: has(device.attributes["dra.net"].ifName) && device.attributes["dra.net"].ifName == "rdma0"
---
apiVersion: v1
kind: Pod
metadata:
  name: rdma-test
spec:
  resourceClaims:
  - name: rdma
    resourceClaimName: rdma0
  containers:
  - name: test
    image: ubuntu:24.04
    command: ["sleep", "infinity"]
    securityContext:
      capabilities:
        add: ["IPC_LOCK"]
    resources:
      claims:
      - name: rdma
```

The child gets an address in `10.208.0.0/12` by default. Do not set `NCCL_IB_GID_INDEX` for jobs that use the children, because NCCL selects the GID index itself.

## Run the NCCL and RCCL Tests

The Dranet tests run `all_reduce_perf` through Kueue (`kueue/`) or with MPI Operator only (`mpi-operator/`). Each worker claims all RDMA NICs of its node.

- The [Dranet NCCL test](../manifests/nccl-tests/dranet/) runs on BM.GPU4.8 nodes, with 16 RDMA NICs for each worker.
- The [Dranet RCCL test](../manifests/rccl-tests/dranet/) runs on BM.GPU.MI300X.8 nodes, with 8 RDMA NICs for each worker.

Kueue does not check before admission that a node has free RDMA NICs. That check (`KueueDRADeviceFeasibility`) is an alpha feature and is off. If another pod holds the RDMA NICs of a node, the worker on that node stays `Pending`. Kueue evicts and requeues the job when its pods are not ready within 30 minutes (`waitForPodsReady`).

For the child range, the published attributes, and the InfiniBand settings, see the [Dranet OKE documentation](https://github.com/kubernetes-sigs/dranet/blob/v1.5.0/site/content/docs/user/oci-oke-rdma.md).
