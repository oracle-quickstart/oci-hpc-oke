# Monitoring Kueue workloads

The stack reuses its existing Prometheus and Grafana installation for Kueue.
With `install_kueue=true`, monitoring adds a ServiceMonitor for Kueue's HTTPS
metrics Service, kube-state-metrics metadata for Workloads, and a recording rule
that connects Workloads to their pods and hosts.

The **Kueue Workloads** dashboard is built and provisioned only when Kueue is
selected and Grafana dashboards are enabled. It appears in the **Kubernetes**
folder, with UID `oke-kueue-workloads`. Setting `install_kueue=false` skips
compilation of its Jsonnet source and removes its provisioned ConfigMap in both
provider and operator deployments.

## From a job to its resources

1. Select the **Namespace** and **LocalQueue**. The **Workloads and owning jobs**
   table includes queued workloads as well as admitted workloads.
2. Click a job name to focus the dashboard on that workload, or select it in
   the **Workload** dropdown.
3. Inspect **Workload conditions** and **Job → pods → hosts**. The latter includes
   CPU-only launcher pods as well as GPU workers.
4. Click a hostname to open the existing **GPU Metrics** or **Host Metrics**
   dashboard for that host.
5. Use the dashboard's top links to inspect all selected hosts together. The
   existing dashboards accept multiple hosts, despite their `-single` UIDs.
   The links preserve the time range and reset unrelated shape/display-name
   filters. The Host dropdown expands All to the workload's actual host list.

The **ClusterQueue** selector controls the queue overview independently of the
workload selectors. This allows queued workloads to remain visible before they
have a ClusterQueue admission assignment. That assignment is empty in the
workload table until quota is reserved.

## Metrics and interpretation

| View | Source | Interpretation |
| --- | --- | --- |
| Controller health | Prometheus `up`, Kubernetes deployment replicas | Scrape availability and controller readiness. |
| Queue backlog | `kueue_pending_workloads` | Active and inadmissible workloads by ClusterQueue. |
| Admission and completions | Kueue counters | Rates of admissions, completions and evictions. |
| Admission wait p95 | Kueue admission histogram | Historical waits of workloads that reached admission; excludes jobs still waiting. |
| Workload identity and conditions | kube-state-metrics custom resource metrics | Namespace, queue, owner, and Kueue condition state. |
| Job-to-host map | `oke:kueue_workload_pod:info` | Workload ownership joined to scheduled pods and node names. |
| Requested GPUs | Pod resource requests joined to the map | Requested NVIDIA or AMD GPUs for the workload's scheduled pods. |
| Measured CPU and memory | cAdvisor metrics joined to the map | Resource usage of containers belonging to those pods. |
| Host GPU and CPU utilization | GPU exporters and node-exporter | All activity on those hosts, including other jobs and system services. |

The ownership map supports pods directly controlled by a Workload's owner
(including batch Jobs, MPIJobs and PyTorchJobs), plus pods controlled by a child
batch Job whose owner is the Workload's owner. Other ownership hierarchies,
such as some Ray or JobSet layouts, need additional mappings. No job-name
prefix guessing or pod-label wildcard allowlist is used.

Pending workloads without scheduled pods have no host resource mapping. Once
pods are deleted, the live map disappears; historical recording-rule data
remains in Prometheus retention, but current dropdowns are intended for live
workloads. These views do not provide per-job GPU attribution on shared hosts.

## Alerts

When Grafana alerting is enabled, the stack adds two alerts after five minutes:

- **Kueue controller unavailable:** no available controller replicas.
- **Kueue metrics unavailable:** no successfully scraped Kueue endpoint.

They use the existing `ons-webhook` contact point. Disabling Kueue provisions
cleanup directives for these rules. Queue backlog alone does not trigger an
alert because waiting can be expected when resources are busy.

## Verify on a cluster

```bash
MONITORING_NAMESPACE=monitoring
kubectl get servicemonitor kueue -n "${MONITORING_NAMESPACE}"
kubectl get configmap dashboard-kueue -n "${MONITORING_NAMESPACE}"
kubectl get workloads.kueue.x-k8s.io -A
```

In Prometheus or Grafana Explore, check:

```promql
up{namespace="kueue-system",service="kueue-controller-manager-metrics-service"}
oke_kueue_workload_owner_info
oke:kueue_workload_pod:info
```

Submit a single-host and multi-host job, verify the pod/host table against
`kubectl get pods -o wide`, and open both host links. Check the selected node
names and time range in the destination dashboards. For missing mappings,
inspect `kube_pod_owner`, `kube_job_owner`, and the Workload's ownerReferences.

For a manual monitoring installation, set `KUEUE_MONITORING=true` in the
[manual monitoring guide](./deploying-monitoring-stack-manually.md).

## Development validation

```bash
make -C terraform/files/grafana/jsonnet verify
python3 test/kueue-monitoring/test_renderer.py
```

`make verify` compiles Kueue explicitly for validation. Ordinary `make compile`
skips it unless `INCLUDE_KUEUE=true` is passed. Terraform supplies
`install_kueue` to the renderer automatically.

The Prometheus fixture in `test/kueue-monitoring/workload-resources.test.yaml`
tests single-host and multi-host mapping, child batch Jobs, namespace isolation,
unscheduled pods, duplicate scrapes, and GPU requests. To run it, extract the
`kueue-workload-resources` group from the rendered monitoring values into
`rules.json` beside a temporary copy of the fixture, then run
`promtool test rules workload-resources.test.yaml` there.

Upstream references: [Kueue metrics setup](https://kueue.sigs.k8s.io/docs/tasks/manage/observability/setup_prometheus/)
and [kube-state-metrics custom resource configuration](https://github.com/kubernetes/kube-state-metrics/blob/main/docs/metrics/extend/customresourcestate-metrics.md).
