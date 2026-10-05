# Running NCCL and RCCL Tests

MPI Operator is required for running the optional NCCL/RCCL tests. Kueue is optional. Each network type folder has a `kueue/` version of every manifest, which runs through Kueue, and an `mpi-operator/` version, which needs only MPI Operator.

The `kueue/` manifests use topology-aware scheduling (TAS) with the `oci-rdma` Topology that the stack creates. Kueue places the workers in the same RDMA local block when it can.

> [!NOTE]
> Starting with stack v26.3.0, Kueue and MPI Operator are deployed by default.

## Deploy MPI Operator and Kueue

```sh
kubectl apply --server-side -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/mpi-operator/mpi-operator.yaml

helm install kueue oci://registry.k8s.io/kueue/charts/kueue --version="0.20.0" --create-namespace --namespace=kueue-system \
  -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/terraform/files/kueue/values.yaml
```

> [!IMPORTANT]
> Kueue v0.20 no longer serves the `kueue.x-k8s.io/v1beta1` API. Before you upgrade an existing Kueue installation, check the stored versions of the Kueue CRDs:
>
> ```sh
> kubectl get crd -o custom-columns=NAME:.metadata.name,STORED:.status.storedVersions | grep kueue.x-k8s.io
> ```
>
> If a CRD lists `v1beta1`, run the Kueue [migration script](https://raw.githubusercontent.com/kubernetes-sigs/kueue/v0.20.0/hack/migrate-to-v1beta2.sh) before you upgrade.

## Run the NCCL/RCCL Tests

> [!IMPORTANT]
> NCCL/RCCL parameters vary by GPU shape. Make sure you are using the manifest that matches your specific bare metal GPU shape.
>
> Also verify that the CUDA major version in the container image matches the CUDA major version installed on the node.

Choose the manifests that match how the pods get the RDMA NICs. Each folder has a README with one command per shape, for the `kueue/` and the `mpi-operator/` versions.

| Network type | The pods use | Requirement | NCCL | RCCL |
|---|---|---|---|---|
| Host network | The RDMA NICs of the host | None | [host-network](../manifests/nccl-tests/host-network/) | [host-network](../manifests/rccl-tests/host-network/) |
| SR-IOV virtual functions | One VF for each RDMA NIC | `deploy_nvidia_network_operator = true` | [virtual-functions](../manifests/nccl-tests/virtual-functions/) | [virtual-functions](../manifests/rccl-tests/virtual-functions/) |

### NCCL Tests
| Image Tag                                                                 | CUDA   |
|---------------------------------------------------------------------------|--------|
| iad.ocir.io/idxzjcdglx2s/nccl-tests:cuda-13.3.0-ubuntu-24.04-nccl-2.30.4-071626.0 | 13.3.0 |
| iad.ocir.io/idxzjcdglx2s/nccl-tests:cuda-12.9.1-ubuntu-24.04-nccl-2.29.3-020926.1 | 12.9.1 |

### RCCL Tests
| Image Tag                                                                 | ROCm   |
|---------------------------------------------------------------------------|--------|
| iad.ocir.io/idxzjcdglx2s/rccl-tests:rocm-7.1.1-ubuntu22.04-rccl-2.27.7-012126.1 | 7.1.1 |
| iad.ocir.io/idxzjcdglx2s/rccl-tests:rocm-6.4.4-ubuntu22.04-rccl-2.22.3-011826.1 | 6.4.4 |

The initial container image pull may take some time. Once the launcher pod `nccl-test-launcher-XXXXX` starts running, you can check its logs for the NCCL test results.

Kueue v0.19 and later evict and requeue a job when its pods are not all ready within 30 minutes (`waitForPodsReady`).

## Check the Results

Follow the launcher pod logs until the test completes:

```sh
kubectl logs -f <launcher-pod>
```

A successful run reports `#wrong` as `0`. When reporting bandwidth, run the test through 8 GiB and use the `8589934592`-byte row. Do not use the average bandwidth line. If a manifest stops below 8 GiB, change the test command's `-e` argument to `8G` and rerun it before reporting a result.
