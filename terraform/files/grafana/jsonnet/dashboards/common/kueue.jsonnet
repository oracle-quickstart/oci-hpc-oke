local panel = import '../../lib/dashboard-panel.libsonnet';
local target = import '../../lib/dashboard-target.libsonnet';
local variable = import '../../lib/dashboard-variable.libsonnet';
local g = import '../../lib/g.libsonnet';
local ds = { type: 'prometheus', uid: 'prometheus' };
local scope = 'namespace=~"$namespace",local_queue=~"$local_queue",workload=~"$workload"';
local pods = 'oke:kueue_workload_pod:info{' + scope + ',hostname=~"$hostname"}';
local cq = 'cluster_queue=~"$cluster_queue",replica_role!="follower"';
local v(name, query, label, regex='') = variable.query(name, ds, query, {
  label: label,
  definition: query,
  refresh: 2,
  multi: true,
  includeAll: true,
  current: { text: 'All', value: '$__all' },
  regex: regex,
  sort: 1,
});
local q(expr, legend='', table=false) = target.prometheus('prometheus', expr, {
  refId: 'A',
  instant: table,
  range: !table,
  format: if table then 'table' else 'time_series',
  legendFormat: legend,
});
local chart(title, expr, legend, x, y, id, unit='short', description='', width=12) =
  panel.timeSeries(title, [q(expr, legend)], { w: width, h: 7, x: x, y: y }, id, {
    datasource: ds,
    description: description,
    fieldConfig: { defaults: { unit: unit, min: 0 }, overrides: [] },
  });
local stat(title, expr, x, id, health=false) = panel.stat(title, [q(expr, table=true)], { w: 6, h: 4, x: x, y: 0 }, id, {
  datasource: ds,
  fieldConfig: {
    defaults: { unit: 'short', decimals: 0 } + (if health then {
                                                  color: { mode: 'thresholds' },
                                                  thresholds: { mode: 'absolute', steps: [{ color: 'red', value: null }, { color: 'green', value: 1 }] },
                                                } else {}),
    overrides: [],
  },
});
local nodeLink(uid, title, host) = {
  title: title,
  url: '/d/' + uid + '?var-PROMETHEUS_DS=prometheus&var-instance_shape=%24__all&var-oci_name=%24__all&' + host + '&from=${__from}&to=${__to}',
  targetBlank: true,
};
local table(title, expr, y, id, description='', links=false, jobLinks=false) =
  panel.table(title, [q(expr, table=true)], { w: 24, h: 8, x: 0, y: y }, id, {
    datasource: ds,
    description: description,
    fieldConfig: {
      defaults: {},
      overrides: (if links then [{
                    matcher: { id: 'byName', options: 'hostname' },
                    properties: [{ id: 'links', value: [
                      nodeLink('gpu-metrics-single', 'GPU metrics on this host', 'var-hostname=${__value.raw}'),
                      nodeLink('host-metrics-single', 'Host metrics on this host', 'var-hostname=${__value.raw}'),
                    ] }],
                  }] else []) + (if jobLinks then [{
                                   matcher: { id: 'byName', options: 'owner_name' },
                                   properties: [{ id: 'links', value: [{
                                     title: 'Inspect this job and its resources',
                                     url: '/d/oke-kueue-workloads?var-namespace=${__data.fields.namespace}&var-local_queue=${__data.fields.local_queue}&var-workload=${__data.fields.workload}&var-hostname=%24__all&from=${__from}&to=${__to}',
                                   }] }],
                                 }] else []),
    },
    transformations: [{ id: 'organize', options: { excludeByName: { Time: true, Value: true } } }],
  });

g.dashboard.new('Kueue Workloads')
+ g.dashboard.withUid('oke-kueue-workloads')
+ g.dashboard.withDescription('Queue admission and workload-to-pod-to-host resource monitoring. Queue charts use ClusterQueue; workload and resource panels use Namespace, LocalQueue, Workload and Host. Host metrics include all activity on the selected nodes, not only this job.')
+ g.dashboard.withTimezone('browser')
+ g.dashboard.time.withFrom('now-1h')
+ g.dashboard.withVariables([
  v('cluster_queue', 'label_values(kueue_cluster_queue_status, cluster_queue)', 'ClusterQueue'),
  v('namespace', 'label_values(oke_kueue_workload_owner_info, namespace)', 'Namespace'),
  v('local_queue', 'label_values(oke_kueue_workload_owner_info{namespace=~"$namespace"}, local_queue)', 'LocalQueue'),
  v('workload', 'label_values(oke_kueue_workload_owner_info{namespace=~"$namespace",local_queue=~"$local_queue"}, workload)', 'Workload'),
  // No custom allValue: Grafana expands All to the actual host list for links.
  v('hostname', 'query_result(max by(hostname) (oke:kueue_workload_pod:info{' + scope + '}))', 'Host', '/hostname="([^"]+)"/'),
])
+ g.dashboard.withLinks([
  nodeLink('gpu-metrics-single', 'GPU metrics — selected hosts', '${hostname:queryparam}') + { type: 'link' },
  nodeLink('host-metrics-single', 'Host metrics — selected hosts', '${hostname:queryparam}') + { type: 'link' },
])
+ g.dashboard.withPanels([
  stat('Kueue metrics endpoint up', 'max(up{namespace="kueue-system",service="kueue-controller-manager-metrics-service"}) or vector(0)', 0, 1, health=true),
  stat('Controller replicas available', 'sum(kube_deployment_status_replicas_available{namespace="kueue-system",deployment="kueue-controller-manager"}) or vector(0)', 6, 2, health=true),
  stat('Pending workloads', 'sum(max by(cluster_queue,status) (kueue_pending_workloads{' + cq + '}))', 12, 3),
  stat('Admitted active workloads', 'sum(max by(cluster_queue) (kueue_admitted_active_workloads{' + cq + '}))', 18, 4),
  chart('Pending workloads by queue and status', 'max by(cluster_queue,status) (kueue_pending_workloads{' + cq + '})', '{{cluster_queue}} / {{status}}', 0, 4, 5),
  chart('Admission throughput', 'sum by(cluster_queue) (rate(kueue_admitted_workloads_total{' + cq + '}[$__rate_interval]))', '{{cluster_queue}}', 12, 4, 6, 'ops'),
  chart('Admission wait p95', 'histogram_quantile(0.95, sum by(le,cluster_queue) (rate(kueue_admission_wait_time_seconds_bucket{' + cq + '}[$__rate_interval])))', '{{cluster_queue}}', 0, 11, 7, 's', 'Observed waits of workloads that reached admission; pending workloads are not samples in this histogram.'),
  chart('Evictions by reason', 'sum by(cluster_queue,reason) (rate(kueue_evicted_workloads_total{' + cq + '}[$__rate_interval]))', '{{cluster_queue}} / {{reason}}', 12, 11, 8, 'ops'),
  chart('Finished workload throughput', 'sum by(cluster_queue) (rate(kueue_finished_workloads_total{' + cq + '}[$__rate_interval]))', '{{cluster_queue}}', 0, 18, 10, 'ops', width=24),
  table('Workloads and owning jobs', 'max by(namespace,local_queue,cluster_queue,workload,owner_kind,owner_name) (oke_kueue_workload_owner_info{' + scope + ',owner_controller="true"})', 25, 11, 'Includes queued workloads with no assigned pods. ClusterQueue is empty until quota is reserved. Click the job name or select a Workload above to inspect its resources.', jobLinks=true),
  table('Workload conditions', 'max by(namespace,workload,condition,status) (oke_kueue_workload_condition{' + scope + '} == 1)', 33, 12, 'Admitted, PodsReady, Finished and other conditions reported by Kueue. Admission alone does not prove successful execution.'),
  table('Job → pods → hosts', 'max by(namespace,workload,owner_kind,owner_name,pod,hostname) (' + pods + ')', 41, 13, 'Click a hostname for host or GPU dashboards. Direct controller ownership and pods of child batch Jobs are resolved; other nested controllers may require additional mappings. Pending or deleted pods have no current host mapping.', true),
  chart('Hosts per selected workload', 'count by(namespace,workload) (max by(namespace,workload,hostname) (' + pods + '))', '{{namespace}} / {{workload}}', 0, 49, 14),
  chart('Requested GPUs per selected workload', 'sum by(namespace,workload,resource) (max by(namespace,pod,container,resource) (kube_pod_container_resource_requests{resource=~"nvidia_com_gpu|amd_com_gpu"}) * on(namespace,pod) group_left(workload) max by(namespace,pod,workload) (' + pods + '))', '{{namespace}} / {{workload}} / {{resource}}', 12, 49, 15, 'short', 'GPU requests of scheduled pods. CPU-only launcher pods are included in the host map but have no GPU request.'),
  chart('Measured pod CPU usage', 'sum by(namespace,workload) (max by(namespace,pod,container) (rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[$__rate_interval])) * on(namespace,pod) group_left(workload) max by(namespace,pod,workload) (' + pods + '))', '{{namespace}} / {{workload}}', 0, 56, 16, 'cores'),
  chart('Measured pod memory working set', 'sum by(namespace,workload) (max by(namespace,pod,container) (container_memory_working_set_bytes{container!="",container!="POD"}) * on(namespace,pod) group_left(workload) max by(namespace,pod,workload) (' + pods + '))', '{{namespace}} / {{workload}}', 12, 56, 17, 'bytes'),
  chart('GPU utilization on selected hosts', '(avg by(hostname) (DCGM_FI_DEV_GPU_UTIL{hostname=~"$hostname"}) or avg by(hostname) (amd_gpu_gfx_activity{hostname=~"$hostname"})) and on(hostname) max by(hostname) (' + pods + ')', '{{hostname}}', 0, 63, 18, 'percent', 'Host-wide GPU activity; includes other jobs sharing these hosts. Use pod metrics above for workload-scoped CPU and memory.'),
  chart('CPU utilization on selected hosts', '(100 * (1 - avg by(hostname) (rate(node_cpu_seconds_total{mode="idle",hostname=~"$hostname"}[$__rate_interval])))) and on(hostname) max by(hostname) (' + pods + ')', '{{hostname}}', 12, 63, 19, 'percent', 'Host-wide CPU activity, including other jobs and system services.'),
], setPanelIDs=false)
+ { refresh: '30s', tags: ['kueue', 'workloads', 'gpu'] }
