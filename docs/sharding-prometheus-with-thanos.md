# Sharding Prometheus with Thanos

By default the stack runs a single Prometheus on the system pool, with no memory requests or limits. Its memory grows with the number of active series, and a BM.GPU.B300.8 node exposes about 22k of them (node-exporter about 13k, cAdvisor about 5k). On large clusters one Prometheus outgrows the system node it runs on. It can then starve, or get controllers such as Kueue evicted, on the same node.

`install_thanos = true` addresses this:

- **Sharding.** Scrape targets are split across Prometheus shards by hash. Thanos keeps one global view for Grafana and stores history in an OCI Object Storage bucket.
- **Automatic sizing.** The stack estimates active series from the worker pools, then picks the number of shards, the memory per Prometheus pod (request equals limit), and the monitoring pool size.
- **A dedicated monitoring pool.** Prometheus, Thanos, Grafana and kube-state-metrics run on a tainted node pool sized for them, isolated from the system pool. It is always created with Thanos.

Thanos is off by default, and without it nothing changes: one Prometheus on the system pool with no requests or limits, no monitoring pool, and no bucket.

## Layout

| Component | Notes |
| --- | --- |
| Prometheus shards + Thanos sidecar | uploads a TSDB block every 2 hours |
| Thanos Query (2 replicas) | Grafana's `Prometheus` datasource (uid `prometheus`) points here; dashboards and alerts are unchanged |
| Thanos Store Gateway, Compactor | serve the bucket; compact, downsample, and apply `thanos_retention_raw` / `_5m` / `_1h` (30d / 90d / 365d) |
| Thanos Ruler | evaluates the rules that need the global view (see below) |

These, Grafana and kube-state-metrics run on a dedicated pool, `oke-monitoring`, with one Prometheus pod per node. The pool has these properties:

- Its nodes carry the label `oci.oraclecloud.com/monitoring=true` and the taint `oci.oraclecloud.com/monitoring=true:NoSchedule`.
- It has one node per Prometheus pod (shards × replicas) plus a spare, so a shard can reschedule when a node is lost or cycled.
- It uses the system pool's image, availability domain (where the Prometheus and Grafana volumes live), and node cycling settings.
- node-exporter, CSI and CNI tolerate the taint. OKE's own node-problem-detector and observability agent don't, so they don't run on these nodes.
- The pool's size and node memory are calculated (see Sizing); set `worker_monitoring_pool_size` or `worker_monitoring_memory` to override.

After installing kube-prometheus-stack, the apply waits until every shard and replica is available. If a shard can't schedule, the apply fails and shows the Pending pods, instead of silently dropping that shard's targets.

## Sizing

The series estimate comes from the worker pool sizes. The constants were measured on a 16 × BM.GPU.B300.8 + 3 × VM.Standard.E5.Flex cluster (449k series predicted, 449k observed):

| Source | Active series |
| --- | --- |
| Each bare-metal node (`BM.*` shapes, RDMA and GMC pools) | ~23.6k (node-exporter, cAdvisor, kubelet, DCGM, and its share of kube-state-metrics and CoreDNS) |
| Each VM node | ~12.2k |
| Cluster-wide (API server, kube-state-metrics base, Grafana, operators) | ~35k |

Shards, memory and nodes are then calculated as follows:

```
shards       = 1 if series <= target, else ceil(series × 1.25 / prometheus_target_series_per_shard)   (target 3M)
memory/pod   = series / shards × 1.25 × 4.5 KB × 2 + 1 GiB, whole GiB, at least 2Gi
pool nodes   = shards × replicas + 1
node memory  = (memory/pod + 0.5Gi sidecar + ~6.5Gi DaemonSets and Thanos) / 0.84, in 8 GB steps, at least 16 GB
```

The constants:

- The 1.25 allows for uneven hash sharding.
- 4.5 KB is the measured working set per series.
- The factor of 2 leaves headroom for queries, WAL replay after restarts, head compaction, and series churn.
- 0.84 is the allocatable fraction of a node's memory.

| Bare-metal GPU nodes (+3 system) | Shards | Memory per Prometheus pod | Monitoring pool |
| --- | --- | --- | --- |
| 16 | 1 | 5Gi | 2 × 16 GB |
| 128 | 2 | 18Gi | 3 × 32 GB |
| 512 | 6 | 23Gi | 7 × 40 GB |
| 1024 | 11 | 25Gi | 12 × 40 GB |

The `prometheus_sizing` output shows the estimate and every derived value. Each can be set explicitly: `prometheus_shards`, `prometheus_memory`, `worker_monitoring_pool_size`, `worker_monitoring_memory`.

A lower `prometheus_target_series_per_shard` gives more, smaller shards: for example, 1.5M gives 21 × 14Gi at 1024 nodes. That means a smaller gap when one shard is down. The costs are more sidecars, more blocks, and more Object Storage requests, because metadata polling scales with the number of blocks.

The estimate uses the pool sizes in the stack. If nodes are added outside the stack, re-apply or set the values explicitly. Changing the shard count reassigns most targets to different shards, so memory rises for a while as the new owners pick up their series. History stays in the bucket.

## Enabling Thanos

```hcl
install_thanos = true   # also creates the monitoring pool
# Optional overrides; everything below is calculated when left at 0 or empty.
# prometheus_shards           = 0
# prometheus_replicas         = 1      # 2 adds HA, doubles Object Storage writes and Prometheus nodes
# prometheus_memory           = ""
# worker_monitoring_pool_size = 0
# worker_monitoring_memory    = 0
```

The stack also creates:

- A private bucket `oke-gpu-<state_id>-thanos`. To use an existing bucket instead, set `thanos_bucket_name`.
- An IAM policy that grants the bucket to the `thanos` and `kube-prometheus-stack-prometheus` ServiceAccounts through OKE workload identity. There are no keys or secrets with credentials. With `create_policies = false`, the `thanos_policy_statements` output lists the statements an administrator must create.

Install order is handled by the stack: bucket and policy, then a 5-minute wait for IAM propagation, then the `thanos` chart (which creates the objstore Secret and Thanos Query), then kube-prometheus-stack.

Use Thanos Query, not the Prometheus Service, for ad hoc queries: with shards, the `kube-prometheus-stack-prometheus` Service sends each request to one shard. The `prom_server_port_forward` output points at `thanos-query` when Thanos is enabled.

The monitoring taint is applied by the node bootstrap script (`files/oke-ubuntu-cloud-init.sh`, which nodes download from `main`). Until a branch with that change is merged, nodes in the monitoring pool come up untainted. The node selectors still place the monitoring pods there, but other pods may also schedule on those nodes.

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

Applying with `install_thanos = true` creates the monitoring pool and moves Prometheus, Grafana and kube-state-metrics there, in the same AD, so their volumes reattach. Shard 0 keeps its volume and history, and the new shards start empty. History on the existing volume stays queryable through the sidecar until it ages out of `prometheus_retention`.

To move it into the bucket, apply once with `thanos_upload_existing_blocks = true`, then set it back to `false`. This can upload up to the full size of the Prometheus volume.

## Destroy

On destroy, or when `install_thanos` is turned off, the stack empties and deletes the bucket it created. It deletes all objects and aborts any uncommitted multipart uploads, which would otherwise block the bucket deletion. A bucket passed in `thanos_bucket_name` is left untouched. The monitoring pool is removed with Thanos.
