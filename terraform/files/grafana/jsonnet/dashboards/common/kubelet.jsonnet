local panel = import '../../lib/dashboard-panel.libsonnet';
local target = import '../../lib/dashboard-target.libsonnet';
local variable = import '../../lib/dashboard-variable.libsonnet';
local g = import '../../lib/g.libsonnet';

g.dashboard.new('Kubernetes / Kubelet')
+ g.dashboard.withUid('3138fa155d5915769fbded898ac09fd9')
+ g.dashboard.withTimezone('utc')
+ g.dashboard.withRefresh('10s')
+ g.dashboard.time.withFrom('now-1h')
+ g.dashboard.withVariables([
  variable.datasource('datasource', 'prometheus', { current: { text: 'default', value: 'default' }, label: 'Data source', options: [], refresh: 1, regex: '' }),
  variable.query('cluster', { type: 'prometheus', uid: '${datasource}' }, 'label_values(up{job="kubelet", metrics_path="/metrics"}, cluster)', { allValue: '.*', current: { text: '', value: '' }, hide: 2, label: 'cluster', options: [], refresh: 2, sort: 1 }),
  variable.query('instance', { type: 'prometheus', uid: '${datasource}' }, 'label_values(up{job="kubelet", metrics_path="/metrics",cluster="$cluster"}, instance)', { current: { text: 'All', value: '$__all' }, includeAll: true, label: 'instance', options: [], refresh: 2 }),
])
+ { annotations: { list: [{ builtIn: 1, datasource: { type: 'grafana', uid: '-- Grafana --' }, enable: true, hide: true, iconColor: 'rgba(0, 211, 255, 1)', name: 'Annotations & Alerts', type: 'dashboard' }] }, links: [{ asDropdown: true, includeVars: true, keepTime: true, tags: ['kubernetes-mixin'], targetBlank: false, title: 'Kubernetes', type: 'dashboards' }], tags: ['kubernetes-mixin'] }
+ g.dashboard.withPanels([
  panel.stat(
    'Running Kubelets',
    [
      target.prometheus('${datasource}', 'sum(kubelet_node_name{cluster="$cluster", job="kubelet", metrics_path="/metrics"})', { instant: true, refId: 'A' }),
    ],
    { h: 7, w: 4, x: 0, y: 0 },
    1,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'none' }, overrides: [] }, interval: '1m', options: { colorMode: 'none', graphMode: 'area', justifyMode: 'auto', orientation: 'auto', percentChangeColorMode: 'standard', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showPercentChange: false, textMode: 'auto', wideLayout: true }, pluginVersion: '11.5.2' },
  ),
  panel.stat(
    'Running Pods',
    [
      target.prometheus('${datasource}', 'sum(kubelet_running_pods{cluster="$cluster", job="kubelet", metrics_path="/metrics", instance=~"$instance"})', { instant: true, refId: 'A' }),
    ],
    { h: 7, w: 4, x: 4, y: 0 },
    2,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'none' }, overrides: [] }, interval: '1m', options: { colorMode: 'none', graphMode: 'area', justifyMode: 'auto', orientation: 'auto', percentChangeColorMode: 'standard', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showPercentChange: false, textMode: 'auto', wideLayout: true }, pluginVersion: '11.5.2' },
  ),
  panel.stat(
    'Running Containers',
    [
      target.prometheus('${datasource}', 'sum(kubelet_running_containers{cluster="$cluster", job="kubelet", metrics_path="/metrics", instance=~"$instance"})', { instant: true, refId: 'A' }),
    ],
    { h: 7, w: 4, x: 8, y: 0 },
    3,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'none' }, overrides: [] }, interval: '1m', options: { colorMode: 'none', graphMode: 'area', justifyMode: 'auto', orientation: 'auto', percentChangeColorMode: 'standard', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showPercentChange: false, textMode: 'auto', wideLayout: true }, pluginVersion: '11.5.2' },
  ),
  panel.stat(
    'Actual Volume Count',
    [
      target.prometheus('${datasource}', 'sum(volume_manager_total_volumes{cluster="$cluster", job="kubelet", metrics_path="/metrics", instance=~"$instance", state="actual_state_of_world"})', { instant: true, refId: 'A' }),
    ],
    { h: 7, w: 4, x: 12, y: 0 },
    4,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'none' }, overrides: [] }, interval: '1m', options: { colorMode: 'none', graphMode: 'area', justifyMode: 'auto', orientation: 'auto', percentChangeColorMode: 'standard', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showPercentChange: false, textMode: 'auto', wideLayout: true }, pluginVersion: '11.5.2' },
  ),
  panel.stat(
    'Desired Volume Count',
    [
      target.prometheus('${datasource}', 'sum(volume_manager_total_volumes{cluster="$cluster", job="kubelet", metrics_path="/metrics", instance=~"$instance",state="desired_state_of_world"})', { instant: true, refId: 'A' }),
    ],
    { h: 7, w: 8, x: 16, y: 0 },
    5,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'none' }, overrides: [] }, interval: '1m', options: { colorMode: 'none', graphMode: 'area', justifyMode: 'auto', orientation: 'auto', percentChangeColorMode: 'standard', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showPercentChange: false, textMode: 'auto', wideLayout: true }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Operation Rate',
    [
      target.prometheus('${datasource}', 'sum(rate(kubelet_runtime_operations_total{cluster="$cluster",job="kubelet", metrics_path="/metrics",instance=~"$instance"}[$__rate_interval])) by (operation_type, instance)', { legendFormat: '{{instance}} {{operation_type}}', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 0, y: 7 },
    7,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'ops' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Operation Error Rate',
    [
      target.prometheus('${datasource}', 'sum(rate(kubelet_runtime_operations_errors_total{cluster="$cluster",job="kubelet", metrics_path="/metrics",instance=~"$instance"}[$__rate_interval])) by (instance, operation_type)', { legendFormat: '{{instance}} {{operation_type}}', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 12, y: 7 },
    8,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'ops' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Operation Duration 99th quantile',
    [
      target.prometheus('${datasource}', 'histogram_quantile(0.99, sum(rate(kubelet_runtime_operations_duration_seconds_bucket{cluster="$cluster",job="kubelet", metrics_path="/metrics",instance=~"$instance"}[$__rate_interval])) by (instance, operation_type, le))', { legendFormat: '{{instance}} {{operation_type}}', refId: 'A' }),
    ],
    { h: 7, w: 24, x: 0, y: 14 },
    9,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 's' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Pod Start Rate',
    [
      target.prometheus('${datasource}', 'sum(rate(kubelet_pod_start_duration_seconds_count{cluster="$cluster",job="kubelet", metrics_path="/metrics",instance=~"$instance"}[$__rate_interval])) by (instance)', { legendFormat: '{{instance}} pod', refId: 'A' }),
      target.prometheus('${datasource}', 'sum(rate(kubelet_pod_worker_duration_seconds_count{cluster="$cluster",job="kubelet", metrics_path="/metrics",instance=~"$instance"}[$__rate_interval])) by (instance)', { legendFormat: '{{instance}} worker', refId: 'B' }),
    ],
    { h: 7, w: 12, x: 0, y: 21 },
    10,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'ops' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Pod Start Duration',
    [
      target.prometheus('${datasource}', 'histogram_quantile(0.99, sum(rate(kubelet_pod_start_duration_seconds_bucket{cluster="$cluster",job="kubelet", metrics_path="/metrics",instance=~"$instance"}[$__rate_interval])) by (instance, le))', { legendFormat: '{{instance}} pod', refId: 'A' }),
      target.prometheus('${datasource}', 'histogram_quantile(0.99, sum(rate(kubelet_pod_worker_duration_seconds_bucket{cluster="$cluster",job="kubelet", metrics_path="/metrics",instance=~"$instance"}[$__rate_interval])) by (instance, le))', { legendFormat: '{{instance}} worker', refId: 'B' }),
    ],
    { h: 7, w: 12, x: 12, y: 21 },
    11,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 's' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Storage Operation Rate',
    [
      target.prometheus('${datasource}', 'sum(rate(storage_operation_duration_seconds_count{cluster="$cluster",job="kubelet", metrics_path="/metrics",instance=~"$instance"}[$__rate_interval])) by (instance, operation_name, volume_plugin)', { legendFormat: '{{instance}} {{operation_name}} {{volume_plugin}}', refId: 'A' }),
    ],
    { h: 7, w: 24, x: 0, y: 28 },
    12,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'ops' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Storage Operation Duration 99th quantile',
    [
      target.prometheus('${datasource}', 'histogram_quantile(0.99, sum(rate(storage_operation_duration_seconds_bucket{cluster="$cluster", job="kubelet", metrics_path="/metrics", instance=~"$instance"}[$__rate_interval])) by (instance, operation_name, volume_plugin, le))', { legendFormat: '{{instance}} {{operation_name}} {{volume_plugin}}', refId: 'A' }),
    ],
    { h: 7, w: 24, x: 0, y: 35 },
    14,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 's' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Cgroup manager operation rate',
    [
      target.prometheus('${datasource}', 'sum(rate(kubelet_cgroup_manager_duration_seconds_count{cluster="$cluster", job="kubelet", metrics_path="/metrics", instance=~"$instance"}[$__rate_interval])) by (instance, operation_type)', { legendFormat: '{{operation_type}}', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 0, y: 42 },
    15,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'ops' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Cgroup manager 99th quantile',
    [
      target.prometheus('${datasource}', 'histogram_quantile(0.99, sum(rate(kubelet_cgroup_manager_duration_seconds_bucket{cluster="$cluster", job="kubelet", metrics_path="/metrics", instance=~"$instance"}[$__rate_interval])) by (instance, operation_type, le))', { legendFormat: '{{instance}} {{operation_type}}', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 12, y: 42 },
    16,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 's' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'PLEG relist rate',
    [
      target.prometheus('${datasource}', 'sum(rate(kubelet_pleg_relist_duration_seconds_count{cluster="$cluster", job="kubelet", metrics_path="/metrics", instance=~"$instance"}[$__rate_interval])) by (instance)', { legendFormat: '{{instance}}', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 0, y: 49 },
    17,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'ops' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'PLEG relist interval',
    [
      target.prometheus('${datasource}', 'histogram_quantile(0.99, sum(rate(kubelet_pleg_relist_interval_seconds_bucket{cluster="$cluster",job="kubelet", metrics_path="/metrics",instance=~"$instance"}[$__rate_interval])) by (instance, le))', { legendFormat: '{{instance}}', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 12, y: 49 },
    18,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 's' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'PLEG relist duration',
    [
      target.prometheus('${datasource}', 'histogram_quantile(0.99, sum(rate(kubelet_pleg_relist_duration_seconds_bucket{cluster="$cluster",job="kubelet", metrics_path="/metrics",instance=~"$instance"}[$__rate_interval])) by (instance, le))', { legendFormat: '{{instance}}', refId: 'A' }),
    ],
    { h: 7, w: 24, x: 0, y: 56 },
    19,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 's' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'RPC rate',
    [
      target.prometheus('${datasource}', 'sum(rate(rest_client_requests_total{cluster="$cluster",job="kubelet", metrics_path="/metrics", instance=~"$instance",code=~"2.."}[$__rate_interval]))', { legendFormat: '2xx', refId: 'A' }),
      target.prometheus('${datasource}', 'sum(rate(rest_client_requests_total{cluster="$cluster",job="kubelet", metrics_path="/metrics", instance=~"$instance",code=~"3.."}[$__rate_interval]))', { legendFormat: '3xx', refId: 'B' }),
      target.prometheus('${datasource}', 'sum(rate(rest_client_requests_total{cluster="$cluster",job="kubelet", metrics_path="/metrics", instance=~"$instance",code=~"4.."}[$__rate_interval]))', { legendFormat: '4xx', refId: 'C' }),
      target.prometheus('${datasource}', 'sum(rate(rest_client_requests_total{cluster="$cluster",job="kubelet", metrics_path="/metrics", instance=~"$instance",code=~"5.."}[$__rate_interval]))', { legendFormat: '5xx', refId: 'D' }),
    ],
    { h: 7, w: 24, x: 0, y: 63 },
    20,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'ops' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Request duration 99th quantile',
    [
      target.prometheus('${datasource}', 'histogram_quantile(0.99, sum(rate(rest_client_request_duration_seconds_bucket{cluster="$cluster",job="kubelet", metrics_path="/metrics", instance=~"$instance"}[$__rate_interval])) by (instance, verb, le))', { legendFormat: '{{instance}} {{verb}}', refId: 'A' }),
    ],
    { h: 7, w: 24, x: 0, y: 70 },
    21,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 's' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Memory',
    [
      target.prometheus('${datasource}', 'process_resident_memory_bytes{cluster="$cluster",job="kubelet", metrics_path="/metrics",instance=~"$instance"}', { legendFormat: '{{instance}}', refId: 'A' }),
    ],
    { h: 7, w: 8, x: 0, y: 77 },
    22,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'CPU usage',
    [
      target.prometheus('${datasource}', 'rate(process_cpu_seconds_total{cluster="$cluster",job="kubelet", metrics_path="/metrics",instance=~"$instance"}[$__rate_interval])', { legendFormat: '{{instance}}', refId: 'A' }),
    ],
    { h: 7, w: 8, x: 8, y: 77 },
    23,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'short' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Goroutines',
    [
      target.prometheus('${datasource}', 'go_goroutines{cluster="$cluster",job="kubelet", metrics_path="/metrics",instance=~"$instance"}', { legendFormat: '{{instance}}', refId: 'A' }),
    ],
    { h: 7, w: 8, x: 16, y: 77 },
    24,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'short' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
], setPanelIDs=false)
