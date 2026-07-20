# Running NCCL and RCCL Tests with Kueue and MPI Operator

Kueue and MPI Operator are required for running the optional NCCL/RCCL tests.

> [!NOTE]
> Starting with stack v26.3.0, Kueue and MPI Operator are deployed by default.

## Deploy MPI Operator and Kueue

```sh
kubectl apply --server-side -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/mpi-operator/mpi-operator.yaml

helm install kueue oci://registry.k8s.io/kueue/charts/kueue --version="0.18.2" --create-namespace --namespace=kueue-system
```

## Run the NCCL/RCCL Tests

> [!IMPORTANT]
> NCCL/RCCL parameters vary by GPU shape. Make sure you are using the manifest that matches your specific bare metal GPU shape.
>
> Also verify that the CUDA major version in the container image matches the CUDA major version installed on the node.

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

### BM.GPU.GB300.4
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.GB300.4.yaml
```

### BM.GPU.GB200-v3.4
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.GB200-v3.4.yaml
```

### BM.GPU.GB200-v2.4
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.GB200-v2.4.yaml
```

### BM.GPU.GB200.4
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.GB200.4.yaml
```

### BM.GPU.B200.8
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.B200.8.yaml
```

### BM.GPU.H200
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.H200.8.yaml
```

### BM.GPU.H100
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.H100.8.yaml
```

### BM.GPU.A100-v2.8
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.A100-v2.8.yaml
```

### BM.GPU4.8
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU4.8.yaml
```

### BM.GPU.B4.8
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/nccl-tests/kueue/BM.GPU.B4.8.yaml
```

### BM.GPU.MI355X-v1.8
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/rccl-tests/kueue/BM.GPU.MI355X-v1.8.yaml
```

### BM.GPU.MI355X.8
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/rccl-tests/kueue/BM.GPU.MI355X.8.yaml
```

### BM.GPU.MI300X.8
```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/rccl-tests/kueue/BM.GPU.MI300X.8.yaml
```

The initial container image pull may take some time. Once the launcher pod `nccl-test-launcher-XXXXX` starts running, you can check its logs for the NCCL test results.

## Check the Results

Follow the launcher pod logs until the test completes:

```sh
kubectl logs -f <launcher-pod>
```

A successful run reports `#wrong` as `0`. When reporting bandwidth, run the test through 8 GiB and use the `8589934592`-byte row. Do not use the average bandwidth line. If a manifest stops below 8 GiB, change the test command's `-e` argument to `8G` and rerun it before reporting a result.
