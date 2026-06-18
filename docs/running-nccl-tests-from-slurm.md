# Running NCCL Tests from Slurm Operator

This guide runs `nccl-tests` through the Slinky Slurm deployment. It is for
clusters where the Slurm GPU workers already mount `/dev/infiniband` and use a
GPU worker image that includes OpenMPI, NCCL, CUDA runtime libraries, and
`all_reduce_perf`.

The examples below were validated with a `BM.GPU.B4.8` Slurm GPU NodeSet using
two nodes and eight GPUs per node.

## Prerequisites

- Slinky Slurm is installed in the `slurm` namespace.
- The Slurm login pod, controller, accounting pod, and GPU worker pods are
  ready.
- At least two GPU Slurm nodes are idle in the `gpu` partition.
- A regular Slurm user exists and has a SlurmDBD association for the account
  used to submit the job. See
  [Slurm User Onboarding](./slurm-operator-user-onboarding.md).
- The GPU worker image contains `all_reduce_perf` at
  `/opt/nccl-tests/bin/all_reduce_perf` and libraries under
  `/opt/nccl-tests/lib`.

The default Slurm GPU worker image selected by the Terraform
`slinky_image_profile` includes NCCL test tooling for NVIDIA profiles.

## Set Variables

Run these commands from the operator host or another shell with `kubectl`
access to the cluster.

```bash
export PATH=/home/ubuntu/bin:$PATH
export OCI_CLI_AUTH=instance_principal

export SLURM_NAMESPACE=slurm
export LOGIN_CONTAINER=login
export WORKER_CONTAINER=slurmd

export SLURM_USER=alice
export SLURM_ACCOUNT=project-a
export SLURM_PARTITION=gpu

export NCCL_NODES=2
export GPUS_PER_NODE=8

export LOGIN_POD="$(
  kubectl -n "$SLURM_NAMESPACE" get pods \
    -l app.kubernetes.io/name=login \
    -o jsonpath='{.items[0].metadata.name}'
)"

export GPU_WORKER_POD="$(
  kubectl -n "$SLURM_NAMESPACE" get pods \
    -l app.kubernetes.io/instance=slurm-worker-gpu \
    -o jsonpath='{.items[0].metadata.name}'
)"
```

## Validate Slurm and the Worker Image

Check that Slurm sees the GPU nodes and that they advertise GPU GRES:

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  sinfo -Nel

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  scontrol show partition "$SLURM_PARTITION"
```

Check that the worker image has the NCCL test binary, CUDA/NCCL libraries, and
the RDMA device mount:

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$GPU_WORKER_POD" -c "$WORKER_CONTAINER" -- \
  bash -lc '
    command -v mpirun
    command -v nvidia-smi
    nvidia-smi -L
    ls -ld /dev/infiniband
    ls -l /opt/nccl-tests/bin/all_reduce_perf
    ls -l /opt/nccl-tests/lib/libcudart.so* /opt/nccl-tests/lib/libnccl.so*
  '
```

Check the Slurm user association:

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  sacctmgr -nP show user "$SLURM_USER" format=User,DefaultAccount,AdminLevel
```

## Optional One-GPU Smoke Test

Run a small single-rank job before the full multi-node test. This proves Slurm
can allocate a GPU and that the NCCL binary starts with the right library path.

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  su - "$SLURM_USER" -c \
    "sbatch --wait --parsable \
      --account=${SLURM_ACCOUNT} \
      --partition=${SLURM_PARTITION} \
      --nodes=1 \
      --ntasks=1 \
      --gres=gpu:1 \
      --time=00:05:00 \
      --job-name=nccl-smoke \
      --output=\$HOME/nccl-smoke-%j.out \
      --wrap='export LD_LIBRARY_PATH=/opt/nccl-tests/lib:\${LD_LIBRARY_PATH:-}; export NCCL_DEBUG=WARN; mpirun -np 1 /opt/nccl-tests/bin/all_reduce_perf -b 8M -e 8M -f 2 -g 1 -n 1 -w 1'"
```

## Create the Slurm Batch Script

The following script uses Slurm for allocation and OpenMPI `mpirun` for rank
launch inside that allocation. Do not run the MPI-enabled `all_reduce_perf`
directly with `srun` unless your image's OpenMPI build is known to support the
cluster's Slurm PMI/PMIx setup.

The `NCCL_IB_HCA` value below is for `BM.GPU.B4.8` and
`BM.GPU.A100-v2.8`. For another GPU shape, copy the NCCL HCA list and NCCL
shape tuning from the matching manifest in
[`manifests/nccl-tests/kueue/`](../manifests/nccl-tests/kueue/).

```bash
kubectl -n "$SLURM_NAMESPACE" exec -i "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  su - "$SLURM_USER" -c 'cat > "$HOME/nccl-slurm.sh" && chmod 755 "$HOME/nccl-slurm.sh"' <<'EOF'
#!/bin/bash
#SBATCH --job-name=nccl-slurm
#SBATCH --time=00:20:00
#SBATCH --output=%x-%j.out
#SBATCH --error=%x-%j.err

set -euxo pipefail

: "${GPUS_PER_NODE:=8}"

export PATH=/opt/nccl-tests/bin:${PATH}
export LD_LIBRARY_PATH=/opt/nccl-tests/lib:${LD_LIBRARY_PATH:-}

export NCCL_DEBUG=WARN
export NCCL_IB_SPLIT_DATA_ON_QPS=0
export NCCL_IB_QPS_PER_CONNECTION=4
export NCCL_IB_GID_INDEX=3
export NCCL_IB_HCA=mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_14,mlx5_15,mlx5_16,mlx5_17,mlx5_9,mlx5_10,mlx5_11,mlx5_12
export NCCL_IB_TC=41
export NCCL_IB_SL=0
export NCCL_IB_TIMEOUT=22
export NCCL_SOCKET_IFNAME=eth0

export HCOLL_ENABLE_MCAST_ALL=0
export UCX_TLS=tcp
export UCX_NET_DEVICES=eth0
export OMPI_MCA_coll_hcoll_enable=0

echo "date=$(date -Is)"
echo "SLURM_JOB_ID=${SLURM_JOB_ID}"
echo "SLURM_JOB_NODELIST=${SLURM_JOB_NODELIST}"
echo "SLURM_NTASKS=${SLURM_NTASKS}"
scontrol show hostnames "${SLURM_JOB_NODELIST}"
which mpirun
which all_reduce_perf
nvidia-smi -L

mpirun \
  -np "${SLURM_NTASKS}" \
  -npernode "${GPUS_PER_NODE}" \
  --bind-to numa \
  --mca btl_tcp_if_include eth0 \
  --mca coll ^hcoll \
  -x PATH \
  -x LD_LIBRARY_PATH \
  -x NCCL_DEBUG \
  -x NCCL_IB_SPLIT_DATA_ON_QPS \
  -x NCCL_IB_QPS_PER_CONNECTION \
  -x NCCL_IB_GID_INDEX \
  -x NCCL_IB_HCA \
  -x NCCL_IB_TC \
  -x NCCL_IB_SL \
  -x NCCL_IB_TIMEOUT \
  -x NCCL_SOCKET_IFNAME \
  -x HCOLL_ENABLE_MCAST_ALL \
  -x UCX_TLS \
  -x UCX_NET_DEVICES \
  -x OMPI_MCA_coll_hcoll_enable \
  all_reduce_perf -b 1G -f 2 -g 1 -e 4G -c 1
EOF
```

## Submit the Job

Submit the job as the Slurm user:

```bash
export NCCL_JOB_ID="$(
  kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
    su - "$SLURM_USER" -c \
      "sbatch --parsable \
        --account=${SLURM_ACCOUNT} \
        --partition=${SLURM_PARTITION} \
        --nodes=${NCCL_NODES} \
        --ntasks-per-node=${GPUS_PER_NODE} \
        --gres=gpu:${GPUS_PER_NODE} \
        --exclusive \
        --export=ALL,GPUS_PER_NODE=${GPUS_PER_NODE} \
        \$HOME/nccl-slurm.sh"
)"

echo "$NCCL_JOB_ID"
```

Watch the job and inspect the logs:

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  squeue -j "$NCCL_JOB_ID" -o "%.18i %.9P %.24j %.8u %.2t %.10M %.6D %R"

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  sacct -j "$NCCL_JOB_ID" \
    --format=JobID,JobName,Partition,Account,AllocNodes,State,ExitCode -P

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  su - "$SLURM_USER" -c \
    "tail -n 120 \$HOME/nccl-slurm-${NCCL_JOB_ID}.out; tail -n 120 \$HOME/nccl-slurm-${NCCL_JOB_ID}.err"
```

A successful job ends with `COMPLETED` and `ExitCode` `0:0`.

## Example Output

This is representative output from a two-node `BM.GPU.B4.8` run with 16 ranks:

```text
SLURM_JOB_NODELIST=inst-qfvws-oke-rdma,inst-wm4sq-oke-rdma
SLURM_NTASKS=16
# nccl-tests version 2.17.9 nccl-headers=22903 nccl-library=22903
# Collective test starting: all_reduce_perf
# nThread 1 nGpus 1 minBytes 1073741824 maxBytes 4294967296 step: 2(factor) warmup iters: 1 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid    490 on inst-qfvws-oke-rdma device  0 [0000:0f:00] NVIDIA A100-SXM4-40GB
#  Rank  7 Group  0 Pid    505 on inst-qfvws-oke-rdma device  7 [0000:da:00] NVIDIA A100-SXM4-40GB
#  Rank  8 Group  0 Pid    247 on inst-wm4sq-oke-rdma device  0 [0000:0f:00] NVIDIA A100-SXM4-40GB
#  Rank 15 Group  0 Pid    263 on inst-wm4sq-oke-rdma device  7 [0000:da:00] NVIDIA A100-SXM4-40GB
NCCL version 2.29.3+cuda13.1
#
#       size         count      type   redop    root     time   algbw   busbw  #wrong     time   algbw   busbw  #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)             (us)  (GB/s)  (GB/s)
  1073741824     268435456     float     sum      -1  10908.0   98.44  184.57       0  11220.1   95.70  179.43       0
  2147483648     536870912     float     sum      -1  21500.1   99.88  187.28       0  21629.9   99.28  186.16       0
  4294967296    1073741824     float     sum      -1  42721.7  100.53  188.50       0  42920.8  100.07  187.63       0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 185.594
#
# Collective test concluded: all_reduce_perf
```

## Troubleshooting

If `all_reduce_perf` fails with `libcudart.so` or `libnccl.so` not found, make
sure the job exports:

```bash
export LD_LIBRARY_PATH=/opt/nccl-tests/lib:${LD_LIBRARY_PATH:-}
```

If direct `srun all_reduce_perf` fails during `MPI_Init` with an OpenMPI PMI or
PMIx error, submit a Slurm allocation with `sbatch` and launch ranks with
`mpirun` as shown above.

If the job remains pending, check GPU node availability and GRES:

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  sinfo -Nel

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  scontrol show partition "$SLURM_PARTITION"
```

If bandwidth is much lower than expected, verify:

- GPU worker pods are on the RDMA-enabled node pool.
- GPU worker pods mount `/dev/infiniband`.
- The Slurm worker NodeSet uses `hostNetwork` for RDMA-capable NVIDIA workers.
- `NCCL_IB_HCA` matches the OCI GPU shape.
- `NCCL_SOCKET_IFNAME` and the OpenMPI TCP interface match the worker network
  interface used by the Slurm pods.
