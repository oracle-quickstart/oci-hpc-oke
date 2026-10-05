# NCCL Tests with Dranet (Preview)

The pods use the pod network. Each worker claims the RDMA NICs of its node through Dranet and gets an IPvlan child of each NIC. For details, see [Using Dranet for RDMA Network Interfaces](../../../docs/using-dranet.md).

## Requirements

- MPI Operator. The stack installs it by default.
- Kueue, only for the `kueue/` manifest. The stack installs it by default.
- For the `kueue/` manifest, the `oci-rdma` Kueue Topology and the RDMA topology labels on the nodes. The stack creates both by default with a GPU RDMA or GPU Memory Cluster pool. Without the Topology, the ClusterQueue is inactive (`TopologyNotFound`) and the job waits. To create the Topology yourself, run `kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/terraform/files/kueue/topology.yaml`.
- Dranet (`install_dranet = true`) on a single-stack IPv4 cluster.
- For the `kueue/` manifest, Kueue maps the `dra.net` DeviceClass to the `dra.net/nic` resource. The stack sets this mapping.

## Run the Test with Kueue

### BM.GPU4.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/dranet/kueue/BM.GPU4.8.yaml
```

## Run the Test with MPI Operator Only

This manifest does not use Kueue. The pods start without queueing, so the cluster must have enough free GPUs for the job.

### BM.GPU4.8

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/dranet/mpi-operator/BM.GPU4.8.yaml
```

For the container images and how to check the results, see [Running NCCL and RCCL Tests](../../../docs/running-nccl-rccl-tests.md).
