# Managing Slurm Topology on OKE

Slurm topology uses OCI RDMA locality to place workers close together.

The topology setting is enabled by default. It requires these stack options and resources:

- `install_slinky = true`
- `slinky_install_slurm_cluster = true`
- `install_oci_hpc_oke_utils = true`
- `install_rdma_labeler = true`
- At least one enabled Slurm worker pool

Workers need usable RDMA locality data from the instance metadata service (IMDS).
See [Using RDMA Network Locality on OKE](./using-rdma-network-locality-when-running-workloads-on-oke.md).

Workers without locality data use the synthetic `none` unit. These workers remain schedulable.

## How It Works

1. OCI HPC OKE Utils reads OCI locality data and labels each node.
2. Its controller generates `tree`, `block`, and `flat` topologies for Slurm.
3. The annotator assigns workers to topology units. Slurm reloads topology changes automatically.

| Topology | Purpose |
| --- | --- |
| `tree` | Models Local Block, Network Block, and HPC Island levels. |
| `block` | Groups workers by Local Block. |
| `flat` | Disables locality placement for CPU workers. |

The CPU partition always uses `flat`. GPU, RDMA, and GMC partitions use the selected default topology.

## Configuration

The default OKE path does not need a topology override.

| Variable | Default | Purpose |
| --- | --- | --- |
| `slinky_topology_enabled` | `true` | Enable Slurm topology management. |
| `slinky_topology_default` | `tree` | Select the default `tree` or `block` topology. |
| `slinky_topology_block_sizes` | `auto` | Derive block sizes or use a list such as `8,16,32`. |

To use the block topology, set this value and apply the stack again:

```hcl
slinky_topology_default = "block"
```

## Use Topology in Jobs

Slurm uses the selected topology when it allocates nodes. Most jobs do not need a topology option.

### Tree Topology

Use `--switches` to request a maximum number of Local Blocks.
Add a wait limit so the request does not delay the job without a bound.

```bash
sbatch --switches=1@00:05:00 my_job.sh
```

This example requests one Local Block and waits up to five minutes.
Slurm can use more Local Blocks after the wait limit expires.

### Block Topology

Use `--segment` to divide a node allocation into equal segments.

```bash
sbatch --nodes=4 --segment=2 my_job.sh
```

This example creates two segments with two nodes in each segment.
The node count must be divisible by the segment size.
The complete job does not have to stay in one block.

## Troubleshooting

Check the topology annotation on a worker:

```bash
kubectl get node "<node-name>" \
  -o jsonpath='{.metadata.annotations.topology\.slinky\.slurm\.net/spec}{"\n"}'
```

A worker with locality data shows `tree:root:isl-<island>:nb-<network-block>:lb-<local-block>,block:lb-<local-block>`.
A worker without usable locality data shows `tree:root:none,block:none`.

Check the generated topology file:

```bash
kubectl -n slurm get configmap slurm-config-extra \
  -o jsonpath='{.data.topology\.yaml}{"\n"}'
```

Check the topology loaded by Slurm:

```bash
kubectl -n slurm exec slurm-controller-0 -c slurmctld -- \
  scontrol show topology
```

If the generated file is stale, check the OCI HPC OKE Utils controller logs:

```bash
kubectl -n kube-system logs deployment/oci-hpc-oke-utils-controller
```

After a Helm upgrade, `topology.yaml` can temporarily contain bootstrap data.
OCI HPC OKE Utils restores the generated data within approximately two minutes.

## Disable Topology Management

Set `slinky_topology_enabled = false` and apply the stack again.

The apply removes `topology.yaml` and its reconfigure sidecar. It does not remove existing node annotations.

Remove the annotations if the workers continue to run:

```bash
kubectl annotate nodes \
  -l 'oke.oraclecloud.com/pool.name in (oke-gpu,oke-rdma,oke-gmc,oke-cpu)' \
  topology.slinky.slurm.net/spec-
```
