# Running NCCL and RCCL Tests from Slurm Operator

This guide runs GPU collective bandwidth tests through the Slinky Slurm
deployment:

- **NCCL tests** on **NVIDIA** GPU workers, using `nccl-tests`
  (`all_reduce_perf` built against CUDA/NCCL).
- **RCCL tests** on **AMD ROCm** GPU workers, using `rccl-tests`
  (`all_reduce_perf` built against ROCm/RCCL).

Both submit a multi-node `all_reduce_perf` job over RDMA and report the bus
bandwidth. Go to the [NCCL Tests](#nccl-tests-nvidia-gpu-shapes) section for
NVIDIA workers or the [RCCL Tests](#rccl-tests-amd-gpu-shapes) section for AMD
workers.

The examples below were validated on live clusters:

- NCCL on a `BM.GPU.B4.8` Slurm GPU NodeSet (two nodes, eight GPUs per node).
- RCCL on a `BM.GPU.MI300X.8` Slurm GPU NodeSet (two nodes, eight GPUs per node).

You can run either test in two ways:

- **From the operator node**, using `kubectl` to exec Slurm commands inside the
  login pod. Use this when you only have `kubectl` access to the cluster.
  Commands that act as the Slurm user are wrapped in `su - "$SLURM_USER" -c`.
- **From the login pod**, where the Slurm client binaries are on `PATH` and you
  run `sinfo`, `sbatch`, and friends directly. Use this for an interactive
  workflow once you are shelled into the pod.

Both methods submit the same job and produce the same result. Each step below
shows both forms; pick one.

## Contents

- [Prerequisites](#prerequisites)
- [NCCL Tests (NVIDIA GPU shapes)](#nccl-tests-nvidia-gpu-shapes)
  - [Set Variables](#set-variables)
  - [Validate Slurm and the Worker Image](#validate-slurm-and-the-worker-image)
  - [Optional One-GPU Smoke Test (nvidia-smi)](#optional-one-gpu-smoke-test-nvidia-smi)
  - [Create the Slurm Batch Script](#create-the-slurm-batch-script)
  - [Submit the Job](#submit-the-job)
  - [Example Output](#example-output)
  - [Running via Pyxis (containerized)](#running-via-pyxis-containerized)
- [RCCL Tests (AMD GPU shapes)](#rccl-tests-amd-gpu-shapes)
  - [Set Variables](#set-variables-1)
  - [Validate Slurm and the Worker Image](#validate-slurm-and-the-worker-image-1)
  - [Optional One-GPU Smoke Test (rocm-smi)](#optional-one-gpu-smoke-test-rocm-smi)
  - [Create the Slurm Batch Script](#create-the-slurm-batch-script-1)
  - [Submit the Job](#submit-the-job-1)
  - [Example Output](#example-output-1)
  - [Running via Pyxis (containerized)](#running-via-pyxis-containerized-1)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Slinky Slurm is installed in the `slurm` namespace.
- The Slurm login pod, controller, accounting pod, and GPU worker pods are
  ready.
- At least two GPU Slurm nodes are idle in the `gpu` partition.
- A regular Slurm user exists and has a SlurmDBD association for the account
  used to submit the job. See
  [Slurm User Onboarding](./slurm-operator-user-onboarding.md).
- The GPU worker image contains the test binaries that match the GPU vendor:
  - **NVIDIA**: `all_reduce_perf` at `/opt/nccl-tests/bin/all_reduce_perf` and
    libraries under `/opt/nccl-tests/lib`.
  - **AMD**: `all_reduce_perf` at `/opt/oci-hpc/rccl-tests/bin/all_reduce_perf`
    (also on `PATH` via `/usr/local/bin`), with the environment helper
    `/opt/oci-hpc/rccl-tests/env.sh`.

The default Slurm GPU worker image selected by the Terraform
`slinky_image_profile` includes `nccl-tests` for NVIDIA profiles and
`rccl-tests` for AMD ROCm profiles.

To open a shell in the login pod (for the login-pod form of either section),
get the external (load balancer) IP of the login service and SSH in as your
Slurm user:

```bash
kubectl -n slurm get svc slurm-login-slinky \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

ssh <user>@<login-pod-external-ip>
```

If you do not have a user account in the login pod yet, create one by following
[Slurm User Onboarding](./slurm-operator-user-onboarding.md).

The examples below match the onboarding quick start: user `alice` in the default
Slurm account `users`. If you passed `--account <name>` to
`slurm-add-user.sh`, or used a different `PROJECT` in the manual onboarding
steps, set `SLURM_ACCOUNT` to that account instead.

## NCCL Tests (NVIDIA GPU shapes)

This section uses the NVIDIA GPU worker image, which ships `all_reduce_perf`
under `/opt/nccl-tests/bin` and OpenMPI for rank launch.

### Set Variables

From the operator host or another shell with `kubectl` access:

```bash
export PATH=/home/ubuntu/bin:$PATH
export OCI_CLI_AUTH=instance_principal

export SLURM_NAMESPACE=slurm
export LOGIN_CONTAINER=login
export WORKER_CONTAINER=slurmd

export SLURM_USER=alice
export SLURM_ACCOUNT=users
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

From inside the login pod you only need the job parameters:

```bash
export SLURM_ACCOUNT=users
export SLURM_PARTITION=gpu

export NCCL_NODES=2
export GPUS_PER_NODE=8
```

### Validate Slurm and the Worker Image

Check that Slurm sees the GPU nodes and that they advertise GPU GRES.

From the operator node:

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  sinfo -Nel

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  scontrol show partition "$SLURM_PARTITION"
```

From inside the login pod:

```bash
sinfo -Nel
scontrol show partition "$SLURM_PARTITION"
sacctmgr -nP show user "$(whoami)" format=User,DefaultAccount,AdminLevel
```

Check that the worker image has the NCCL test binary, CUDA/NCCL libraries, and
the RDMA device mount (this is a pod-level check that needs `kubectl` access to
the worker pod, so run it from the operator node):

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$GPU_WORKER_POD" -c "$WORKER_CONTAINER" -- \
  bash -lc '
    command -v mpirun
    command -v nvidia-smi
    command -v jq
    nvidia-smi -L
    ls -ld /dev/infiniband
    ls -l /opt/nccl-tests/bin/all_reduce_perf
    ls -l /opt/nccl-tests/env.sh
    ls -l /opt/nccl-tests/lib/libcudart.so* /opt/nccl-tests/lib/libnccl.so*
  '
```

Check the Slurm user association from the operator node:

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  sacctmgr -nP show user "$SLURM_USER" format=User,DefaultAccount,AdminLevel
```

### Optional One-GPU Smoke Test (nvidia-smi)

Run a small single-rank job before the full multi-node test. This proves Slurm
can allocate a GPU and that the GPU is visible to the job.

`sbatch --parsable` prints only the job ID; the test output is written to the
`--output` file, not the terminal. Capture the job ID so you can read it back.

From the operator node:

```bash
export SMOKE_JOB_ID="$(
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
        --wrap='nvidia-smi'"
)"

echo "$SMOKE_JOB_ID"

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  sacct -j "$SMOKE_JOB_ID" \
    --format=JobID,JobName,Partition,Account,State,ExitCode -P

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  su - "$SLURM_USER" -c "cat \$HOME/nccl-smoke-${SMOKE_JOB_ID}.out"
```

From inside the login pod:

```bash
SMOKE_JOB_ID="$(sbatch --wait --parsable \
  --account="${SLURM_ACCOUNT}" \
  --partition="${SLURM_PARTITION}" \
  --nodes=1 \
  --ntasks=1 \
  --gres=gpu:1 \
  --time=00:05:00 \
  --job-name=nccl-smoke \
  --output="$HOME/nccl-smoke-%j.out" \
  --wrap='nvidia-smi')"

echo "$SMOKE_JOB_ID"

sacct -j "$SMOKE_JOB_ID" \
  --format=JobID,JobName,Partition,Account,State,ExitCode -P
cat "$HOME/nccl-smoke-${SMOKE_JOB_ID}.out"
```

The job should be `COMPLETED` with `ExitCode` `0:0`, and the output should be the
`nvidia-smi` table listing the allocated GPU.

### Create the Slurm Batch Script

The following script uses Slurm for allocation and OpenMPI `mpirun` for rank
launch inside that allocation. Do not run the MPI-enabled `all_reduce_perf`
directly with `srun` unless your image's OpenMPI build is known to support the
cluster's Slurm PMI/PMIx setup.

The script sources `/opt/nccl-tests/env.sh` for the NCCL, HPCX (OpenMPI/UCX),
and nccl-tests paths, then detects the OCI GPU shape and applies the matching
`NCCL_IB_HCA` / `UCX_NET_DEVICES` tuning. It covers `BM.GPU.B4.8`,
`BM.GPU.A100-v2.8`, `BM.GPU4.8`, `BM.GPU.H100.8`, `BM.GPU.H200.8`,
`BM.GPU.B200.8`, and `BM.GPU.B300.8`, with two `mpirun` profiles: an A100-class
profile (B4.8 / A100-v2.8 / GPU4.8) and an H100-and-newer profile
(H100 / H200 / B200 / B300). The HCA lists match the per-shape manifests in
[`manifests/nccl-tests/kueue/`](../manifests/nccl-tests/kueue/); add a `case`
arm there to support another shape.

Shape detection reads the OCI instance metadata service at `169.254.169.254`.
The GPU worker pods run with `hostNetwork`, so IMDS is reachable, and `jq` ships
in the worker image.

Set `EXEC=all_gather_perf` (or another `*_perf` binary) in the job environment
to run a different collective; it defaults to `all_reduce_perf`.

The script body is the same for both run methods. From the operator node, write
it with `kubectl exec ... su - "$SLURM_USER" -c 'cat > ...'`; from inside the
login pod, write it directly with a heredoc.

From the operator node:

```bash
kubectl -n "$SLURM_NAMESPACE" exec -i "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  su - "$SLURM_USER" -c 'cat > "$HOME/nccl-slurm.sh" && chmod 755 "$HOME/nccl-slurm.sh"' <<'EOF'
#!/bin/bash
#SBATCH --job-name=nccl-slurm
#SBATCH --time=00:20:00
#SBATCH --output=%x-%j.out
#SBATCH --error=%x-%j.err

set -uxo pipefail
: "${GPUS_PER_NODE:=8}"

# NCCL + HPCX (OpenMPI/UCX) + nccl-tests paths from the worker image
source /opt/nccl-tests/env.sh

# all_reduce_perf by default; override with EXEC=all_gather_perf (binaries in $NCCL_TEST_HOME/bin)
EXEC_CMD="${NCCL_TEST_HOME}/bin/${EXEC:-all_reduce_perf}"
[[ -x "${EXEC_CMD}" ]] || { echo "Test executable ${EXEC_CMD} not found!"; exit 1; }

# HPCX NCCL net plugin in the image (used by the H100/H200/B200/B300 profile)
HPCX_NET_PLUGIN=/opt/hpcx/nccl_rdma_sharp_plugin/lib/libnccl-net.so
[[ -f "${HPCX_NET_PLUGIN}" ]] || HPCX_NET_PLUGIN=none

export NCCL_DEBUG=WARN

# GPU worker pods use hostNetwork, so IMDS (169.254.169.254) is reachable and jq ships in the image.
shape="$(curl -sH "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/ | jq -r .shape)"
echo "shape=${shape}"

case "${shape}" in
  BM.GPU.B4.8|BM.GPU.A100-v2.8)
    var_UCX_NET_DEVICES=mlx5_0:1
    var_NCCL_IB_HCA="=mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_14,mlx5_15,mlx5_16,mlx5_17,mlx5_9,mlx5_10,mlx5_11,mlx5_12" ;;
  BM.GPU4.8)
    var_UCX_NET_DEVICES=mlx5_4:1
    var_NCCL_IB_HCA="=mlx5_0,mlx5_2,mlx5_6,mlx5_8,mlx5_10,mlx5_12,mlx5_14,mlx5_16,mlx5_1,mlx5_3,mlx5_7,mlx5_9,mlx5_11,mlx5_13,mlx5_15,mlx5_17" ;;
  BM.GPU.H100.8)
    var_UCX_NET_DEVICES=eth0
    var_NCCL_IB_HCA="=mlx5_0,mlx5_1,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_9,mlx5_10,mlx5_12,mlx5_13,mlx5_14,mlx5_15,mlx5_16,mlx5_17" ;;
  BM.GPU.H200.8|BM.GPU.B200.8)
    var_UCX_NET_DEVICES=eth0
    var_NCCL_IB_HCA="=mlx5_0,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_9,mlx5_10,mlx5_11" ;;
  BM.GPU.B300.8)
    var_UCX_NET_DEVICES=eth0
    var_NCCL_IB_HCA="=mlx5_0,mlx5_1,mlx5_7,mlx5_8,mlx5_9,mlx5_10,mlx5_11,mlx5_12,mlx5_13,mlx5_14,mlx5_16,mlx5_17,mlx5_18,mlx5_19,mlx5_20,mlx5_21" ;;
  *)
    echo "Unsupported shape ${shape}; set var_UCX_NET_DEVICES and var_NCCL_IB_HCA manually."; exit 1 ;;
esac

echo "date=$(date -Is)"
echo "SLURM_JOB_NODELIST=${SLURM_JOB_NODELIST}"
echo "SLURM_NTASKS=${SLURM_NTASKS}"
scontrol show hostnames "${SLURM_JOB_NODELIST}"
which mpirun
echo "EXEC_CMD=${EXEC_CMD}"

case "${shape}" in
  BM.GPU.B4.8|BM.GPU.A100-v2.8|BM.GPU4.8)
    mpirun --mca pml ucx \
      --bind-to numa \
      --mca coll ^hcoll \
      -np "${SLURM_NTASKS}" -npernode "${GPUS_PER_NODE}" \
      -x NCCL_DEBUG \
      -x NCCL_IB_SL=0 \
      -x NCCL_IB_TC=41 \
      -x NCCL_IB_QPS_PER_CONNECTION=4 \
      -x UCX_TLS=ud,self,sm \
      -x UCX_NET_DEVICES=${var_UCX_NET_DEVICES} \
      -x HCOLL_ENABLE_MCAST_ALL=0 \
      -x coll_hcoll_enable=0 \
      -x NCCL_IB_GID_INDEX=3 \
      -x NCCL_ALGO=Ring \
      -x NCCL_IB_HCA="${var_NCCL_IB_HCA}" \
      "${EXEC_CMD}" -b 1G -e 10G -i $((1024*1024*1024*9)) -n 100 ;;
  BM.GPU.H100.8|BM.GPU.H200.8|BM.GPU.B200.8|BM.GPU.B300.8)
    mpirun --mca pml ucx \
      --bind-to numa \
      --mca coll ^hcoll \
      -np "${SLURM_NTASKS}" -npernode "${GPUS_PER_NODE}" \
      -x NCCL_DEBUG \
      -x NCCL_CUMEM_ENABLE=0 \
      -x NCCL_IB_SPLIT_DATA_ON_QPS=0 \
      -x NCCL_IB_QPS_PER_CONNECTION=1 \
      -x NCCL_IB_GID_INDEX=3 \
      -x NCCL_IB_TC=41 \
      -x NCCL_IB_SL=0 \
      -x NCCL_IB_TIMEOUT=22 \
      -x NCCL_NET_PLUGIN=${HPCX_NET_PLUGIN} \
      -x HCOLL_ENABLE_MCAST_ALL=0 \
      -x coll_hcoll_enable=0 \
      -x UCX_TLS=tcp \
      -x UCX_NET_DEVICES=${var_UCX_NET_DEVICES} \
      -x RX_QUEUE_LEN=8192 \
      -x IB_RX_QUEUE_LEN=8192 \
      -x NCCL_SOCKET_IFNAME=${var_UCX_NET_DEVICES} \
      -x NCCL_IGNORE_CPU_AFFINITY=1 \
      -x NCCL_IB_HCA="${var_NCCL_IB_HCA}" \
      "${EXEC_CMD}" -b 1G -e 16G -f 2 -g 1 -n 50 ;;
esac
EOF
```

From inside the login pod:

```bash
cat > "$HOME/nccl-slurm.sh" <<'EOF'
#!/bin/bash
#SBATCH --job-name=nccl-slurm
#SBATCH --time=00:20:00
#SBATCH --output=%x-%j.out
#SBATCH --error=%x-%j.err

set -uxo pipefail
: "${GPUS_PER_NODE:=8}"

# NCCL + HPCX (OpenMPI/UCX) + nccl-tests paths from the worker image
source /opt/nccl-tests/env.sh

# all_reduce_perf by default; override with EXEC=all_gather_perf (binaries in $NCCL_TEST_HOME/bin)
EXEC_CMD="${NCCL_TEST_HOME}/bin/${EXEC:-all_reduce_perf}"
[[ -x "${EXEC_CMD}" ]] || { echo "Test executable ${EXEC_CMD} not found!"; exit 1; }

# HPCX NCCL net plugin in the image (used by the H100/H200/B200/B300 profile)
HPCX_NET_PLUGIN=/opt/hpcx/nccl_rdma_sharp_plugin/lib/libnccl-net.so
[[ -f "${HPCX_NET_PLUGIN}" ]] || HPCX_NET_PLUGIN=none

export NCCL_DEBUG=WARN

# GPU worker pods use hostNetwork, so IMDS (169.254.169.254) is reachable and jq ships in the image.
shape="$(curl -sH "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/ | jq -r .shape)"
echo "shape=${shape}"

case "${shape}" in
  BM.GPU.B4.8|BM.GPU.A100-v2.8)
    var_UCX_NET_DEVICES=mlx5_0:1
    var_NCCL_IB_HCA="=mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_14,mlx5_15,mlx5_16,mlx5_17,mlx5_9,mlx5_10,mlx5_11,mlx5_12" ;;
  BM.GPU4.8)
    var_UCX_NET_DEVICES=mlx5_4:1
    var_NCCL_IB_HCA="=mlx5_0,mlx5_2,mlx5_6,mlx5_8,mlx5_10,mlx5_12,mlx5_14,mlx5_16,mlx5_1,mlx5_3,mlx5_7,mlx5_9,mlx5_11,mlx5_13,mlx5_15,mlx5_17" ;;
  BM.GPU.H100.8)
    var_UCX_NET_DEVICES=eth0
    var_NCCL_IB_HCA="=mlx5_0,mlx5_1,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_9,mlx5_10,mlx5_12,mlx5_13,mlx5_14,mlx5_15,mlx5_16,mlx5_17" ;;
  BM.GPU.H200.8|BM.GPU.B200.8)
    var_UCX_NET_DEVICES=eth0
    var_NCCL_IB_HCA="=mlx5_0,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_9,mlx5_10,mlx5_11" ;;
  BM.GPU.B300.8)
    var_UCX_NET_DEVICES=eth0
    var_NCCL_IB_HCA="=mlx5_0,mlx5_1,mlx5_7,mlx5_8,mlx5_9,mlx5_10,mlx5_11,mlx5_12,mlx5_13,mlx5_14,mlx5_16,mlx5_17,mlx5_18,mlx5_19,mlx5_20,mlx5_21" ;;
  *)
    echo "Unsupported shape ${shape}; set var_UCX_NET_DEVICES and var_NCCL_IB_HCA manually."; exit 1 ;;
esac

echo "date=$(date -Is)"
echo "SLURM_JOB_NODELIST=${SLURM_JOB_NODELIST}"
echo "SLURM_NTASKS=${SLURM_NTASKS}"
scontrol show hostnames "${SLURM_JOB_NODELIST}"
which mpirun
echo "EXEC_CMD=${EXEC_CMD}"

case "${shape}" in
  BM.GPU.B4.8|BM.GPU.A100-v2.8|BM.GPU4.8)
    mpirun --mca pml ucx \
      --bind-to numa \
      --mca coll ^hcoll \
      -np "${SLURM_NTASKS}" -npernode "${GPUS_PER_NODE}" \
      -x NCCL_DEBUG \
      -x NCCL_IB_SL=0 \
      -x NCCL_IB_TC=41 \
      -x NCCL_IB_QPS_PER_CONNECTION=4 \
      -x UCX_TLS=ud,self,sm \
      -x UCX_NET_DEVICES=${var_UCX_NET_DEVICES} \
      -x HCOLL_ENABLE_MCAST_ALL=0 \
      -x coll_hcoll_enable=0 \
      -x NCCL_IB_GID_INDEX=3 \
      -x NCCL_ALGO=Ring \
      -x NCCL_IB_HCA="${var_NCCL_IB_HCA}" \
      "${EXEC_CMD}" -b 1G -e 10G -i $((1024*1024*1024*9)) -n 100 ;;
  BM.GPU.H100.8|BM.GPU.H200.8|BM.GPU.B200.8|BM.GPU.B300.8)
    mpirun --mca pml ucx \
      --bind-to numa \
      --mca coll ^hcoll \
      -np "${SLURM_NTASKS}" -npernode "${GPUS_PER_NODE}" \
      -x NCCL_DEBUG \
      -x NCCL_CUMEM_ENABLE=0 \
      -x NCCL_IB_SPLIT_DATA_ON_QPS=0 \
      -x NCCL_IB_QPS_PER_CONNECTION=1 \
      -x NCCL_IB_GID_INDEX=3 \
      -x NCCL_IB_TC=41 \
      -x NCCL_IB_SL=0 \
      -x NCCL_IB_TIMEOUT=22 \
      -x NCCL_NET_PLUGIN=${HPCX_NET_PLUGIN} \
      -x HCOLL_ENABLE_MCAST_ALL=0 \
      -x coll_hcoll_enable=0 \
      -x UCX_TLS=tcp \
      -x UCX_NET_DEVICES=${var_UCX_NET_DEVICES} \
      -x RX_QUEUE_LEN=8192 \
      -x IB_RX_QUEUE_LEN=8192 \
      -x NCCL_SOCKET_IFNAME=${var_UCX_NET_DEVICES} \
      -x NCCL_IGNORE_CPU_AFFINITY=1 \
      -x NCCL_IB_HCA="${var_NCCL_IB_HCA}" \
      "${EXEC_CMD}" -b 1G -e 16G -f 2 -g 1 -n 50 ;;
esac
EOF
chmod 755 "$HOME/nccl-slurm.sh"
```

### Submit the Job

From the operator node:

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

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  squeue -j "$NCCL_JOB_ID"

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  sacct -j "$NCCL_JOB_ID" \
    --format=JobID,JobName,Partition,Account,AllocNodes,State,ExitCode -P

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  su - "$SLURM_USER" -c \
    "tail -n 120 \$HOME/nccl-slurm-${NCCL_JOB_ID}.out; tail -n 120 \$HOME/nccl-slurm-${NCCL_JOB_ID}.err"
```

From inside the login pod:

```bash
NCCL_JOB_ID="$(sbatch --parsable \
  --account="${SLURM_ACCOUNT}" \
  --partition="${SLURM_PARTITION}" \
  --nodes="${NCCL_NODES}" \
  --ntasks-per-node="${GPUS_PER_NODE}" \
  --gres=gpu:"${GPUS_PER_NODE}" \
  --exclusive \
  --export=ALL,GPUS_PER_NODE="${GPUS_PER_NODE}" \
  "$HOME/nccl-slurm.sh")"

echo "$NCCL_JOB_ID"

squeue -j "$NCCL_JOB_ID"

sacct -j "$NCCL_JOB_ID" \
  --format=JobID,JobName,Partition,Account,AllocNodes,State,ExitCode -P

tail -n 120 "$HOME/nccl-slurm-${NCCL_JOB_ID}.out" \
            "$HOME/nccl-slurm-${NCCL_JOB_ID}.err"

if [[ ! -e "$HOME/nccl-slurm-${NCCL_JOB_ID}.out" ]]; then
  echo "Output files do not exist yet. The job is probably still pending or just starting."
  squeue -j "$NCCL_JOB_ID"
  scontrol show job "$NCCL_JOB_ID" | sed -n '1,25p'
fi
```

A successful job ends with `COMPLETED` and `ExitCode` `0:0`.

### Example Output

This is representative output from a two-node `BM.GPU.B4.8` run with 16 ranks
(avg bus bandwidth ~189 GB/s):

```text
shape=BM.GPU.B4.8
SLURM_JOB_NODELIST=inst-vfj93-oke-rdma,inst-e8gjz-oke-rdma
SLURM_NTASKS=16
/opt/hpcx/ompi/bin/mpirun
EXEC_CMD=/opt/nccl-tests/bin/all_reduce_perf
# nccl-tests version 2.17.9 nccl-headers=22903 nccl-library=22903
# Collective test starting: all_reduce_perf
# nThread 1 nGpus 1 minBytes 1073741824 maxBytes 10737418240 step: 9663676416(bytes) warmup iters: 1 iters: 100 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid   1584 on inst-vfj93-oke-rdma device  0 [0000:0f:00] NVIDIA A100-SXM4-40GB
#  Rank  7 Group  0 Pid   1598 on inst-vfj93-oke-rdma device  7 [0000:da:00] NVIDIA A100-SXM4-40GB
#  Rank  8 Group  0 Pid   1088 on inst-e8gjz-oke-rdma device  0 [0000:0f:00] NVIDIA A100-SXM4-40GB
#  Rank 15 Group  0 Pid   1100 on inst-e8gjz-oke-rdma device  7 [0000:da:00] NVIDIA A100-SXM4-40GB
NCCL version 2.29.3+cuda13.1
#
#       size         count      type   redop    root     time   algbw   busbw  #wrong     time   algbw   busbw  #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)             (us)  (GB/s)  (GB/s)
  1073741824     268435456     float     sum      -1  10785.4   99.56  186.67       0  10770.9   99.69  186.92       0
 10737418240    2684354560     float     sum      -1   105287  101.98  191.22       0   105285  101.98  191.22       0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 189.005
#
# Collective test concluded: all_reduce_perf
```

### Running via Pyxis (containerized)

The steps above run the baked-in `all_reduce_perf` directly on the worker
filesystem. You can instead run the test inside a container with Pyxis/Enroot.
This requires the Pyxis NVIDIA worker image (`slurmd-nvml-nccl-pyxis`, the
default the Terraform `slinky_image_profile` selects for NVIDIA): on that image
`srun` accepts `--container-image`, `--container-name`, and `--container-mounts`,
and the image's `97-oke-nvidia-mounts.sh` Enroot hook injects the GPU driver
userland.

Validated on two `BM.GPU.B4.8` nodes (16 ranks) with a plain `ubuntu:24.04`
container at ~187 GB/s avg bus bandwidth, at parity with the native run above.

Key points:

- Use a plain image (`ubuntu:24.04`) and mount the worker's NCCL test payload
  (`/opt/nccl-tests`, `/opt/hpcx`) and RDMA verbs userland into it. NGC images
  (for example `nvcr.io/nvidia/pytorch`) ship their own `rdma-core` and set
  `NVIDIA_VISIBLE_DEVICES` themselves, so the RDMA-userland mounts can be dropped
  for them.
- Export `NVIDIA_VISIBLE_DEVICES=all` (activates the GPU hook; the Slurm cgroup
  still restricts the container to the `--gres` GPUs) and
  `MELLANOX_VISIBLE_DEVICES=all` (RDMA device hook).
- Use `--container-name` so all tasks on a node share one container instance,
  which UCX intra-node shared memory requires.
- Pin the MPI control plane to IB UD (`UCX_TLS=ud,self,sm`,
  `UCX_NET_DEVICES=mlx5_0:1`); UCX inter-node TCP otherwise picks the
  `rdma0`-`rdma15` interfaces, which do not route TCP between nodes.

From inside the login pod, write the job and submit it with
`sbatch --partition=gpu --account=<account>`:

```bash
cat > "$HOME/nccl-pyxis.sh" <<'EOF'
#!/usr/bin/env bash
#SBATCH --job-name=nccl-pyxis
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=8
#SBATCH --cpus-per-task=2
#SBATCH --gres=gpu:8

set -euo pipefail

CONTAINER_IMAGE="${CONTAINER_IMAGE:-ubuntu:24.04}"

M=/usr/lib/x86_64-linux-gnu
RDMA_USERLAND_MOUNTS="$M/libibverbs.so.1:$M/libibverbs.so.1,$M/libmlx5.so.1:$M/libmlx5.so.1,$M/librdmacm.so.1:$M/librdmacm.so.1,$M/libnl-3.so.200:$M/libnl-3.so.200,$M/libnl-route-3.so.200:$M/libnl-route-3.so.200,$M/libibverbs:$M/libibverbs,/etc/libibverbs.d:/etc/libibverbs.d"
PAYLOAD_MOUNTS="/opt/nccl-tests:/opt/nccl-tests,/opt/hpcx:/opt/hpcx"

# Activate the GPU and RDMA Enroot hooks. The Slurm cgroup still restricts the
# container to the GPUs allocated by --gres.
export NVIDIA_VISIBLE_DEVICES=all
export MELLANOX_VISIBLE_DEVICES=all

# MPI control plane over IB UD on the frontend HCA.
export UCX_TLS=ud,self,sm
export UCX_NET_DEVICES=mlx5_0:1
export HCOLL_ENABLE_MCAST_ALL=0
export coll_hcoll_enable=0
export OMPI_MCA_coll=^hcoll

# BM.GPU.B4.8 NCCL settings; the HCA list is shape-specific.
export NCCL_DEBUG=WARN
export NCCL_ALGO=Ring
export NCCL_IGNORE_CPU_AFFINITY=1
export NCCL_IB_SPLIT_DATA_ON_QPS=0
export NCCL_IB_QPS_PER_CONNECTION=4
export NCCL_IB_GID_INDEX=3
export NCCL_IB_HCA="=mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_14,mlx5_15,mlx5_16,mlx5_17,mlx5_9,mlx5_10,mlx5_11,mlx5_12"
export NCCL_IB_TC=41
export NCCL_IB_SL=0
export NCCL_IB_TIMEOUT=16

# Mounted payload library paths and the HPCX relocation prefix.
export LD_LIBRARY_PATH=/opt/nccl-tests/lib:/opt/hpcx/ucx/lib:/opt/hpcx/ompi/lib:/opt/hpcx/nccl_rdma_sharp_plugin/lib
export OPAL_PREFIX=/opt/hpcx/ompi

srun --mpi=pmix --export=ALL \
  --container-image="$CONTAINER_IMAGE" \
  --container-name=nccl \
  --container-mounts="$PAYLOAD_MOUNTS,$RDMA_USERLAND_MOUNTS" \
  /opt/nccl-tests/bin/all_reduce_perf -b 1G -f 2 -g 1 -e 4G -c 1
EOF
chmod 755 "$HOME/nccl-pyxis.sh"

sbatch --partition=gpu --account=users "$HOME/nccl-pyxis.sh"
```

The first run imports `ubuntu:24.04` (`pyxis: imported docker image: ubuntu:24.04`
on stderr). A successful job ends `COMPLETED` with `ExitCode` `0:0` and reports
an avg bus bandwidth close to the native run. For another NVIDIA shape, replace
the `NCCL_IB_HCA` list (see
[Create the Slurm Batch Script](#create-the-slurm-batch-script)).

## RCCL Tests (AMD GPU shapes)

This section uses the AMD ROCm GPU worker image (`slurmd-rocm-rccl`), which
ships `all_reduce_perf` under `/opt/oci-hpc/rccl-tests/bin` (also on `PATH` via
`/usr/local/bin` and under `/workspace/rccl-tests/build`), OpenMPI at
`/opt/ompi`, and the environment helper `/opt/oci-hpc/rccl-tests/env.sh` that
sets the ROCm, OpenMPI, and rccl-tests paths.

RCCL reuses the `NCCL_*` environment variable names, so the tuning variables
below look like the NCCL ones but apply to RCCL.

### Set Variables

From the operator host or another shell with `kubectl` access:

```bash
export PATH=/home/ubuntu/bin:$PATH
export OCI_CLI_AUTH=instance_principal

export SLURM_NAMESPACE=slurm
export LOGIN_CONTAINER=login
export WORKER_CONTAINER=slurmd

export SLURM_USER=alice
export SLURM_ACCOUNT=users
export SLURM_PARTITION=gpu

export RCCL_NODES=2
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

From inside the login pod you only need the job parameters:

```bash
export SLURM_ACCOUNT=users
export SLURM_PARTITION=gpu

export RCCL_NODES=2
export GPUS_PER_NODE=8
```

### Validate Slurm and the Worker Image

Check that Slurm sees the GPU nodes and that they advertise GPU GRES.

From the operator node:

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  sinfo -Nel

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  scontrol show partition "$SLURM_PARTITION"
```

From inside the login pod:

```bash
sinfo -Nel
scontrol show partition "$SLURM_PARTITION"
sacctmgr -nP show user "$(whoami)" format=User,DefaultAccount,AdminLevel
```

Check that the worker image has the RCCL test binary, the RCCL/ROCm libraries,
and the RDMA device mount (a pod-level check that needs `kubectl` access to the
worker pod, so run it from the operator node):

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$GPU_WORKER_POD" -c "$WORKER_CONTAINER" -- \
  bash -lc '
    command -v mpirun
    command -v rocm-smi
    ls -ld /dev/infiniband
    ls -l /opt/oci-hpc/rccl-tests/bin/all_reduce_perf
    ls -l /opt/oci-hpc/rccl-tests/env.sh
    ldd /opt/oci-hpc/rccl-tests/bin/all_reduce_perf | grep -iE "rccl|rocm"
  '
```

Check the Slurm user association from the operator node:

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  sacctmgr -nP show user "$SLURM_USER" format=User,DefaultAccount,AdminLevel
```

### Optional One-GPU Smoke Test (rocm-smi)

Run a small single-rank job before the full multi-node test. This proves Slurm
can allocate an AMD GPU and that the GPU is visible to the job.

`sbatch --parsable` prints only the job ID; the test output is written to the
`--output` file, not the terminal. Capture the job ID so you can read it back.

From the operator node:

```bash
export SMOKE_JOB_ID="$(
  kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
    su - "$SLURM_USER" -c \
      "sbatch --wait --parsable \
        --account=${SLURM_ACCOUNT} \
        --partition=${SLURM_PARTITION} \
        --nodes=1 \
        --ntasks=1 \
        --gres=gpu:1 \
        --time=00:05:00 \
        --job-name=rccl-smoke \
        --output=\$HOME/rccl-smoke-%j.out \
        --wrap='rocm-smi'"
)"

echo "$SMOKE_JOB_ID"

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  sacct -j "$SMOKE_JOB_ID" \
    --format=JobID,JobName,Partition,Account,State,ExitCode -P

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  su - "$SLURM_USER" -c "cat \$HOME/rccl-smoke-${SMOKE_JOB_ID}.out"
```

From inside the login pod:

```bash
SMOKE_JOB_ID="$(sbatch --wait --parsable \
  --account="${SLURM_ACCOUNT}" \
  --partition="${SLURM_PARTITION}" \
  --nodes=1 \
  --ntasks=1 \
  --gres=gpu:1 \
  --time=00:05:00 \
  --job-name=rccl-smoke \
  --output="$HOME/rccl-smoke-%j.out" \
  --wrap='rocm-smi')"

echo "$SMOKE_JOB_ID"

sacct -j "$SMOKE_JOB_ID" \
  --format=JobID,JobName,Partition,Account,State,ExitCode -P
cat "$HOME/rccl-smoke-${SMOKE_JOB_ID}.out"
```

The job should be `COMPLETED` with `ExitCode` `0:0`, and the output should be the
`rocm-smi` table listing the allocated GPU.

### Create the Slurm Batch Script

The script sources `/opt/oci-hpc/rccl-tests/env.sh` for the ROCm, OpenMPI, and
rccl-tests paths, then runs `all_reduce_perf` over the Slurm allocation with
`mpirun`.

The `NCCL_IB_HCA` value and tuning below are for `BM.GPU.MI300X.8`. For another
AMD GPU shape, copy the HCA list and tuning from the matching manifest in
[`manifests/rccl-tests/kueue/`](../manifests/rccl-tests/kueue/). For example,
`BM.GPU.MI355X-v1.8` uses
`NCCL_IB_HCA="=mlx5_0,mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7"` with
`NCCL_IB_QPS_PER_CONNECTION=1` and adds `NCCL_IB_GID_INDEX=3`, `NCCL_IB_TC=41`,
and `NCCL_IB_TIMEOUT=22`.

Keep the transport selection at `--mca pml ucx` only. In testing, adding
`--mca btl ^openib` (and `--mca coll ^hcoll`) let the ranks initialize but then
hung the collective with no bandwidth output. The `openib` and `libvmw_pvrdma`
warnings those flags would suppress are harmless because UCX provides the
transport (see [Troubleshooting](#troubleshooting)).

The script body is the same for both run methods. From the operator node, write
it with `kubectl exec ... su - "$SLURM_USER" -c 'cat > ...'`; from inside the
login pod, write it directly with a heredoc.

From the operator node:

```bash
kubectl -n "$SLURM_NAMESPACE" exec -i "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  su - "$SLURM_USER" -c 'cat > "$HOME/rccl-slurm.sh" && chmod 755 "$HOME/rccl-slurm.sh"' <<'EOF'
#!/bin/bash
#SBATCH --job-name=rccl-slurm
#SBATCH --time=00:20:00
#SBATCH --output=%x-%j.out
#SBATCH --error=%x-%j.err

set -euxo pipefail

: "${GPUS_PER_NODE:=8}"

# ROCm + OpenMPI + rccl-tests paths from the worker image
source /opt/oci-hpc/rccl-tests/env.sh

# BM.GPU.MI300X.8 RCCL / RDMA tuning (RCCL reuses the NCCL_* names)
export NCCL_SOCKET_IFNAME=eth0
export NCCL_IB_HCA="=mlx5_0,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_7,mlx5_8,mlx5_9"
export NCCL_IB_SL=0
export NCCL_IB_QPS_PER_CONNECTION=4
export NCCL_IGNORE_CPU_AFFINITY=1
export UCX_NET_DEVICES=mlx5_0:1
export HCOLL_ENABLE_MCAST_ALL=0
export RX_QUEUE_LEN=8192
export IB_RX_QUEUE_LEN=8192

echo "date=$(date -Is)"
echo "SLURM_JOB_ID=${SLURM_JOB_ID}"
echo "SLURM_JOB_NODELIST=${SLURM_JOB_NODELIST}"
echo "SLURM_NTASKS=${SLURM_NTASKS}"
scontrol show hostnames "${SLURM_JOB_NODELIST}"
which mpirun
which all_reduce_perf

mpirun \
  -np "${SLURM_NTASKS}" \
  -npernode "${GPUS_PER_NODE}" \
  --bind-to numa \
  --mca pml ucx \
  -x PATH \
  -x LD_LIBRARY_PATH \
  -x NCCL_SOCKET_IFNAME \
  -x NCCL_IB_HCA \
  -x NCCL_IB_SL \
  -x NCCL_IB_QPS_PER_CONNECTION \
  -x NCCL_IGNORE_CPU_AFFINITY \
  -x UCX_NET_DEVICES \
  -x HCOLL_ENABLE_MCAST_ALL \
  -x coll_hcoll_enable=0 \
  -x RX_QUEUE_LEN \
  -x IB_RX_QUEUE_LEN \
  all_reduce_perf -b 1G -e 16G -f 2 -g 1
EOF
```

From inside the login pod:

```bash
cat > "$HOME/rccl-slurm.sh" <<'EOF'
#!/bin/bash
#SBATCH --job-name=rccl-slurm
#SBATCH --time=00:20:00
#SBATCH --output=%x-%j.out
#SBATCH --error=%x-%j.err

set -euxo pipefail

: "${GPUS_PER_NODE:=8}"

# ROCm + OpenMPI + rccl-tests paths from the worker image
source /opt/oci-hpc/rccl-tests/env.sh

# BM.GPU.MI300X.8 RCCL / RDMA tuning (RCCL reuses the NCCL_* names)
export NCCL_SOCKET_IFNAME=eth0
export NCCL_IB_HCA="=mlx5_0,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_7,mlx5_8,mlx5_9"
export NCCL_IB_SL=0
export NCCL_IB_QPS_PER_CONNECTION=4
export NCCL_IGNORE_CPU_AFFINITY=1
export UCX_NET_DEVICES=mlx5_0:1
export HCOLL_ENABLE_MCAST_ALL=0
export RX_QUEUE_LEN=8192
export IB_RX_QUEUE_LEN=8192

echo "date=$(date -Is)"
echo "SLURM_JOB_ID=${SLURM_JOB_ID}"
echo "SLURM_JOB_NODELIST=${SLURM_JOB_NODELIST}"
echo "SLURM_NTASKS=${SLURM_NTASKS}"
scontrol show hostnames "${SLURM_JOB_NODELIST}"
which mpirun
which all_reduce_perf

mpirun \
  -np "${SLURM_NTASKS}" \
  -npernode "${GPUS_PER_NODE}" \
  --bind-to numa \
  --mca pml ucx \
  -x PATH \
  -x LD_LIBRARY_PATH \
  -x NCCL_SOCKET_IFNAME \
  -x NCCL_IB_HCA \
  -x NCCL_IB_SL \
  -x NCCL_IB_QPS_PER_CONNECTION \
  -x NCCL_IGNORE_CPU_AFFINITY \
  -x UCX_NET_DEVICES \
  -x HCOLL_ENABLE_MCAST_ALL \
  -x coll_hcoll_enable=0 \
  -x RX_QUEUE_LEN \
  -x IB_RX_QUEUE_LEN \
  all_reduce_perf -b 1G -e 16G -f 2 -g 1
EOF
chmod 755 "$HOME/rccl-slurm.sh"
```

### Submit the Job

From the operator node:

```bash
export RCCL_JOB_ID="$(
  kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
    su - "$SLURM_USER" -c \
      "sbatch --parsable \
        --account=${SLURM_ACCOUNT} \
        --partition=${SLURM_PARTITION} \
        --nodes=${RCCL_NODES} \
        --ntasks-per-node=${GPUS_PER_NODE} \
        --gres=gpu:${GPUS_PER_NODE} \
        --exclusive \
        --export=ALL,GPUS_PER_NODE=${GPUS_PER_NODE} \
        \$HOME/rccl-slurm.sh"
)"

echo "$RCCL_JOB_ID"

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  squeue -j "$RCCL_JOB_ID"

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  sacct -j "$RCCL_JOB_ID" \
    --format=JobID,JobName,Partition,Account,AllocNodes,State,ExitCode -P

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  su - "$SLURM_USER" -c \
    "tail -n 120 \$HOME/rccl-slurm-${RCCL_JOB_ID}.out; tail -n 120 \$HOME/rccl-slurm-${RCCL_JOB_ID}.err"
```

From inside the login pod:

```bash
RCCL_JOB_ID="$(sbatch --parsable \
  --account="${SLURM_ACCOUNT}" \
  --partition="${SLURM_PARTITION}" \
  --nodes="${RCCL_NODES}" \
  --ntasks-per-node="${GPUS_PER_NODE}" \
  --gres=gpu:"${GPUS_PER_NODE}" \
  --exclusive \
  --export=ALL,GPUS_PER_NODE="${GPUS_PER_NODE}" \
  "$HOME/rccl-slurm.sh")"

echo "$RCCL_JOB_ID"

squeue -j "$RCCL_JOB_ID"

sacct -j "$RCCL_JOB_ID" \
  --format=JobID,JobName,Partition,Account,AllocNodes,State,ExitCode -P

tail -n 120 "$HOME/rccl-slurm-${RCCL_JOB_ID}.out" \
            "$HOME/rccl-slurm-${RCCL_JOB_ID}.err"

if [[ ! -e "$HOME/rccl-slurm-${RCCL_JOB_ID}.out" ]]; then
  echo "Output files do not exist yet. The job is probably still pending or just starting."
  squeue -j "$RCCL_JOB_ID"
  scontrol show job "$RCCL_JOB_ID" | sed -n '1,25p'
fi
```

A successful job ends with `COMPLETED` and `ExitCode` `0:0`.

### Example Output

This is representative output from a two-node `BM.GPU.MI300X.8` run with 16
ranks (avg bus bandwidth ~355 GB/s):

```text
SLURM_JOB_NODELIST=inst-aq8lt-oke-rdma,inst-ao2dl-oke-rdma
SLURM_NTASKS=16
/opt/ompi/bin/mpirun
/opt/oci-hpc/rccl-tests/bin/all_reduce_perf
# Collective test starting: all_reduce_perf
# nThread 1 nGpus 1 minBytes 1073741824 maxBytes 17179869184 step: 2(factor) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
rccl-tests: Version develop:a52452e
# Using devices
#  Rank  0 Group  0 Pid    268 on inst-aq8lt-oke-rdma device  0 [0000:11:00]
#  Rank  7 Group  0 Pid    275 on inst-aq8lt-oke-rdma device  7 [0000:da:00]
#  Rank  8 Group  0 Pid    114 on inst-ao2dl-oke-rdma device  0 [0000:11:00]
#  Rank 15 Group  0 Pid    121 on inst-ao2dl-oke-rdma device  7 [0000:da:00]
#
#                                                              out-of-place                       in-place
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
  1073741824     268435456     float     sum      -1   5753.0  186.64  349.95      0   5754.5  186.59  349.86      0
  2147483648     536870912     float     sum      -1    11406  188.28  353.03      0    11406  188.28  353.02      0
  4294967296    1073741824     float     sum      -1    22680  189.37  355.07      0    22677  189.40  355.12      0
  8589934592    2147483648     float     sum      -1    45110  190.42  357.04      0    45132  190.33  356.87      0
 17179869184    4294967296     float     sum      -1    89885  191.13  358.37      0    89917  191.06  358.24      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 354.659
#
# Collective test concluded: all_reduce_perf
```

### Running via Pyxis (containerized)

The steps above run the baked-in `all_reduce_perf` directly on the worker
filesystem. You can instead run the test inside a container with Pyxis/Enroot.
This requires the Pyxis AMD worker image (`slurmd-rocm-rccl-...-pyxis`) and a
**tmpfs `/tmp`** on the worker pods: Enroot writes its image-import scratch under
`/tmp`, and while flattening a multi-layer image it creates OverlayFS whiteouts
(device nodes). The pod's overlay root filesystem rejects `mknod` (even for
root), so the import fails with
`enroot-aufs2ovlfs: ... Operation not permitted` unless `/tmp` is a tmpfs. On
that image `srun` accepts `--container-image`, `--container-name`, and
`--container-mounts`.

Validated on two `BM.GPU.MI300X.8` nodes (16 ranks) with the self-contained
`rccl-tests` image at ~354 GB/s, at parity with the native run above.

Key points:

- The `rccl-tests` image is self-contained for the ROCm/RCCL userland, so no
  library mounts are needed (unlike the NVIDIA path).
- Enroot has no AMD GPU hook, so bind the AMD GPU (`/dev/kfd`, `/dev/dri`) and
  RDMA (`/dev/infiniband`) device nodes into the container with
  `--container-mounts`. The Slurm cgroup (`ConstrainDevices=yes`) still restricts
  the container to the GPUs allocated by `--gres`.
- Use `--container-name` so all tasks on a node share one container instance,
  which UCX intra-node shared memory requires.
- Submit it as a plain `sbatch`. Do **not** "pre-warm" the import with a separate
  interactive `srun --container-image` step: the Enroot import of the multi-GB
  image runs longer than srun's message timeout, so that srun fails with
  `Socket timed out on send/recv` and leaves a step stuck `COMPLETING` that holds
  the nodes. The job's own `srun` imports the image inline (a few minutes on the
  first run per node) and then runs.

From inside the login pod, write the job and submit it with
`sbatch --partition=gpu --account=<account>`:

```bash
cat > "$HOME/rccl-pyxis.sh" <<'EOF'
#!/usr/bin/env bash
#SBATCH --job-name=rccl-pyxis
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=8
#SBATCH --gres=gpu:8
#SBATCH --exclusive

set -euo pipefail

# The rccl-tests image is self-contained for the ROCm/RCCL userland.
CONTAINER_IMAGE="${CONTAINER_IMAGE:-iad.ocir.io#idxzjcdglx2s/rccl-tests:rocm-7.1.1-ubuntu22.04-rccl-2.27.7-011826.1}"

# Enroot has no AMD hook; bind the AMD GPU + RDMA device nodes in. The Slurm
# cgroup still restricts the container to the --gres GPUs.
DEVICE_MOUNTS=/dev/kfd:/dev/kfd,/dev/dri:/dev/dri,/dev/infiniband:/dev/infiniband

# BM.GPU.MI300X.8 RCCL / UCX transport (RCCL reuses the NCCL_* names).
export NCCL_CUMEM_ENABLE=0
export NCCL_IB_TIMEOUT=22
export NCCL_IB_SL=0
export NCCL_IB_TC=41
export NCCL_IB_GID_INDEX=3
export NCCL_DEBUG=WARN
export NCCL_IB_QPS_PER_CONNECTION=1
export NCCL_IB_SPLIT_DATA_ON_QPS=0
export NCCL_IB_HCA="=mlx5_0,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_7,mlx5_8,mlx5_9"
export NCCL_PXN_DISABLE=0
export NCCL_NET_PLUGIN=none
export UCX_TLS=ud,self,sm
export UCX_NET_DEVICES=mlx5_0:1
export HCOLL_ENABLE_MCAST_ALL=0
export coll_hcoll_enable=0

# --container-name: all tasks on a node share one container instance (UCX shm).
srun --mpi=pmix --export=ALL \
  --container-image="$CONTAINER_IMAGE" \
  --container-name=rccl \
  --container-mounts="$DEVICE_MOUNTS" \
  /workspace/rccl-tests/build/all_reduce_perf -b 1G -e 8G -f 2 -g 1 -n 20
EOF
chmod 755 "$HOME/rccl-pyxis.sh"

sbatch --partition=gpu --account=users "$HOME/rccl-pyxis.sh"
```

## Troubleshooting

The commands below are shown in the direct (login pod) form. From the operator
node, wrap each Slurm command in
`kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- ...`.

If `all_reduce_perf` fails with `libcudart.so` or `libnccl.so` not found on an
NVIDIA worker, make sure the job exports:

```bash
export LD_LIBRARY_PATH=/opt/nccl-tests/lib:${LD_LIBRARY_PATH:-}
```

On an AMD worker, make sure the job sources the image's environment helper so
the ROCm, OpenMPI, and RCCL paths are set:

```bash
source /opt/oci-hpc/rccl-tests/env.sh
```

On AMD workers, `mpirun` stderr may show `libibverbs: ... libvmw_pvrdma...` and
`openib` "no preset parameters" / "error initializing an OpenFabrics device"
warnings. These are harmless: the transport is UCX (`--mca pml ucx`), not the
`openib` BTL. Do not try to silence them with `--mca btl ^openib` on this image;
in testing that let the ranks initialize but then hung the collective with no
bandwidth output. Leave the transport selection at `--mca pml ucx`.

If direct `srun all_reduce_perf` fails during `MPI_Init` with an OpenMPI PMI or
PMIx error, submit a Slurm allocation with `sbatch` and launch ranks with
`mpirun` as shown above.

If the job remains pending, check GPU node availability and GRES:

```bash
sinfo -Nel
scontrol show partition "$SLURM_PARTITION"
```

If bandwidth is much lower than expected, verify:

- GPU worker pods are on the RDMA-enabled node pool.
- GPU worker pods mount `/dev/infiniband`.
- The Slurm worker NodeSet uses `hostNetwork` for RDMA-capable workers.
- `NCCL_IB_HCA` matches the OCI GPU shape (the NVIDIA and AMD HCA lists differ;
  see the matching manifest under
  [`manifests/nccl-tests/kueue/`](../manifests/nccl-tests/kueue/) or
  [`manifests/rccl-tests/kueue/`](../manifests/rccl-tests/kueue/)).
- `NCCL_SOCKET_IFNAME` and the OpenMPI TCP interface match the worker network
  interface used by the Slurm pods.
