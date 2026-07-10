# Using the NCCL/RCCL Parameters ConfigMap in Job Manifests

## Overview

When the cluster is deployed with RDMA or GPU Memory Cluster (GMC) worker pools, Terraform
creates one ConfigMap in the `default` namespace for each distinct supported
shape. Each ConfigMap holds a single `nccl.conf` key: the recommended NCCL/RCCL
tuning parameters from
[recommended-nccl-rccl-parameters-by-shape.md](./recommended-nccl-rccl-parameters-by-shape.md),
one `KEY=value` line per parameter. NCCL reads `/etc/nccl.conf`, while RCCL
reads `/etc/rccl.conf`. Both libraries read their file at initialization, and
environment variables take precedence over anything set in the file, so a
per-job `export` or `-x` still wins.

The ConfigMap name includes the GPU vendor and normalized shape:

- `oci-nccl-parameters-<shape>` for NVIDIA shapes
- `oci-rccl-parameters-<shape>` for AMD shapes

The shape is lowercase with dots replaced by hyphens. For example,
`BM.GPU.H100.8` uses `oci-nccl-parameters-bm-gpu-h100-8`, while
`BM.GPU.MI300X.8` uses `oci-rccl-parameters-bm-gpu-mi300x-8`. The examples below
use an NVIDIA H100 cluster.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: oci-nccl-parameters-bm-gpu-h100-8
  namespace: default
data:
  nccl.conf: |
    NCCL_CUMEM_ENABLE=0
    NCCL_DEBUG=WARN
    NCCL_IB_GID_INDEX=3
    NCCL_IB_HCA==mlx5_0,mlx5_1,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_9,mlx5_10,mlx5_12,mlx5_13,mlx5_14,mlx5_15,mlx5_16,mlx5_17
    NCCL_IB_SL=0
    NCCL_IB_SPLIT_DATA_ON_QPS=0
    NCCL_IB_TC=41
    NCCL_IB_TIMEOUT=22
    NCCL_IGNORE_CPU_AFFINITY=1
    NCCL_SOCKET_IFNAME=eth0
```

The ConfigMaps are controlled by the `deploy_nccl_rccl_param_configmap`
Terraform variable (default `true`). A ConfigMap is created for every distinct
enabled RDMA or GMC shape covered by the parameter set. If both pools use the
same shape, Terraform creates one ConfigMap for that shape.

Verify it exists:

```bash
kubectl get configmap oci-nccl-parameters-bm-gpu-h100-8 -n default -o yaml
```

## Quickstart

For an NCCL pod, mount the ConfigMap at `/etc/nccl.conf` with `subPath`:

```yaml
containers:
- name: my-container
  volumeMounts:
  - name: nccl-conf
    mountPath: /etc/nccl.conf
    subPath: nccl.conf
volumes:
- name: nccl-conf
  configMap:
    name: oci-nccl-parameters-bm-gpu-h100-8
```

For an RCCL pod, use the same ConfigMap key and volume but mount it at
`/etc/rccl.conf`:

```yaml
containers:
- name: my-container
  volumeMounts:
  - name: rccl-conf
    mountPath: /etc/rccl.conf
    subPath: nccl.conf
volumes:
- name: rccl-conf
  configMap:
    name: oci-rccl-parameters-bm-gpu-mi300x-8
```

Each library reads its own file at process startup, so this works regardless of
how the process was launched (directly, over SSH, or under Pyxis), with no
extra environment wiring.

For an MPIJob the ranks run in the **worker** pods (`mpirun` launches them over
SSH), so mount the ConfigMap into the worker container the same way. Each
`sshd`-spawned rank process reads `/etc/nccl.conf` on its own at NCCL
initialization, so no environment forwarding through the SSH session is
required:

```yaml
          containers:
          - name: mpi-worker
            volumeMounts:
            - name: nccl-conf
              mountPath: /etc/nccl.conf
              subPath: nccl.conf
            command:
            - /bin/bash
            - -c
            - mkdir -p /var/run/sshd; /usr/sbin/sshd -D -p 2222;
          volumes:
          - name: nccl-conf
            configMap:
              name: oci-nccl-parameters-bm-gpu-h100-8
```

## Slurm (Slinky) clusters

Slurm worker NodeSets mount their own shape's ConfigMap automatically at both
`/etc/nccl.conf` (NCCL) and `/etc/rccl.conf` (RCCL), so `sbatch` and `srun`
jobs pick up the parameters without any manifest or submission-environment
changes, whichever library the job links against. Per-job exports still
override them. Multi-pool clusters (for example separate RDMA and GMC
shapes) get the correct file for each pool.

Containerized Pyxis job steps run in the container filesystem, which does not
include the worker pod's mounted files, so add
`--container-mounts=/etc/nccl.conf` (NCCL) or `--container-mounts=/etc/rccl.conf`
(RCCL) (or include the path in an existing `--container-mounts` list) to bind
in whichever file the job's library reads.

Changing a shape's parameters updates the ConfigMap, but Kubernetes does not
refresh a `subPath` mount on its own. The worker NodeSet carries a hash of
the ConfigMap contents as a pod annotation, so a parameter change rolls the
affected worker pods automatically; no manual restart is needed.

## Worked example: BM.GPU.H100.8 NCCL test

The sample manifest
[manifests/nccl-tests/kueue/BM.GPU.H100.8.yaml](../manifests/nccl-tests/kueue/BM.GPU.H100.8.yaml)
hard-codes the parameters as inline `mpirun -x VAR=value` flags. To drive it from
the ConfigMap instead, make two changes.

### 1. Mount the ConfigMap into the worker pods

Add a `nccl-conf` volume and mount it into the worker container at
`/etc/nccl.conf`.

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
            volumeMounts:
            - name: nccl-conf
              mountPath: /etc/nccl.conf
              subPath: nccl.conf
            command:
              - /bin/bash
              - -c
              - mkdir -p /var/run/sshd; /usr/sbin/sshd -D -p 2222;
          volumes:
          - name: nccl-conf
            configMap:
              name: oci-nccl-parameters-bm-gpu-h100-8
```

Every rank process (started directly or over the SSH session `mpirun` opens)
reads `/etc/nccl.conf` on its own; there is no relay step.

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
test-harness tuning, not device settings. On a non-VF cluster `NCCL_IB_HCA`
resolves to the full device list; on a VF cluster it resolves to `mlx5`, with
no manifest change.

## Consuming from non-MPI pods (PyTorch, torchrun, custom launchers)

Processes that read NCCL settings directly from the environment or from
`/etc/nccl.conf` (for example a `torchrun` job) only need the same volume
mount as the Quickstart, on the pod that runs the training process:

```yaml
spec:
  containers:
  - name: trainer
    image: ...
    volumeMounts:
    - name: nccl-conf
      mountPath: /etc/nccl.conf
      subPath: nccl.conf
    command: ["torchrun", "..."]
  volumes:
  - name: nccl-conf
    configMap:
      name: oci-nccl-parameters-bm-gpu-h100-8
```

## Notes and caveats

- Namespace. The ConfigMaps live in `default`. A ConfigMap volume only
  resolves in the same namespace as the pod, so run the job in `default`, or
  copy the required ConfigMap into the job's namespace:

  ```bash
  kubectl get configmap oci-nccl-parameters-bm-gpu-h100-8 -n default -o json \
    | jq '
        del(
          .metadata.uid,
          .metadata.resourceVersion,
          .metadata.creationTimestamp,
          .metadata.managedFields,
          .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration"
        )
        | .metadata.namespace = "<your-namespace>"
      ' \
    | kubectl apply -f -
  ```

- Virtual functions need more than the config file. The ConfigMap sets
  `NCCL_IB_HCA` to `mlx5` when VFs are enabled, but a VF workload still needs
  the SR-IOV pieces the standard manifest does not have: the
  `k8s.v1.cni.cncf.io/networks: rdma-vf,...` pod annotation and the
  `nvidia.com/rdma-vf` resource requests. See the manifests under
  [manifests/nccl-tests/kueue/virtual-functions/](../manifests/nccl-tests/kueue/virtual-functions/)
  for the full VF layout. The ConfigMap handles the parameter values; it does not
  change pod networking or resources.

- Override a single value. NCCL and RCCL read environment variables before
  `/etc/nccl.conf` and `/etc/rccl.conf`, respectively. An explicit `env:` entry
  or an inline `-x VAR=value` for the same variable therefore takes precedence,
  overriding one parameter while inheriting the rest from the file.

- Available keys vary by shape. Each shape's `nccl.conf` carries only the
  parameters listed for it in
  [recommended-nccl-rccl-parameters-by-shape.md](./recommended-nccl-rccl-parameters-by-shape.md)
  (for example AMD shapes include `RCCL_*` keys). Inspect the live ConfigMap to
  see exactly which keys are present:

  ```bash
  kubectl get configmap oci-nccl-parameters-bm-gpu-h100-8 -n default \
    -o jsonpath='{.data.nccl\.conf}'
  ```

## Creating the ConfigMap manually

Create it yourself when Terraform does not: `deploy_nccl_rccl_param_configmap`
is `false`, the shape is not in the parameter set, or you want the ConfigMap in
a namespace other than `default`.

1. Look up the parameters for your shape in
   [recommended-nccl-rccl-parameters-by-shape.md](./recommended-nccl-rccl-parameters-by-shape.md),
   one `KEY=value` line per parameter.
2. Name it `oci-nccl-parameters-<shape>` on NVIDIA shapes or
   `oci-rccl-parameters-<shape>` on AMD shapes. Convert the shape to lowercase
   and replace dots with hyphens.
3. For `NCCL_IB_HCA`, use the shape's full device list on a non-VF cluster, or
   `mlx5` when SR-IOV virtual functions are enabled for that shape.

Apply the manifest (NVIDIA H100 example; swap in your shape's keys and
namespace):

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: oci-nccl-parameters-bm-gpu-h100-8
  namespace: default
data:
  nccl.conf: |
    NCCL_CUMEM_ENABLE=0
    NCCL_DEBUG=WARN
    NCCL_IB_GID_INDEX=3
    NCCL_IB_HCA==mlx5_0,mlx5_1,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_9,mlx5_10,mlx5_12,mlx5_13,mlx5_14,mlx5_15,mlx5_16,mlx5_17
    NCCL_IB_SL=0
    NCCL_IB_SPLIT_DATA_ON_QPS=0
    NCCL_IB_TC=41
    NCCL_IB_TIMEOUT=22
    NCCL_IGNORE_CPU_AFFINITY=1
    NCCL_SOCKET_IFNAME=eth0
EOF
```

Or build it from a file without writing YAML:

```bash
cat > nccl.conf <<'EOF'
NCCL_CUMEM_ENABLE=0
NCCL_DEBUG=WARN
NCCL_IB_GID_INDEX=3
NCCL_IB_HCA==mlx5_0,mlx5_1,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_9,mlx5_10,mlx5_12,mlx5_13,mlx5_14,mlx5_15,mlx5_16,mlx5_17
NCCL_IB_SL=0
NCCL_IB_SPLIT_DATA_ON_QPS=0
NCCL_IB_TC=41
NCCL_IB_TIMEOUT=22
NCCL_IGNORE_CPU_AFFINITY=1
NCCL_SOCKET_IFNAME=eth0
EOF

kubectl create configmap oci-nccl-parameters-bm-gpu-h100-8 -n default \
  --from-file=nccl.conf=nccl.conf
```

The leading `=` in `NCCL_IB_HCA` is the NCCL exact-name-match prefix, not a typo;
keep it. For a VF cluster, replace the whole device list with the single value
`mlx5`.
