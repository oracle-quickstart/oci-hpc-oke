# Running NCCL and RCCL Tests with Kueue and MPI Operator

Kueue and MPI Operator are required for running the optional NCCL/RCCL tests.

> [!NOTE]
> Starting with stack v26.3.0, Kueue and MPI Operator are deployed by default.

## Deploy MPI Operator and Kueue

```sh
kubectl apply --server-side -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/manifests/mpi-operator/mpi-operator.yaml

helm install kueue oci://registry.k8s.io/kueue/charts/kueue --version="0.17.2" --create-namespace --namespace=kueue-system
```

## Run the NCCL/RCCL Tests

> [!IMPORTANT]  
> NCCL/RCCL parameters vary by GPU shape. Make sure you are using the manifest that matches your specific bare metal GPU shape.
>
> Also verify that the CUDA major version in the container image matches the CUDA major version installed on the node.

### NCCL Tests
| Image Tag                                                                 | CUDA   |
|---------------------------------------------------------------------------|--------|
| iad.ocir.io/idxzjcdglx2s/nccl-tests:cuda-13.1.1-ubuntu-24.04-nccl-2.29.3-020926.1 | 13.1.1 |
| iad.ocir.io/idxzjcdglx2s/nccl-tests:cuda-12.9.1-ubuntu-24.04-nccl-2.29.3-020926.1 | 12.9.1 |

### RCCL Tests
| Image Tag                                                                 | ROCM   |
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

## Example Output

```sh
Waiting for workers to be ready...
All workers are ready!
Warning: Permanently added '[nccl-test-worker-1.nccl-test.default.svc]:2222' (ED25519) to the list of known hosts.
Warning: Permanently added '[nccl-test-worker-0.nccl-test.default.svc]:2222' (ED25519) to the list of known hosts.
# nThread 1 nGpus 1 minBytes 1073741824 maxBytes 4294967296 step: 2(factor) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid     88 on inst-fufd1-oke-rdma device  0 [0000:0f:00] NVIDIA A100-SXM4-40GB
#  Rank  1 Group  0 Pid     89 on inst-fufd1-oke-rdma device  1 [0000:15:00] NVIDIA A100-SXM4-40GB
#  Rank  2 Group  0 Pid     90 on inst-fufd1-oke-rdma device  2 [0000:51:00] NVIDIA A100-SXM4-40GB
#  Rank  3 Group  0 Pid     91 on inst-fufd1-oke-rdma device  3 [0000:54:00] NVIDIA A100-SXM4-40GB
#  Rank  4 Group  0 Pid     92 on inst-fufd1-oke-rdma device  4 [0000:8d:00] NVIDIA A100-SXM4-40GB
#  Rank  5 Group  0 Pid     93 on inst-fufd1-oke-rdma device  5 [0000:92:00] NVIDIA A100-SXM4-40GB
#  Rank  6 Group  0 Pid     94 on inst-fufd1-oke-rdma device  6 [0000:d6:00] NVIDIA A100-SXM4-40GB
#  Rank  7 Group  0 Pid     95 on inst-fufd1-oke-rdma device  7 [0000:da:00] NVIDIA A100-SXM4-40GB
#  Rank  8 Group  0 Pid     88 on inst-aqu5j-oke-rdma device  0 [0000:0f:00] NVIDIA A100-SXM4-40GB
#  Rank  9 Group  0 Pid     89 on inst-aqu5j-oke-rdma device  1 [0000:15:00] NVIDIA A100-SXM4-40GB
#  Rank 10 Group  0 Pid     90 on inst-aqu5j-oke-rdma device  2 [0000:51:00] NVIDIA A100-SXM4-40GB
#  Rank 11 Group  0 Pid     91 on inst-aqu5j-oke-rdma device  3 [0000:54:00] NVIDIA A100-SXM4-40GB
#  Rank 12 Group  0 Pid     92 on inst-aqu5j-oke-rdma device  4 [0000:8d:00] NVIDIA A100-SXM4-40GB
#  Rank 13 Group  0 Pid     93 on inst-aqu5j-oke-rdma device  5 [0000:92:00] NVIDIA A100-SXM4-40GB
#  Rank 14 Group  0 Pid     94 on inst-aqu5j-oke-rdma device  6 [0000:d6:00] NVIDIA A100-SXM4-40GB
#  Rank 15 Group  0 Pid     96 on inst-aqu5j-oke-rdma device  7 [0000:da:00] NVIDIA A100-SXM4-40GB
NCCL version 2.25.1+cuda12.8
#
#                                                              out-of-place                       in-place          
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)       
  1073741824     268435456     float     sum      -1    10776   99.64  186.83      0    10781   99.60  186.75      0
  2147483648     536870912     float     sum      -1    21287  100.88  189.15      0    21299  100.82  189.05      0
  4294967296    1073741824     float     sum      -1    42381  101.34  190.02      0    42364  101.38  190.09      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 188.648 
#
```
