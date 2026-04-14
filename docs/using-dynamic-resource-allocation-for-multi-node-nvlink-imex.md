# Using Dynamic Resource Allocation (DRA) for Multi-Node NVLink

The [`manifests/nccl-tests/kueue/`](../manifests/nccl-tests/kueue/) directory contains NCCL test manifests for various OCI GPU shapes. The GB200 and GB300 shapes use Dynamic Resource Allocation (DRA) to orchestrate Multi-Node NVLink (MNNVL). Other shapes (H100, H200, B200, B300, A100) do not, because MNNVL only applies to GB200/GB300 NVL systems.

This guide explains what DRA pieces appear in those manifests, why they are there, and how to adapt them.

## When DRA is required

DRA is required for workloads that share GPU memory across nodes over NVLink (MNNVL). On OCI this currently means:

- `BM.GPU.GB200.4`
- `BM.GPU.GB200-v2.4`
- `BM.GPU.GB200-v3.4`
- `BM.GPU.GB300.4`

For shapes without MNNVL (A100, H100, H200, B200, B300), DRA is not needed. Those manifests request GPUs via the classic `nvidia.com/gpu` resource limit only.

## Prerequisites

- Kubernetes 1.32 or newer with the DRA feature gate enabled (default on recent OKE).
- The [NVIDIA DRA driver](https://github.com/kubernetes-sigs/dra-driver-nvidia-gpu) (`dra-driver-nvidia-gpu`) **v25.8.0 or newer** installed in the cluster. This driver provides the `resource.nvidia.com/v1beta1` API group (`ComputeDomain`) and the IMEX daemon/channel machinery under the hood. `numNodes: 0`, used by all DRA manifests here, requires v25.8.0+.
- For MNNVL workloads, the underlying hardware fabric (NVLink Switch / IMEX) must be operational on the selected node pool.

## The building blocks

A DRA-enabled MNNVL manifest uses three pieces that work together:

### 1. `ComputeDomain` (cluster-managed IMEX domain)

```yaml
apiVersion: resource.nvidia.com/v1beta1
kind: ComputeDomain
metadata:
  name: bm-gpu-gb200-v3.4-nccl-tests-compute-domain
spec:
  numNodes: 0
  channel:
    resourceClaimTemplate:
      name: bm-gpu-gb200-v3.4-nccl-tests-compute-domain-channel
```

A `ComputeDomain` represents a secure, ephemeral MNNVL boundary. Pods inside the same domain can share GPU memory over NVLink. Pods outside cannot reach in.

Two fields matter:

- **`spec.numNodes`**: set to `0`. The driver uses DNS names and does not gate pod startup on IMEX peer discovery. The workload itself waits for peers to become reachable (for example, the `Launcher` container in these manifests SSH-probes all workers before invoking `mpirun`). Requires DRA driver **v25.8.0 or newer**.
- **`spec.channel.resourceClaimTemplate.name`**: name of the `ResourceClaimTemplate` the driver creates for allocating IMEX channels.

### 2. Pod `resourceClaims` (reference to the template)

Each worker pod declares that it wants a channel from the template:

```yaml
spec:
  containers:
  - name: mpi-worker
    resources:
      limits:
        nvidia.com/gpu: 4
      claims:
      - name: compute-domain-channel
  resourceClaims:
  - name: compute-domain-channel
    resourceClaimTemplateName: bm-gpu-gb200-v3.4-nccl-tests-compute-domain-channel
```

Two coordinated references:

- `spec.resourceClaims[].name` is a pod-local alias for the claim.
- `spec.resourceClaims[].resourceClaimTemplateName` points at the template the `ComputeDomain` generates (matches `channel.resourceClaimTemplate.name` above).
- `spec.containers[].resources.claims[].name` wires the alias into the container so the kubelet injects the channel device into that container.

The classic `nvidia.com/gpu` limit is still required. DRA handles only the IMEX channel; GPUs themselves are still requested the normal way in these manifests.

### 3. Workload readiness check

With `numNodes: 0`, pods are admitted as soon as their local IMEX daemon is up; they do not wait for peers. The workload itself must confirm that all peers are online before triggering any cross-node IMEX interaction (cross-node GPU memory sharing). How you do this depends on the launcher:

- **mpirun-based workloads**: need an explicit check, because `mpirun` will try to SSH into unready workers and fail. For example, the four NCCL manifests in [`manifests/nccl-tests/kueue/`](../manifests/nccl-tests/kueue/) use an SSH probe loop in the launcher before invoking `mpirun`:

  ```bash
  while ! (for host in $(awk '{print $1}' /etc/mpi/hostfile); do \
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p 2222 $host exit 2>/dev/null || exit 1; \
  done); do
    echo "Waiting for workers to be ready..."
    sleep 5
  done
  ```

- **torchrun / PyTorch Elastic**: the built-in rendezvous already waits for all ranks to join before training starts. No extra wait loop needed.
- **MPI with a built-in startup barrier** (for example, PMIx rendezvous): also covered by the launcher itself.

## Naming conventions used here

DRA object names in these manifests follow a predictable scheme keyed off the shape name:

| Piece                          | Example (GB200-v3.4)                                      |
|--------------------------------|-----------------------------------------------------------|
| `ComputeDomain` name           | `bm-gpu-gb200-v3.4-nccl-tests-compute-domain`             |
| `ResourceClaimTemplate` name   | `bm-gpu-gb200-v3.4-nccl-tests-compute-domain-channel`     |
| Pod-local claim alias          | `compute-domain-channel`                                  |

When creating a manifest for a new MNNVL shape, keep this scheme so the four references stay consistent: `ComputeDomain.spec.channel.resourceClaimTemplate.name` must equal `pod.spec.resourceClaims[].resourceClaimTemplateName`, and `pod.spec.resourceClaims[].name` must equal `container.resources.claims[].name`.

## Adapting a manifest for a new MNNVL shape

1. Copy the closest existing DRA-enabled manifest (prefer [`BM.GPU.GB300.4.yaml`](../manifests/nccl-tests/kueue/BM.GPU.GB300.4.yaml) or [`BM.GPU.GB200-v3.4.yaml`](../manifests/nccl-tests/kueue/BM.GPU.GB200-v3.4.yaml)).
2. Replace the shape name everywhere: `ResourceFlavor.spec.nodeLabels`, `nodeSelector`, queue names, and the DRA object names.
3. Set `Worker.replicas` to the number of nodes you want to exercise. Leave `ComputeDomain.spec.numNodes` at `0`.
4. Update NCCL and mpirun flags as appropriate for the shape (NIC list, `NCCL_NET_PLUGIN`, `NCCL_NVLS_ENABLE`, and so on). These differ per-shape and are not DRA-related.
5. Verify the DRA driver is installed and reports the target nodes as schedulable for the channel device class before applying.

## Troubleshooting

- **Worker pods stuck in `ContainerCreating`**: check the DRA driver pods (`kubectl get pods -n <dra-driver-ns>`) and the node's kubelet plugin socket.
- **`ResourceClaim` not found**: confirm the `ComputeDomain` was created and that `channel.resourceClaimTemplate.name` matches the pod's `resourceClaimTemplateName` exactly.
- **`mpirun` fails with NCCL errors after pods start**: MNNVL fabric is probably not ready. The launcher's SSH wait loop only proves workers are reachable, not that the IMEX mesh is complete. Retry, and check IMEX daemon logs on the worker nodes.
