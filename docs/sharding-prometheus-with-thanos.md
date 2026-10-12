# Sharding Prometheus with Thanos

By default the stack runs a single Prometheus. Its memory grows with the number of active series, and a BM.GPU.B300.8 node exposes about 22k of them (node-exporter about 13k, cAdvisor about 5k). On large clusters one Prometheus pod eventually outgrows the system node it runs on.

Two settings address this:

- **Thanos (opt-in).** `install_thanos = true` lets you split Prometheus into shards. Thanos keeps one global view for Grafana and stores history in an OCI Object Storage bucket.
- **Prometheus memory.** `prometheus_memory` is set as both the request and the limit, and `prometheus_cpu` (default `1`) as the request. A Prometheus that outgrows its budget is OOM-killed inside its own cgroup instead of pushing the node into kubelet eviction, which can take out Kueue and other controllers on the same node. When `prometheus_memory` is empty (the default):
  - Without Thanos, no requests or limits are set, the stack's historical behavior.
  - With Thanos, it is calculated from the worker pools and `prometheus_shards` (see below).

  Set `prometheus_memory` explicitly to override it in either case.

## Sizing

With Thanos and an empty `prometheus_memory`, the stack estimates active series from the worker pool sizes. The constants were measured on a 16 × BM.GPU.B300.8 + 3 × VM.Standard.E5.Flex cluster (449k series predicted, 449k observed):

| Source | Active series |
| --- | --- |
| Each bare-metal node (`BM.*` shapes, RDMA and GMC pools) | ~23.6k (node-exporter, cAdvisor, kubelet, DCGM, and its share of kube-state-metrics and CoreDNS) |
| Each VM node | ~12.2k |
| Cluster-wide (API server, kube-state-metrics base, Grafana, operators) | ~35k |

Memory per Prometheus pod is then calculated as follows:

```
series_per_shard = total / prometheus_shards × 1.25   (hash sharding over few targets is uneven)
memory           = series_per_shard × 4.5 KB × 2 + 1 GiB, rounded up to whole GiB, at least 2Gi
```

The 4.5 KB is the measured working set per series. The factor of 2 leaves headroom for queries, WAL replay after restarts, head compaction, and series churn.

| Cluster | Shards | Memory per pod |
| --- | --- | --- |
| 16 × BM GPU + 3 system | 2 | 4Gi |
| 128 × BM GPU + 3 system | 6 | 7Gi |
| 512 × BM GPU + 3 system | 8 | 17Gi |
| 1024 × BM GPU + 3 system | 16 | 17Gi |

The `prometheus_sizing` output shows the estimate and the result.

Each Prometheus pod must also fit on a system or CPU pool node, because the GPU pools are tainted. If a pod plus its sidecar would take more than about 60% of such a node, the plan shows a warning with the number of shards that would fit. The default system pool is 3 × VM.Standard.E5.Flex with 16 GB, which allows about 9Gi per pod. Add shards, or raise `worker_ops_memory`.

The estimate uses the pool sizes in the stack. If nodes are added outside the stack, re-apply or set `prometheus_memory` explicitly.

## Enabling Thanos

```hcl
install_thanos      = true
prometheus_shards   = 2     # targets are split across shards by hash of their address
prometheus_replicas = 1     # per shard; 2 adds HA and doubles Object Storage writes
# prometheus_memory = "16Gi"  # optional; calculated from the worker pools when empty
```

This deploys:

| Component | Where | Notes |
| --- | --- | --- |
| Thanos sidecar | each Prometheus pod | uploads a TSDB block every 2 hours |
| Thanos Query | `files/thanos` chart, 2 replicas | Grafana's `Prometheus` datasource (uid `prometheus`) now points here; dashboards and alerts are unchanged |
| Store Gateway | `files/thanos` chart | serves the blocks in the bucket |
| Compactor | `files/thanos` chart | compacts, downsamples to 5m and 1h, applies `thanos_retention_raw`, `_5m`, `_1h` (30d / 90d / 365d) |
| Thanos Ruler | kube-prometheus-stack `thanosRuler` | evaluates the rules that need the global view (see below) |

The stack also creates:

- A private bucket `oke-gpu-<state_id>-thanos`. To use an existing bucket instead, set `thanos_bucket_name`.
- An IAM policy that grants the bucket to the `thanos` and `kube-prometheus-stack-prometheus` ServiceAccounts through OKE workload identity. There are no keys or secrets with credentials. With `create_policies = false`, the `thanos_policy_statements` output lists the statements an administrator must create.

Install order matters and is handled by the stack: bucket and policy, then a 5-minute wait for IAM propagation, then the `thanos` chart (which creates the objstore Secret and Thanos Query), then kube-prometheus-stack.

Use Thanos Query, not the Prometheus Service, for ad hoc queries: with shards, the `kube-prometheus-stack-prometheus` Service sends each request to one shard. The `prom_server_port_forward` output points at `thanos-query` when Thanos is enabled.

## Recording rules across shards

Each shard evaluates rules over only the targets it scrapes. A rule that reads a single target type (the API server, kube-state-metrics, or one exporter per node) stays correct. A rule that joins series from different targets would silently produce partial results. For example, `node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate` joins cAdvisor on every kubelet with `kube_pod_info` from kube-state-metrics.

Label such a `PrometheusRule` with `thanos-ruler: "true"`. The Prometheus shards then skip it and the Thanos Ruler evaluates it against Thanos Query. The stack labels `k8s-container-resource-rules` this way.

## Object Storage usage

Measured on a 16 × BM.GPU.B300.8 cluster (about 910 stored samples/s per node):

| Per BM.GPU.B300.8 node | |
| --- | --- |
| Uploaded by the sidecars | ~161 MB/day |
| Stored after 30 days | ~5.2 GB |
| Stored at full retention (30d raw, 90d 5m, 365d 1h) | ~10 GB |

Downsampled data is kept alongside the raw data, so it only saves space when `thanos_retention_raw` is shorter than the 5m and 1h retentions. Requests are dominated by the Compactor and Store Gateway polling block metadata. That scales with the number of blocks in the bucket (shards and retention), not with the number of nodes.

## Enabling Thanos on an existing cluster

Applying with `install_thanos = true` updates the running Prometheus in place. Shard 0 keeps its volume and history, and the new shards start empty. History on the existing volume stays queryable through the sidecar until it ages out of `prometheus_retention`.

To move it into the bucket, apply once with `thanos_upload_existing_blocks = true`, then set it back to `false`. This can upload up to the full size of the Prometheus volume.

## Destroy

On destroy, or when `install_thanos` is turned off, the stack empties and deletes the bucket it created. It deletes all objects and aborts any uncommitted multipart uploads, which would otherwise block the bucket deletion. A bucket passed in `thanos_bucket_name` is left untouched.
