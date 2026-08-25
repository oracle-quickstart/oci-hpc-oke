# Run NCCL and RCCL Tests with Slurm Operator

Use this guide to run multi-node GPU bandwidth tests through Slurm Operator.

- Use NCCL for NVIDIA GPUs.
- Use RCCL for AMD GPUs.
- Use `all_reduce_perf` to measure collective bandwidth over RDMA.

Run the test commands in the Slurm login pod.

This guide supports host-network Slurm workers only.

## Quick Start

### Prerequisites

See [Slurm User Onboarding](./slurm-operator-user-onboarding.md) if you need a user.

The default worker images contain these test binaries:

| GPU vendor | Test binary |
| --- | --- |
| NVIDIA | `/opt/nccl-tests/bin/all_reduce_perf` |
| AMD | `/opt/oci-hpc/rccl-tests/bin/all_reduce_perf` |

### Open the Login Shell

Get the login service IP from the operator node:

```bash
kubectl -n slurm get service slurm-login-slinky \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}'
```

Connect as a regular Slurm user:

```bash
ssh "<user>@<login-service-ip>"
```

Run all remaining test commands in this login shell.

### Select a GPU Partition

List the partitions:

```bash
sinfo
```

Set the partition for the test:

```bash
export SLURM_PARTITION=rdma
```

## NCCL Tests for NVIDIA GPUs

### Set the Test Size

Run these commands in the login shell:

```bash
export NCCL_NODES=2
export GPUS_PER_NODE=8

scontrol show partition "$SLURM_PARTITION"
```

Use four GPUs per node for GB200 and GB300 shapes. See [GMC on GB200 and GB300](#gmc-on-gb200-and-gb300).

### Run an Optional GPU Check

```bash
SMOKE_JOB_ID="$(sbatch --wait --parsable \
  --partition="$SLURM_PARTITION" \
  --nodes=1 \
  --ntasks=1 \
  --gres=gpu:1 \
  --time=00:05:00 \
  --job-name=nccl-smoke \
  --output="$HOME/nccl-smoke-%j.out" \
  --wrap='nvidia-smi')"

cat "$HOME/nccl-smoke-${SMOKE_JOB_ID}.out"
```

The output must list the allocated GPU.

### Create the Host-Network Script

This script supports these shapes:

- `BM.GPU4.8`
- `BM.GPU.A100-v2.8`
- `BM.GPU.B4.8`
- `BM.GPU.H100.8`
- `BM.GPU.H200.8`
- `BM.GPU.B200.8`
- `BM.GPU.B300.8`

The script gets the shape from the instance metadata service. Add a `case` entry for another shape.

```bash
cat > "$HOME/nccl-slurm.sh" <<'EOF'
#!/usr/bin/env bash
#SBATCH --job-name=nccl-slurm
#SBATCH --time=00:20:00
#SBATCH --output=%x-%j.out

set -uxo pipefail
: "${GPUS_PER_NODE:=8}"

source /opt/nccl-tests/env.sh

EXEC_CMD="${NCCL_TEST_HOME}/bin/${EXEC:-all_reduce_perf}"
[[ -x "$EXEC_CMD" ]] || { echo "Test executable $EXEC_CMD not found"; exit 1; }

HPCX_NET_PLUGIN=/opt/hpcx/nccl_rdma_sharp_plugin/lib/libnccl-net.so
[[ -f "$HPCX_NET_PLUGIN" ]] || HPCX_NET_PLUGIN=none

export NCCL_DEBUG=WARN

shape="$(
  curl -sH 'Authorization: Bearer Oracle' \
    http://169.254.169.254/opc/v2/instance/ | jq -r .shape
)"
echo "shape=$shape"

case "$shape" in
  BM.GPU.B4.8|BM.GPU.A100-v2.8)
    var_UCX_NET_DEVICES=mlx5_0:1
    var_NCCL_IB_HCA="=mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_14,mlx5_15,mlx5_16,mlx5_17,mlx5_9,mlx5_10,mlx5_11,mlx5_12"
    ;;
  BM.GPU4.8)
    var_UCX_NET_DEVICES=mlx5_4:1
    var_NCCL_IB_HCA="=mlx5_0,mlx5_2,mlx5_6,mlx5_8,mlx5_10,mlx5_12,mlx5_14,mlx5_16,mlx5_1,mlx5_3,mlx5_7,mlx5_9,mlx5_11,mlx5_13,mlx5_15,mlx5_17"
    ;;
  BM.GPU.H100.8)
    var_UCX_NET_DEVICES=eth0
    var_NCCL_IB_HCA="=mlx5_0,mlx5_1,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_9,mlx5_10,mlx5_12,mlx5_13,mlx5_14,mlx5_15,mlx5_16,mlx5_17"
    ;;
  BM.GPU.H200.8|BM.GPU.B200.8)
    var_UCX_NET_DEVICES=eth0
    var_NCCL_IB_HCA="=mlx5_0,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_9,mlx5_10,mlx5_11"
    ;;
  BM.GPU.B300.8)
    var_UCX_NET_DEVICES=eth0
    var_NCCL_IB_HCA="=mlx5_0,mlx5_1,mlx5_7,mlx5_8,mlx5_9,mlx5_10,mlx5_11,mlx5_12,mlx5_13,mlx5_14,mlx5_16,mlx5_17,mlx5_18,mlx5_19,mlx5_20,mlx5_21"
    ;;
  *)
    echo "Unsupported shape $shape" >&2
    exit 1
    ;;
esac

echo "SLURM_JOB_NODELIST=$SLURM_JOB_NODELIST"
echo "SLURM_NTASKS=$SLURM_NTASKS"
scontrol show hostnames "$SLURM_JOB_NODELIST"

case "$shape" in
  BM.GPU.B4.8|BM.GPU.A100-v2.8|BM.GPU4.8)
    mpirun --mca pml ucx \
      --bind-to numa \
      --mca coll ^hcoll \
      -np "$SLURM_NTASKS" \
      -npernode "$GPUS_PER_NODE" \
      -x NCCL_DEBUG \
      -x NCCL_IB_SL=0 \
      -x NCCL_IB_TC=41 \
      -x NCCL_IB_QPS_PER_CONNECTION=4 \
      -x UCX_TLS=ud,self,sm \
      -x UCX_NET_DEVICES="$var_UCX_NET_DEVICES" \
      -x HCOLL_ENABLE_MCAST_ALL=0 \
      -x coll_hcoll_enable=0 \
      -x NCCL_IB_GID_INDEX=3 \
      -x NCCL_ALGO=Ring \
      -x NCCL_IB_HCA="$var_NCCL_IB_HCA" \
      "$EXEC_CMD" -b 1G -e 8G -f 2 -g 1 -n 100
    ;;
  BM.GPU.H100.8|BM.GPU.H200.8|BM.GPU.B200.8|BM.GPU.B300.8)
    mpirun --mca pml ucx \
      --bind-to numa \
      --mca coll ^hcoll \
      -np "$SLURM_NTASKS" \
      -npernode "$GPUS_PER_NODE" \
      -x NCCL_DEBUG \
      -x NCCL_CUMEM_ENABLE=0 \
      -x NCCL_IB_SPLIT_DATA_ON_QPS=0 \
      -x NCCL_IB_QPS_PER_CONNECTION=1 \
      -x NCCL_IB_GID_INDEX=3 \
      -x NCCL_IB_TC=41 \
      -x NCCL_IB_SL=0 \
      -x NCCL_IB_TIMEOUT=22 \
      -x NCCL_NET_PLUGIN="$HPCX_NET_PLUGIN" \
      -x HCOLL_ENABLE_MCAST_ALL=0 \
      -x coll_hcoll_enable=0 \
      -x UCX_TLS=tcp \
      -x UCX_NET_DEVICES="$var_UCX_NET_DEVICES" \
      -x RX_QUEUE_LEN=8192 \
      -x IB_RX_QUEUE_LEN=8192 \
      -x NCCL_SOCKET_IFNAME="$var_UCX_NET_DEVICES" \
      -x NCCL_IGNORE_CPU_AFFINITY=1 \
      -x NCCL_IB_HCA="$var_NCCL_IB_HCA" \
      "$EXEC_CMD" -b 1G -e 16G -f 2 -g 1 -n 50
    ;;
esac
EOF

chmod 755 "$HOME/nccl-slurm.sh"
```

### Submit the NCCL Job

```bash
NCCL_JOB_ID="$(sbatch --wait --parsable \
  --partition="$SLURM_PARTITION" \
  --nodes="$NCCL_NODES" \
  --ntasks-per-node="$GPUS_PER_NODE" \
  --gres=gpu:"$GPUS_PER_NODE" \
  --exclusive \
  --export=ALL,GPUS_PER_NODE="$GPUS_PER_NODE" \
  "$HOME/nccl-slurm.sh")"

cat "$HOME/nccl-slurm-${NCCL_JOB_ID}.out"
```

## GMC on GB200 and GB300

GB200 and GB300 workers use four GPUs per node. They also use an NVIDIA DRA `ComputeDomain`.

With one GPU memory fabric, use the `gmc` partition. With multiple fabrics, use one `gmc-<suffix>` partition.

Do not use `gmc-all` for an MNNVL test. All test nodes must use the same `ComputeDomain`.

Check the Kubernetes resources from the operator node:

```bash
kubectl -n slurm get computedomain
kubectl -n slurm get resourceclaimtemplates,resourceclaims
kubectl -n dra-driver-nvidia-gpu get pods
kubectl -n slurm get nodesets
```

The `ComputeDomain` must be ready. Each worker claim must be allocated and reserved.

Run this script from the login shell:

```bash
cat > "$HOME/nccl-gmc.sh" <<'EOF'
#!/usr/bin/env bash
#SBATCH --job-name=nccl-gmc
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=2
#SBATCH --gres=gpu:4
#SBATCH --time=00:20:00
#SBATCH --output=%x-%j.out

set -euo pipefail

export PATH=/opt/hpcx/ompi/bin:/opt/nccl-tests/bin:${PATH}
export LD_LIBRARY_PATH=/opt/nccl-tests/lib:/opt/hpcx/ucx/lib:/opt/hpcx/ompi/lib:/opt/hpcx/nccl_spectrum-x_plugin/lib:/opt/hpcx/nccl_rdma_sharp_plugin/lib:${LD_LIBRARY_PATH:-}
export OPAL_PREFIX=/opt/hpcx/ompi
export UCX_TLS=tcp
export UCX_NET_DEVICES=eth0
export HCOLL_ENABLE_MCAST_ALL=0
export coll_hcoll_enable=0
export OMPI_MCA_coll=^hcoll

test -r /etc/nccl.conf
sha256sum /etc/nccl.conf
cat /etc/nccl.conf
scontrol show hostnames "$SLURM_JOB_NODELIST"

mpirun --mca pml ucx \
  --bind-to numa \
  --mca coll '^hcoll' \
  -np "$SLURM_NTASKS" \
  -npernode 4 \
  -x PATH \
  -x LD_LIBRARY_PATH \
  -x OPAL_PREFIX \
  -x UCX_TLS \
  -x UCX_NET_DEVICES \
  -x HCOLL_ENABLE_MCAST_ALL \
  -x coll_hcoll_enable \
  /opt/nccl-tests/bin/all_reduce_perf -b 1G -e 8G -f 2 -g 1 -n 20
EOF

chmod 755 "$HOME/nccl-gmc.sh"

export SLURM_PARTITION="<gmc-partition>"
GMC_JOB_ID="$(sbatch --wait --parsable \
  --partition="$SLURM_PARTITION" \
  "$HOME/nccl-gmc.sh")"

cat "$HOME/nccl-gmc-${GMC_JOB_ID}.out"
```

The script does not set `NCCL_*` variables. NCCL reads the shape settings from `/etc/nccl.conf`.

## RCCL Tests for AMD GPUs

RCCL uses `NCCL_*` variable names for its tuning.

### Set the Test Size

```bash
export RCCL_NODES=2
export GPUS_PER_NODE=8

sinfo
scontrol show partition "$SLURM_PARTITION"
```

### Run an Optional GPU Check

```bash
SMOKE_JOB_ID="$(sbatch --wait --parsable \
  --partition="$SLURM_PARTITION" \
  --nodes=1 \
  --ntasks=1 \
  --gres=gpu:1 \
  --time=00:05:00 \
  --job-name=rccl-smoke \
  --output="$HOME/rccl-smoke-%j.out" \
  --wrap='rocm-smi')"

cat "$HOME/rccl-smoke-${SMOKE_JOB_ID}.out"
```

The output must list the allocated GPU.

### Create the Host-Network Script

This script contains the tuning for `BM.GPU.MI300X.8`.

For another shape, use the matching values from [`manifests/rccl-tests/kueue/`](../manifests/rccl-tests/kueue/).

```bash
cat > "$HOME/rccl-slurm.sh" <<'EOF'
#!/usr/bin/env bash
#SBATCH --job-name=rccl-slurm
#SBATCH --time=00:20:00
#SBATCH --output=%x-%j.out

set -euxo pipefail
: "${GPUS_PER_NODE:=8}"

source /opt/oci-hpc/rccl-tests/env.sh

export NCCL_SOCKET_IFNAME=eth0
export NCCL_IB_HCA="=mlx5_0,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_7,mlx5_8,mlx5_9"
export NCCL_IB_SL=0
export NCCL_IB_QPS_PER_CONNECTION=1
export NCCL_IGNORE_CPU_AFFINITY=1
export UCX_NET_DEVICES=mlx5_0:1
export HCOLL_ENABLE_MCAST_ALL=0
export RX_QUEUE_LEN=8192
export IB_RX_QUEUE_LEN=8192

echo "SLURM_JOB_ID=$SLURM_JOB_ID"
echo "SLURM_JOB_NODELIST=$SLURM_JOB_NODELIST"
echo "SLURM_NTASKS=$SLURM_NTASKS"
scontrol show hostnames "$SLURM_JOB_NODELIST"

mpirun \
  -np "$SLURM_NTASKS" \
  -npernode "$GPUS_PER_NODE" \
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

Do not add `--mca btl ^openib`. This option can cause the collective to stop.

### Submit the RCCL Job

```bash
RCCL_JOB_ID="$(sbatch --wait --parsable \
  --partition="$SLURM_PARTITION" \
  --nodes="$RCCL_NODES" \
  --ntasks-per-node="$GPUS_PER_NODE" \
  --gres=gpu:"$GPUS_PER_NODE" \
  --exclusive \
  --export=ALL,GPUS_PER_NODE="$GPUS_PER_NODE" \
  "$HOME/rccl-slurm.sh")"

cat "$HOME/rccl-slurm-${RCCL_JOB_ID}.out"
```

## Pyxis Reference

Use the native tests above for the shortest workflow. Use Pyxis only when the test must run in a container.

### NVIDIA Workers

- Use a Pyxis-enabled NVIDIA worker image.
- Mount `/opt/nccl-tests`, `/opt/hpcx`, and `/etc/nccl.conf`.
- Set `NVIDIA_VISIBLE_DEVICES=all`.
- Set `MELLANOX_VISIBLE_DEVICES=all`.
- Use one `--container-name` for all tasks on each node.

GB200 and GB300 containers must mount `/etc/nccl.conf`. Do not override its `NCCL_*` values.

### AMD Workers

- Use a Pyxis-enabled AMD worker image.
- Mount `/dev/kfd`, `/dev/dri`, `/dev/infiniband`, and `/etc/rccl.conf`.
- Configure worker `/tmp` as `tmpfs` for Enroot image imports.
- Use one `--container-name` for all tasks on each node.
- Do not run a separate `srun` to pre-import a large image.

## Troubleshooting

### A Job Remains Pending

Check the partition and GPU resources:

```bash
sinfo
scontrol show partition "$SLURM_PARTITION"
squeue -j "<job-id>" -o '%.18i %.9T %.30R'
```

### NVIDIA Libraries Are Missing

Set the worker library path:

```bash
export LD_LIBRARY_PATH=/opt/nccl-tests/lib:${LD_LIBRARY_PATH:-}
```

### AMD Libraries Are Missing

Load the worker environment:

```bash
source /opt/oci-hpc/rccl-tests/env.sh
```

### AMD OpenFabrics Warnings Appear

The AMD image can report `openib` or `libvmw_pvrdma` warnings. UCX remains the selected transport.

Do not add `--mca btl ^openib`. This option can stop the collective.

### Bandwidth Is Low

Check these items:

- The GPU workers run on the RDMA node pool.
- The workers mount `/dev/infiniband`.
- The worker NodeSet uses host network.
- `NCCL_IB_HCA` matches the GPU shape.
- The socket and UCX interfaces match the worker network.
