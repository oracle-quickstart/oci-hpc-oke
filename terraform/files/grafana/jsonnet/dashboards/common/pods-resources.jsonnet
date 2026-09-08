local panel = import '../../lib/dashboard-panel.libsonnet';
local target = import '../../lib/dashboard-target.libsonnet';
local variable = import '../../lib/dashboard-variable.libsonnet';
local g = import '../../lib/g.libsonnet';

g.dashboard.new('Kubernetes / Compute Resources / Namespace (Pods)')
+ g.dashboard.withUid('85a562078cdf77779eaa1add43ccec1e')
+ g.dashboard.withTimezone('utc')
+ g.dashboard.withRefresh('10s')
+ g.dashboard.time.withFrom('now-1h')
+ g.dashboard.withVariables([
  variable.datasource('datasource', 'prometheus', { current: { text: 'default', value: 'default' }, label: 'Data source', options: [], refresh: 1, regex: '' }),
  variable.query('cluster', { type: 'prometheus', uid: '${datasource}' }, 'label_values(up{job="kube-state-metrics"}, cluster)', { allValue: '.*', current: { text: '', value: '' }, hide: 2, label: 'cluster', options: [], refresh: 2, sort: 1 }),
  variable.query('namespace', { type: 'prometheus', uid: '${datasource}' }, 'label_values(kube_namespace_status_phase{job="kube-state-metrics", cluster="$cluster"}, namespace)', { current: { text: 'monitoring', value: 'monitoring' }, label: 'namespace', options: [], refresh: 2, sort: 1 }),
])
+ { annotations: { list: [{ builtIn: 1, datasource: { type: 'grafana', uid: '-- Grafana --' }, enable: true, hide: true, iconColor: 'rgba(0, 211, 255, 1)', name: 'Annotations & Alerts', type: 'dashboard' }] }, links: [{ asDropdown: true, includeVars: true, keepTime: true, tags: ['kubernetes-mixin'], targetBlank: false, title: 'Kubernetes', type: 'dashboards' }], tags: ['kubernetes-mixin'] }
+ g.dashboard.withPanels([
  panel.stat(
    'CPU Utilisation (from requests)',
    [
      target.prometheus('${datasource}', 'sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate{cluster="$cluster", namespace="$namespace"}) / sum(kube_pod_container_resource_requests{job="kube-state-metrics", cluster="$cluster", namespace="$namespace", resource="cpu"})', { instant: true, refId: 'A' }),
    ],
    { h: 3, w: 6, x: 0, y: 0 },
    1,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'percentunit' }, overrides: [] }, interval: '1m', options: { colorMode: 'none', graphMode: 'area', justifyMode: 'auto', orientation: 'auto', percentChangeColorMode: 'standard', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showPercentChange: false, textMode: 'auto', wideLayout: true }, pluginVersion: '11.5.2' },
  ),
  panel.stat(
    'CPU Utilisation (from limits)',
    [
      target.prometheus('${datasource}', 'sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate{cluster="$cluster", namespace="$namespace"}) / sum(kube_pod_container_resource_limits{job="kube-state-metrics", cluster="$cluster", namespace="$namespace", resource="cpu"})', { instant: true, refId: 'A' }),
    ],
    { h: 3, w: 6, x: 6, y: 0 },
    2,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'percentunit' }, overrides: [] }, interval: '1m', options: { colorMode: 'none', graphMode: 'area', justifyMode: 'auto', orientation: 'auto', percentChangeColorMode: 'standard', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showPercentChange: false, textMode: 'auto', wideLayout: true }, pluginVersion: '11.5.2' },
  ),
  panel.stat(
    'Memory Utilisation (from requests)',
    [
      target.prometheus('${datasource}', 'sum(container_memory_working_set_bytes{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace",container!="", image!=""}) / sum(kube_pod_container_resource_requests{job="kube-state-metrics", cluster="$cluster", namespace="$namespace", resource="memory"})', { instant: true, refId: 'A' }),
    ],
    { h: 3, w: 6, x: 12, y: 0 },
    3,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'percentunit' }, overrides: [] }, interval: '1m', options: { colorMode: 'none', graphMode: 'area', justifyMode: 'auto', orientation: 'auto', percentChangeColorMode: 'standard', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showPercentChange: false, textMode: 'auto', wideLayout: true }, pluginVersion: '11.5.2' },
  ),
  panel.stat(
    'Memory Utilisation (from limits)',
    [
      target.prometheus('${datasource}', 'sum(container_memory_working_set_bytes{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace",container!="", image!=""}) / sum(kube_pod_container_resource_limits{job="kube-state-metrics", cluster="$cluster", namespace="$namespace", resource="memory"})', { instant: true, refId: 'A' }),
    ],
    { h: 3, w: 6, x: 18, y: 0 },
    4,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'percentunit' }, overrides: [] }, interval: '1m', options: { colorMode: 'none', graphMode: 'area', justifyMode: 'auto', orientation: 'auto', percentChangeColorMode: 'standard', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showPercentChange: false, textMode: 'auto', wideLayout: true }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'CPU Usage',
    [
      target.prometheus('${datasource}', 'sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate{cluster="$cluster", namespace="$namespace"}) by (pod)', { legendFormat: '__auto', refId: 'A' }),
      target.prometheus('${datasource}', 'scalar(max(kube_resourcequota{cluster="$cluster", namespace="$namespace", type="hard",resource="requests.cpu"}))', { legendFormat: 'quota - requests', refId: 'B' }),
      target.prometheus('${datasource}', 'scalar(max(kube_resourcequota{cluster="$cluster", namespace="$namespace", type="hard",resource="limits.cpu"}))', { legendFormat: 'quota - limits', refId: 'C' }),
    ],
    { h: 7, w: 24, x: 0, y: 3 },
    5,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [{ matcher: { id: 'byFrameRefID', options: 'B' }, properties: [{ id: 'custom.lineStyle', value: { fill: 'dash' } }, { id: 'custom.lineWidth', value: 2 }, { id: 'color', value: { fixedColor: 'red', mode: 'fixed' } }] }, { matcher: { id: 'byFrameRefID', options: 'C' }, properties: [{ id: 'custom.lineStyle', value: { fill: 'dash' } }, { id: 'custom.lineWidth', value: 2 }, { id: 'color', value: { fixedColor: 'orange', mode: 'fixed' } }] }] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.table(
    'CPU Quota',
    [
      target.prometheus('${datasource}', 'sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate{cluster="$cluster", namespace="$namespace"}) by (pod)', { format: 'table', instant: true, refId: 'A' }),
      target.prometheus('${datasource}', 'sum(cluster:namespace:pod_cpu:active:kube_pod_container_resource_requests{cluster="$cluster", namespace="$namespace"}) by (pod)', { format: 'table', instant: true, refId: 'B' }),
      target.prometheus('${datasource}', 'sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate{cluster="$cluster", namespace="$namespace"}) by (pod) / sum(cluster:namespace:pod_cpu:active:kube_pod_container_resource_requests{cluster="$cluster", namespace="$namespace"}) by (pod)', { format: 'table', instant: true, refId: 'C' }),
      target.prometheus('${datasource}', 'sum(cluster:namespace:pod_cpu:active:kube_pod_container_resource_limits{cluster="$cluster", namespace="$namespace"}) by (pod)', { format: 'table', instant: true, refId: 'D' }),
      target.prometheus('${datasource}', 'sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate{cluster="$cluster", namespace="$namespace"}) by (pod) / sum(cluster:namespace:pod_cpu:active:kube_pod_container_resource_limits{cluster="$cluster", namespace="$namespace"}) by (pod)', { format: 'table', instant: true, refId: 'E' }),
    ],
    { h: 7, w: 24, x: 0, y: 10 },
    6,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { custom: { align: 'auto', cellOptions: { type: 'auto' }, inspect: false }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [{ matcher: { id: 'byRegexp', options: '/%/' }, properties: [{ id: 'unit', value: 'percentunit' }] }, { matcher: { id: 'byName', options: 'Pod' }, properties: [{ id: 'links', value: [{ title: 'Drill down to pods', url: '/d/6581e46e4e5c7ba40a07646395ef7b23/k8s-resources-pod?${datasource:queryparam}&var-cluster=$cluster&var-namespace=$namespace&var-pod=${__data.fields.Pod}' }] }] }] }, options: { cellHeight: 'sm', footer: { countRows: false, fields: '', reducer: ['sum'], show: false }, showHeader: true }, pluginVersion: '11.5.2', transformations: [{ id: 'joinByField', options: { byField: 'pod', mode: 'outer' } }, { id: 'organize', options: { excludeByName: { Time: true, 'Time 1': true, 'Time 2': true, 'Time 3': true, 'Time 4': true, 'Time 5': true }, indexByName: { 'Time 1': 0, 'Time 2': 1, 'Time 3': 2, 'Time 4': 3, 'Time 5': 4, 'Value #A': 6, 'Value #B': 7, 'Value #C': 8, 'Value #D': 9, 'Value #E': 10, pod: 5 }, renameByName: { 'Value #A': 'CPU Usage', 'Value #B': 'CPU Requests', 'Value #C': 'CPU Requests %', 'Value #D': 'CPU Limits', 'Value #E': 'CPU Limits %', pod: 'Pod' } } }] },
  ),
  panel.timeSeries(
    'Memory Usage (w/o cache)',
    [
      target.prometheus('${datasource}', 'sum(container_memory_working_set_bytes{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace", container!="", image!=""}) by (pod)', { legendFormat: '__auto', refId: 'A' }),
      target.prometheus('${datasource}', 'scalar(max(kube_resourcequota{cluster="$cluster", namespace="$namespace", type="hard",resource="requests.memory"}))', { legendFormat: 'quota - requests', refId: 'B' }),
      target.prometheus('${datasource}', 'scalar(max(kube_resourcequota{cluster="$cluster", namespace="$namespace", type="hard",resource="limits.memory"}))', { legendFormat: 'quota - limits', refId: 'C' }),
    ],
    { h: 7, w: 24, x: 0, y: 17 },
    7,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [{ matcher: { id: 'byFrameRefID', options: 'B' }, properties: [{ id: 'custom.lineStyle', value: { fill: 'dash' } }, { id: 'custom.lineWidth', value: 2 }, { id: 'color', value: { fixedColor: 'red', mode: 'fixed' } }] }, { matcher: { id: 'byFrameRefID', options: 'C' }, properties: [{ id: 'custom.lineStyle', value: { fill: 'dash' } }, { id: 'custom.lineWidth', value: 2 }, { id: 'color', value: { fixedColor: 'orange', mode: 'fixed' } }] }] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.table(
    'Memory Quota',
    [
      target.prometheus('${datasource}', 'sum(container_memory_working_set_bytes{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace",container!="", image!=""}) by (pod)', { format: 'table', instant: true, refId: 'A' }),
      target.prometheus('${datasource}', 'sum(cluster:namespace:pod_memory:active:kube_pod_container_resource_requests{cluster="$cluster", namespace="$namespace"}) by (pod)', { format: 'table', instant: true, refId: 'B' }),
      target.prometheus('${datasource}', 'sum(container_memory_working_set_bytes{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace",container!="", image!=""}) by (pod) / sum(cluster:namespace:pod_memory:active:kube_pod_container_resource_requests{cluster="$cluster", namespace="$namespace"}) by (pod)', { format: 'table', instant: true, refId: 'C' }),
      target.prometheus('${datasource}', 'sum(cluster:namespace:pod_memory:active:kube_pod_container_resource_limits{cluster="$cluster", namespace="$namespace"}) by (pod)', { format: 'table', instant: true, refId: 'D' }),
      target.prometheus('${datasource}', 'sum(container_memory_working_set_bytes{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace",container!="", image!=""}) by (pod) / sum(cluster:namespace:pod_memory:active:kube_pod_container_resource_limits{cluster="$cluster", namespace="$namespace"}) by (pod)', { format: 'table', instant: true, refId: 'E' }),
      target.prometheus('${datasource}', 'sum(container_memory_rss{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace",container!=""}) by (pod)', { format: 'table', instant: true, refId: 'F' }),
      target.prometheus('${datasource}', 'sum(container_memory_cache{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace",container!=""}) by (pod)', { format: 'table', instant: true, refId: 'G' }),
      target.prometheus('${datasource}', 'sum(container_memory_swap{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace",container!=""}) by (pod)', { format: 'table', instant: true, refId: 'H' }),
    ],
    { h: 7, w: 24, x: 0, y: 24 },
    8,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { custom: { align: 'auto', cellOptions: { type: 'auto' }, inspect: false }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [{ matcher: { id: 'byRegexp', options: '/%/' }, properties: [{ id: 'unit', value: 'percentunit' }] }, { matcher: { id: 'byName', options: 'Pod' }, properties: [{ id: 'links', value: [{ title: 'Drill down to pods', url: '/d/6581e46e4e5c7ba40a07646395ef7b23/k8s-resources-pod?${datasource:queryparam}&var-cluster=$cluster&var-namespace=$namespace&var-pod=${__data.fields.Pod}' }] }] }] }, options: { cellHeight: 'sm', footer: { countRows: false, fields: '', reducer: ['sum'], show: false }, showHeader: true }, pluginVersion: '11.5.2', transformations: [{ id: 'joinByField', options: { byField: 'pod', mode: 'outer' } }, { id: 'organize', options: { excludeByName: { Time: true, 'Time 1': true, 'Time 2': true, 'Time 3': true, 'Time 4': true, 'Time 5': true, 'Time 6': true, 'Time 7': true, 'Time 8': true }, indexByName: { 'Time 1': 0, 'Time 2': 1, 'Time 3': 2, 'Time 4': 3, 'Time 5': 4, 'Time 6': 5, 'Time 7': 6, 'Time 8': 7, 'Value #A': 9, 'Value #B': 10, 'Value #C': 11, 'Value #D': 12, 'Value #E': 13, 'Value #F': 14, 'Value #G': 15, 'Value #H': 16, pod: 8 }, renameByName: { 'Value #A': 'Memory Usage', 'Value #B': 'Memory Requests', 'Value #C': 'Memory Requests %', 'Value #D': 'Memory Limits', 'Value #E': 'Memory Limits %', 'Value #F': 'Memory Usage (RSS)', 'Value #G': 'Memory Usage (Cache)', 'Value #H': 'Memory Usage (Swap)', pod: 'Pod' } } }] },
  ),
  panel.table(
    'Current Network Usage',
    [
      target.prometheus('${datasource}', 'sum(rate(container_network_receive_bytes_total{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace"}[$__rate_interval])) by (pod)', { format: 'table', instant: true, refId: 'A' }),
      target.prometheus('${datasource}', 'sum(rate(container_network_transmit_bytes_total{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace"}[$__rate_interval])) by (pod)', { format: 'table', instant: true, refId: 'B' }),
      target.prometheus('${datasource}', 'sum(rate(container_network_receive_packets_total{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace"}[$__rate_interval])) by (pod)', { format: 'table', instant: true, refId: 'C' }),
      target.prometheus('${datasource}', 'sum(rate(container_network_transmit_packets_total{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace"}[$__rate_interval])) by (pod)', { format: 'table', instant: true, refId: 'D' }),
      target.prometheus('${datasource}', 'sum(rate(container_network_receive_packets_dropped_total{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace"}[$__rate_interval])) by (pod)', { format: 'table', instant: true, refId: 'E' }),
      target.prometheus('${datasource}', 'sum(rate(container_network_transmit_packets_dropped_total{job="kubelet", metrics_path="/metrics/cadvisor", cluster="$cluster", namespace="$namespace"}[$__rate_interval])) by (pod)', { format: 'table', instant: true, refId: 'F' }),
    ],
    { h: 7, w: 24, x: 0, y: 31 },
    9,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { custom: { align: 'auto', cellOptions: { type: 'auto' }, inspect: false }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [{ matcher: { id: 'byRegexp', options: '/Bandwidth/' }, properties: [{ id: 'unit', value: 'Bps' }] }, { matcher: { id: 'byRegexp', options: '/Packets/' }, properties: [{ id: 'unit', value: 'pps' }] }, { matcher: { id: 'byName', options: 'Pod' }, properties: [{ id: 'links', value: [{ title: 'Drill down to pods', url: '/d/6581e46e4e5c7ba40a07646395ef7b23/k8s-resources-pod?${datasource:queryparam}&var-cluster=$cluster&var-namespace=$namespace&var-pod=${__data.fields.Pod}' }] }] }] }, options: { cellHeight: 'sm', footer: { countRows: false, fields: '', reducer: ['sum'], show: false }, showHeader: true }, pluginVersion: '11.5.2', transformations: [{ id: 'joinByField', options: { byField: 'pod', mode: 'outer' } }, { id: 'organize', options: { excludeByName: { Time: true, 'Time 1': true, 'Time 2': true, 'Time 3': true, 'Time 4': true, 'Time 5': true, 'Time 6': true }, indexByName: { 'Time 1': 0, 'Time 2': 1, 'Time 3': 2, 'Time 4': 3, 'Time 5': 4, 'Time 6': 5, 'Value #A': 7, 'Value #B': 8, 'Value #C': 9, 'Value #D': 10, 'Value #E': 11, 'Value #F': 12, pod: 6 }, renameByName: { 'Value #A': 'Current Receive Bandwidth', 'Value #B': 'Current Transmit Bandwidth', 'Value #C': 'Rate of Received Packets', 'Value #D': 'Rate of Transmitted Packets', 'Value #E': 'Rate of Received Packets Dropped', 'Value #F': 'Rate of Transmitted Packets Dropped', pod: 'Pod' } } }] },
  ),
  panel.timeSeries(
    'Receive Bandwidth',
    [
      target.prometheus('${datasource}', 'sum(rate(container_network_receive_bytes_total{cluster="$cluster", namespace="$namespace"}[$__rate_interval])) by (pod)', { legendFormat: '__auto', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 0, y: 38 },
    10,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'Bps' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Transmit Bandwidth',
    [
      target.prometheus('${datasource}', 'sum(rate(container_network_transmit_bytes_total{cluster="$cluster", namespace="$namespace"}[$__rate_interval])) by (pod)', { legendFormat: '__auto', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 12, y: 38 },
    11,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'Bps' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Rate of Received Packets',
    [
      target.prometheus('${datasource}', 'sum(irate(container_network_receive_packets_total{cluster="$cluster", namespace="$namespace"}[$__rate_interval])) by (pod)', { legendFormat: '__auto', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 0, y: 45 },
    12,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'pps' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Rate of Transmitted Packets',
    [
      target.prometheus('${datasource}', 'sum(irate(container_network_transmit_packets_total{cluster="$cluster", namespace="$namespace"}[$__rate_interval])) by (pod)', { legendFormat: '__auto', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 12, y: 45 },
    13,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'pps' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Rate of Received Packets Dropped',
    [
      target.prometheus('${datasource}', 'sum(irate(container_network_receive_packets_dropped_total{cluster="$cluster", namespace="$namespace"}[$__rate_interval])) by (pod)', { legendFormat: '__auto', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 0, y: 52 },
    14,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'pps' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Rate of Transmitted Packets Dropped',
    [
      target.prometheus('${datasource}', 'sum(irate(container_network_transmit_packets_dropped_total{cluster="$cluster", namespace="$namespace"}[$__rate_interval])) by (pod)', { legendFormat: '__auto', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 12, y: 52 },
    15,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'pps' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'IOPS(Reads+Writes)',
    [
      target.prometheus('${datasource}', 'ceil(sum by(pod) (rate(container_fs_reads_total{container!="", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)", cluster="$cluster", namespace="$namespace"}[$__rate_interval]) + rate(container_fs_writes_total{container!="", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)", cluster="$cluster", namespace="$namespace"}[$__rate_interval])))', { legendFormat: '__auto', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 0, y: 59 },
    16,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'iops' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'ThroughPut(Read+Write)',
    [
      target.prometheus('${datasource}', 'sum by(pod) (rate(container_fs_reads_bytes_total{container!="", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)", cluster="$cluster", namespace="$namespace"}[$__rate_interval]) + rate(container_fs_writes_bytes_total{container!="", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)", cluster="$cluster", namespace="$namespace"}[$__rate_interval]))', { legendFormat: '__auto', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 12, y: 59 },
    17,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'Bps' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.table(
    'Current Storage IO',
    [
      target.prometheus('${datasource}', 'sum by(pod) (rate(container_fs_reads_total{job="kubelet", metrics_path="/metrics/cadvisor", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)", container!="", cluster="$cluster", namespace="$namespace"}[$__rate_interval]))', { format: 'table', instant: true, refId: 'A' }),
      target.prometheus('${datasource}', 'sum by(pod) (rate(container_fs_writes_total{job="kubelet", metrics_path="/metrics/cadvisor", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)", container!="", cluster="$cluster", namespace="$namespace"}[$__rate_interval]))', { format: 'table', instant: true, refId: 'B' }),
      target.prometheus('${datasource}', 'sum by(pod) (rate(container_fs_reads_total{job="kubelet", metrics_path="/metrics/cadvisor", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)", container!="", cluster="$cluster", namespace="$namespace"}[$__rate_interval]) + rate(container_fs_writes_total{job="kubelet", metrics_path="/metrics/cadvisor", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)", container!="", cluster="$cluster", namespace="$namespace"}[$__rate_interval]))', { format: 'table', instant: true, refId: 'C' }),
      target.prometheus('${datasource}', 'sum by(pod) (rate(container_fs_reads_bytes_total{job="kubelet", metrics_path="/metrics/cadvisor", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)", container!="", cluster="$cluster", namespace="$namespace"}[$__rate_interval]))', { format: 'table', instant: true, refId: 'D' }),
      target.prometheus('${datasource}', 'sum by(pod) (rate(container_fs_writes_bytes_total{job="kubelet", metrics_path="/metrics/cadvisor", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)", container!="", cluster="$cluster", namespace="$namespace"}[$__rate_interval]))', { format: 'table', instant: true, refId: 'E' }),
      target.prometheus('${datasource}', 'sum by(pod) (rate(container_fs_reads_bytes_total{job="kubelet", metrics_path="/metrics/cadvisor", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)", container!="", cluster="$cluster", namespace="$namespace"}[$__rate_interval]) + rate(container_fs_writes_bytes_total{job="kubelet", metrics_path="/metrics/cadvisor", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)", container!="", cluster="$cluster", namespace="$namespace"}[$__rate_interval]))', { format: 'table', instant: true, refId: 'F' }),
    ],
    { h: 7, w: 24, x: 0, y: 66 },
    18,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { custom: { align: 'auto', cellOptions: { type: 'auto' }, inspect: false }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [{ matcher: { id: 'byRegexp', options: '/IOPS/' }, properties: [{ id: 'unit', value: 'iops' }] }, { matcher: { id: 'byRegexp', options: '/Throughput/' }, properties: [{ id: 'unit', value: 'Bps' }] }, { matcher: { id: 'byName', options: 'Pod' }, properties: [{ id: 'links', value: [{ title: 'Drill down to pods', url: '/d/6581e46e4e5c7ba40a07646395ef7b23/k8s-resources-pod?${datasource:queryparam}&var-cluster=$cluster&var-namespace=$namespace&var-pod=${__data.fields.Pod}' }] }] }] }, options: { cellHeight: 'sm', footer: { countRows: false, fields: '', reducer: ['sum'], show: false }, showHeader: true }, pluginVersion: '11.5.2', transformations: [{ id: 'joinByField', options: { byField: 'pod', mode: 'outer' } }, { id: 'organize', options: { excludeByName: { Time: true, 'Time 1': true, 'Time 2': true, 'Time 3': true, 'Time 4': true, 'Time 5': true, 'Time 6': true }, indexByName: { 'Time 1': 0, 'Time 2': 1, 'Time 3': 2, 'Time 4': 3, 'Time 5': 4, 'Time 6': 5, 'Value #A': 7, 'Value #B': 8, 'Value #C': 9, 'Value #D': 10, 'Value #E': 11, 'Value #F': 12, pod: 6 }, renameByName: { 'Value #A': 'IOPS(Reads)', 'Value #B': 'IOPS(Writes)', 'Value #C': 'IOPS(Reads + Writes)', 'Value #D': 'Throughput(Read)', 'Value #E': 'Throughput(Write)', 'Value #F': 'Throughput(Read + Write)', pod: 'Pod' } } }] },
  ),
], setPanelIDs=false)
