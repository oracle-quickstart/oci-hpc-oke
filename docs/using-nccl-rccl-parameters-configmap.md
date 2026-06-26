# Using the NCCL/RCCL Parameters ConfigMap in Job Manifests

## Overview

When the cluster is deployed with an RDMA or GMC GPU worker pool, Terraform
creates a ConfigMap in the `default` namespace holding the recommended NCCL/RCCL
tuning parameters for the deployed shape (from
[recommended-nccl-rccl-parameters-by-shape.md](./recommended-nccl-rccl-parameters-by-shape.md)),
one environment variable per key.

The ConfigMap name depends on the GPU vendor:

- `oci-nccl-parameters` for NVIDIA shapes
- `oci-rccl-parameters` for AMD shapes

The examples below use an NVIDIA H100 cluster, so they reference
`oci-nccl-parameters`. On an AMD cluster use `oci-rccl-parameters` instead; the structure
is identical. An example ConfigMap (NVIDIA H100):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: oci-nccl-parameters
  namespace: default
data:
  NCCL_DEBUG: "WARN"
  NCCL_CUMEM_ENABLE: "0"
  NCCL_IB_SPLIT_DATA_ON_QPS: "0"
  NCCL_IB_GID_INDEX: "3"
  NCCL_IB_HCA: "=mlx5_0,mlx5_1,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_9,mlx5_10,mlx5_12,mlx5_13,mlx5_14,mlx5_15,mlx5_16,mlx5_17"
  NCCL_IB_TC: "41"
  NCCL_IB_SL: "0"
  NCCL_IB_TIMEOUT: "22"
  NCCL_SOCKET_IFNAME: "eth0"
  NCCL_IGNORE_CPU_AFFINITY: "1"
```

The ConfigMap is controlled by the `deploy_nccl_rccl_param_configmap` Terraform
variable (default `true`). It is created only when `worker_rdma_enabled` or
`worker_gmc_enabled` is true and the shape is covered by the parameter set.

Verify it exists:

```bash
kubectl get configmap oci-nccl-parameters -n default -o yaml
```

## Quickstart

For any pod whose process reads NCCL/RCCL settings from the environment, mount
every key as a container environment variable with `envFrom`:

```yaml
containers:
- name: my-container
  image: ...
  envFrom:
  - configMapRef:
      name: oci-nccl-parameters
```

For an MPIJob the ranks run in the **worker** pods (`mpirun` launches them over
SSH), so the settings must reach the worker processes. Add `envFrom` to the
worker container and copy the variables into `/etc/environment` before starting
`sshd`. Every rank then inherits them and `mpirun` needs no `-x NCCL_*` flags at
all:

```yaml
          containers:
          - name: mpi-worker
            envFrom:
            - configMapRef:
                name: oci-nccl-parameters
            command:
            - /bin/bash
            - -c
            - mkdir -p /var/run/sshd; printenv | grep -E '^(NCCL|RCCL)_' >> /etc/environment; /usr/sbin/sshd -D -p 2222;
```

## Worked example: BM.GPU.H100.8 NCCL test

The sample manifest
[manifests/nccl-tests/kueue/BM.GPU.H100.8.yaml](../manifests/nccl-tests/kueue/BM.GPU.H100.8.yaml)
hard-codes the parameters as inline `mpirun -x VAR=value` flags. To drive it from
the ConfigMap instead, make two changes.

### 1. Inject the ConfigMap into the worker pods

Add `envFrom` to the worker container, and write the NCCL/RCCL variables into
`/etc/environment` before starting `sshd` so the SSH sessions `mpirun` opens
inherit them.

Before:

```yaml
          containers:
          - name: mpi-worker
            ...
            image: iad.ocir.io/idxzjcdglx2s/nccl-tests:cuda-13.1.1-ubuntu-24.04-nccl-2.29.3-020926.1
            command:
              - /bin/bash
              - -c
              - mkdir -p /var/run/sshd; /usr/sbin/sshd -D -p 2222;
```

After:

```yaml
          containers:
          - name: mpi-worker
            ...
            image: iad.ocir.io/idxzjcdglx2s/nccl-tests:cuda-13.1.1-ubuntu-24.04-nccl-2.29.3-020926.1
            envFrom:
            - configMapRef:
                name: oci-nccl-parameters
            command:
              - /bin/bash
              - -c
              - mkdir -p /var/run/sshd; printenv | grep -E '^(NCCL|RCCL)_' >> /etc/environment; /usr/sbin/sshd -D -p 2222;
```

`envFrom` puts every ConfigMap key (including the VF-aware `NCCL_IB_HCA`) into the
worker environment; the `printenv ... >> /etc/environment` line publishes those
values to each SSH session, so every rank starts with them. This works with the
stock Ubuntu-based nccl-tests image, whose `sshd` reads `/etc/environment` through
PAM.

### 2. Remove the NCCL flags from `mpirun`

The workers now carry the settings, so delete every `-x NCCL_*` flag from the
launcher command. Keep only the non-NCCL tuning flags that are not in the
ConfigMap.

Before:

```bash
                mpirun --allow-run-as-root \
                -mca coll ^hcoll  -mca plm_rsh_args "-p 2222" \
                -mca coll_hcoll_enable 0 \
                -np $NP -npernode $NUM_GPUS --bind-to numa \
                -x NCCL_DEBUG=WARN \
                -x NCCL_CUMEM_ENABLE=0 \
                -x NCCL_IB_SPLIT_DATA_ON_QPS=0 \
                -x NCCL_IB_GID_INDEX=3 \
                -x NCCL_IB_HCA==mlx5_0,mlx5_1,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_9,mlx5_10,mlx5_12,mlx5_13,mlx5_14,mlx5_15,mlx5_16,mlx5_17 \
                -x NCCL_IB_TC=41 \
                -x NCCL_IB_SL=0 \
                -x NCCL_IB_TIMEOUT=22 \
                -x HCOLL_ENABLE_MCAST_ALL=0 \
                -x UCX_TLS=tcp \
                -x UCX_NET_DEVICES=eth0 \
                -x RX_QUEUE_LEN=8192 \
                -x IB_RX_QUEUE_LEN=8192 \
                -x NCCL_SOCKET_IFNAME=eth0 \
                -x NCCL_IGNORE_CPU_AFFINITY=1 \
                /workspace/nccl-tests/build/all_reduce_perf -b 8 -f 2 -g 1 -e 4G -c 1
```

After:

```bash
                mpirun --allow-run-as-root \
                -mca coll ^hcoll  -mca plm_rsh_args "-p 2222" \
                -mca coll_hcoll_enable 0 \
                -np $NP -npernode $NUM_GPUS --bind-to numa \
                -x HCOLL_ENABLE_MCAST_ALL=0 \
                -x UCX_TLS=tcp \
                -x UCX_NET_DEVICES=eth0 \
                -x RX_QUEUE_LEN=8192 \
                -x IB_RX_QUEUE_LEN=8192 \
                /workspace/nccl-tests/build/all_reduce_perf -b 8 -f 2 -g 1 -e 4G -c 1
```

Every NCCL/RCCL setting is gone from the manifest. The five remaining flags are
test-harness tuning, not device settings; add them to the worker
`/etc/environment` line too if you want a bare `mpirun`. On a non-VF cluster
`NCCL_IB_HCA` resolves to the full device list; on a VF cluster it resolves to
`mlx5`, with no manifest change.

### Alternative: forward from the launcher

If your image's `sshd` does not load `/etc/environment`, forward from the launcher
instead: put `envFrom` on the **launcher** container and generate the `-x` flags
from its environment. `mpirun -x` takes one variable name and has no wildcard, so
`-x NCCL_*` is not valid; build one flag per variable:

```bash
                # One -x flag per NCCL/RCCL variable in the launcher environment.
                X_ARGS=$(for v in $(compgen -e); do
                  case "$v" in NCCL_*|RCCL_*) printf ' -x %s' "$v" ;; esac
                done)

                mpirun --allow-run-as-root \
                -mca coll ^hcoll  -mca plm_rsh_args "-p 2222" \
                -mca coll_hcoll_enable 0 \
                -np $NP -npernode $NUM_GPUS --bind-to numa \
                $X_ARGS \
                -x HCOLL_ENABLE_MCAST_ALL=0 \
                -x UCX_TLS=tcp \
                -x UCX_NET_DEVICES=eth0 \
                -x RX_QUEUE_LEN=8192 \
                -x IB_RX_QUEUE_LEN=8192 \
                /workspace/nccl-tests/build/all_reduce_perf -b 8 -f 2 -g 1 -e 4G -c 1
```

`compgen -e` lists exported variable names; the `case` keeps the `NCCL_*` and
`RCCL_*` ones, so nothing is listed by hand and ConfigMap changes need no manifest
edit.

## Consuming from non-MPI pods (PyTorch, torchrun, custom launchers)

Processes that read NCCL settings directly from the environment (for example a
`torchrun` job) only need `envFrom` on the pod that runs the training process.
No `mpirun -x` forwarding is involved:

```yaml
spec:
  containers:
  - name: trainer
    image: ...
    envFrom:
    - configMapRef:
        name: oci-nccl-parameters
    command: ["torchrun", "..."]
```

## Notes and caveats

- Namespace. The ConfigMap lives in `default`. A `configMapRef` only resolves in
  the same namespace, so run the job in `default`, or copy the ConfigMap into the
  job's namespace:

  ```bash
  kubectl get configmap oci-nccl-parameters -n default -o yaml \
    | sed 's/namespace: default/namespace: <your-namespace>/' \
    | kubectl apply -f -
  ```

- Virtual functions need more than the env var. The ConfigMap sets `NCCL_IB_HCA`
  to `mlx5` when VFs are enabled, but a VF workload still needs the SR-IOV pieces
  the standard manifest does not have: the
  `k8s.v1.cni.cncf.io/networks: rdma-vf,...` pod annotation and the
  `nvidia.com/rdma-vf` resource requests. See the manifests under
  [manifests/nccl-tests/kueue/virtual-functions/](../manifests/nccl-tests/kueue/virtual-functions/)
  for the full VF layout. The ConfigMap handles the parameter values; it does not
  change pod networking or resources.

- Override a single value. `envFrom` sets the container environment; an explicit
  `env:` entry or an inline `-x VAR=value` for the same variable takes precedence,
  so you can override one parameter while inheriting the rest from the ConfigMap.

- Available keys vary by shape. Each shape carries only the parameters listed for
  it in
  [recommended-nccl-rccl-parameters-by-shape.md](./recommended-nccl-rccl-parameters-by-shape.md)
  (for example AMD shapes include `RCCL_*` keys). Inspect the live ConfigMap to
  see exactly which keys are present:

  ```bash
  kubectl get configmap oci-nccl-parameters -n default \
    -o jsonpath='{.data}' | tr ',' '\n'
  ```
