# NCCL Tests with SR-IOV Virtual Functions

Each pod gets one SR-IOV virtual function (VF) for each RDMA NIC. For the pod settings, see [Using SR-IOV Virtual Functions](../../../docs/using-rdma-network-interfaces-in-manifests.md#using-sr-iov-virtual-functions).

## Requirements

- MPI Operator. The stack installs it by default.
- Kueue, only for the `kueue/` manifests. The stack installs it by default.
- For the `kueue/` manifests, the `oci-rdma` Kueue Topology and the RDMA topology labels on the nodes. The stack creates both by default with a GPU RDMA or GPU Memory Cluster pool. Without the Topology, the ClusterQueue is inactive (`TopologyNotFound`) and the job waits. To create the Topology yourself, run `kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/terraform/files/kueue/topology.yaml`.
- The NVIDIA Network Operator with SR-IOV (`deploy_nvidia_network_operator = true`).

## Run the Test with Kueue

Run the command for your GPU shape.

### BM.GPU.B300.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/kueue/BM.GPU.B300.8.yaml
```

### BM.GPU.B200.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/kueue/BM.GPU.B200.8.yaml
```

### BM.GPU.H200.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/kueue/BM.GPU.H200.8.yaml
```

### BM.GPU.H100.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/kueue/BM.GPU.H100.8.yaml
```

### BM.GPU.A100-v2.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/kueue/BM.GPU.A100-v2.8.yaml
```

### BM.GPU4.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/kueue/BM.GPU4.8.yaml
```

### BM.GPU.B4.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/kueue/BM.GPU.B4.8.yaml
```

## Run the Test with MPI Operator Only

These manifests do not use Kueue. The pods start without queueing, so the cluster must have enough free GPUs for the job.

### BM.GPU.B300.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/mpi-operator/BM.GPU.B300.8.yaml
```

### BM.GPU.B200.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/mpi-operator/BM.GPU.B200.8.yaml
```

### BM.GPU.H200.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/mpi-operator/BM.GPU.H200.8.yaml
```

### BM.GPU.H100.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/mpi-operator/BM.GPU.H100.8.yaml
```

### BM.GPU.A100-v2.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/mpi-operator/BM.GPU.A100-v2.8.yaml
```

### BM.GPU4.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/mpi-operator/BM.GPU4.8.yaml
```

### BM.GPU.B4.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/virtual-functions/mpi-operator/BM.GPU.B4.8.yaml
```

For the container images and how to check the results, see [Running NCCL and RCCL Tests](../../../docs/running-nccl-rccl-tests.md).
