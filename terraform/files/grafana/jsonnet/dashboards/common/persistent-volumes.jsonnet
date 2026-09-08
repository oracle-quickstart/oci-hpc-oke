local panel = import '../../lib/dashboard-panel.libsonnet';
local target = import '../../lib/dashboard-target.libsonnet';
local variable = import '../../lib/dashboard-variable.libsonnet';
local g = import '../../lib/g.libsonnet';

g.dashboard.new('Kubernetes / Persistent Volumes')
+ g.dashboard.withUid('919b92a8e8041bd567af9edab12c840c')
+ g.dashboard.withTimezone('utc')
+ g.dashboard.withRefresh('10s')
+ g.dashboard.time.withFrom('now-1h')
+ g.dashboard.withVariables([
  variable.datasource('datasource', 'prometheus', { current: { text: 'default', value: 'default' }, label: 'Data source', options: [], refresh: 1, regex: '' }),
  variable.query('cluster', { type: 'prometheus', uid: '${datasource}' }, 'label_values(kubelet_volume_stats_capacity_bytes{job="kubelet", metrics_path="/metrics"}, cluster)', { allValue: '.*', current: { text: '', value: '' }, hide: 2, label: 'cluster', options: [], refresh: 2, sort: 1 }),
  variable.query('namespace', { type: 'prometheus', uid: '${datasource}' }, 'label_values(kubelet_volume_stats_capacity_bytes{cluster="$cluster", job="kubelet", metrics_path="/metrics"}, namespace)', { current: { text: 'monitoring', value: 'monitoring' }, label: 'Namespace', options: [], refresh: 2, sort: 1 }),
  variable.query('volume', { type: 'prometheus', uid: '${datasource}' }, 'label_values(kubelet_volume_stats_capacity_bytes{cluster="$cluster", job="kubelet", metrics_path="/metrics", namespace="$namespace"}, persistentvolumeclaim)', { current: { text: 'storage-kube-prometheus-stack-grafana-0', value: 'storage-kube-prometheus-stack-grafana-0' }, label: 'PersistentVolumeClaim', options: [], refresh: 2, sort: 1 }),
])
+ { annotations: { list: [{ builtIn: 1, datasource: { type: 'grafana', uid: '-- Grafana --' }, enable: true, hide: true, iconColor: 'rgba(0, 211, 255, 1)', name: 'Annotations & Alerts', type: 'dashboard' }] }, links: [{ asDropdown: true, includeVars: true, keepTime: true, tags: ['kubernetes-mixin'], targetBlank: false, title: 'Kubernetes', type: 'dashboards' }], tags: ['kubernetes-mixin'] }
+ g.dashboard.withPanels([
  panel.timeSeries(
    'Volume Space Usage',
    [
      target.prometheus('${datasource}', '(\n  sum without(instance, node) (topk(1, (kubelet_volume_stats_capacity_bytes{cluster="$cluster", job="kubelet", metrics_path="/metrics", namespace="$namespace", persistentvolumeclaim="$volume"})))\n  -\n  sum without(instance, node) (topk(1, (kubelet_volume_stats_available_bytes{cluster="$cluster", job="kubelet", metrics_path="/metrics", namespace="$namespace", persistentvolumeclaim="$volume"})))\n)\n', { legendFormat: 'Used Space', refId: 'A' }),
      target.prometheus('${datasource}', 'sum without(instance, node) (topk(1, (kubelet_volume_stats_available_bytes{cluster="$cluster", job="kubelet", metrics_path="/metrics", namespace="$namespace", persistentvolumeclaim="$volume"})))\n', { legendFormat: 'Free Space', refId: 'B' }),
    ],
    { h: 7, w: 18, x: 0, y: 0 },
    1,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.gauge(
    'Volume Space Usage',
    [
      target.prometheus('${datasource}', 'max without(instance,node) (\n(\n  topk(1, kubelet_volume_stats_capacity_bytes{cluster="$cluster", job="kubelet", metrics_path="/metrics", namespace="$namespace", persistentvolumeclaim="$volume"})\n  -\n  topk(1, kubelet_volume_stats_available_bytes{cluster="$cluster", job="kubelet", metrics_path="/metrics", namespace="$namespace", persistentvolumeclaim="$volume"})\n)\n/\ntopk(1, kubelet_volume_stats_capacity_bytes{cluster="$cluster", job="kubelet", metrics_path="/metrics", namespace="$namespace", persistentvolumeclaim="$volume"})\n* 100)\n', { instant: true, refId: 'A' }),
    ],
    { h: 7, w: 6, x: 18, y: 0 },
    2,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'thresholds' }, mappings: [], max: 100, min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'orange', value: 80 }, { color: 'red', value: 90 }] }, unit: 'percent' }, overrides: [] }, interval: '1m', options: { minVizHeight: 75, minVizWidth: 75, orientation: 'auto', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showThresholdLabels: false, showThresholdMarkers: true, sizing: 'auto' }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Volume inodes Usage',
    [
      target.prometheus('${datasource}', 'sum without(instance, node) (topk(1, (kubelet_volume_stats_inodes_used{cluster="$cluster", job="kubelet", metrics_path="/metrics", namespace="$namespace", persistentvolumeclaim="$volume"})))', { legendFormat: 'Used inodes', refId: 'A' }),
      target.prometheus('${datasource}', '(\n  sum without(instance, node) (topk(1, (kubelet_volume_stats_inodes{cluster="$cluster", job="kubelet", metrics_path="/metrics", namespace="$namespace", persistentvolumeclaim="$volume"})))\n  -\n  sum without(instance, node) (topk(1, (kubelet_volume_stats_inodes_used{cluster="$cluster", job="kubelet", metrics_path="/metrics", namespace="$namespace", persistentvolumeclaim="$volume"})))\n)\n', { legendFormat: 'Free inodes', refId: 'B' }),
    ],
    { h: 7, w: 18, x: 0, y: 7 },
    3,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'none' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.gauge(
    'Volume inodes Usage',
    [
      target.prometheus('${datasource}', 'max without(instance,node) (\ntopk(1, kubelet_volume_stats_inodes_used{cluster="$cluster", job="kubelet", metrics_path="/metrics", namespace="$namespace", persistentvolumeclaim="$volume"})\n/\ntopk(1, kubelet_volume_stats_inodes{cluster="$cluster", job="kubelet", metrics_path="/metrics", namespace="$namespace", persistentvolumeclaim="$volume"})\n* 100)\n', { instant: true, refId: 'A' }),
    ],
    { h: 7, w: 6, x: 18, y: 7 },
    4,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'thresholds' }, mappings: [], max: 100, min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'orange', value: 80 }, { color: 'red', value: 90 }] }, unit: 'percent' }, overrides: [] }, interval: '1m', options: { minVizHeight: 75, minVizWidth: 75, orientation: 'auto', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showThresholdLabels: false, showThresholdMarkers: true, sizing: 'auto' }, pluginVersion: '11.5.2' },
  ),
], setPanelIDs=false)
