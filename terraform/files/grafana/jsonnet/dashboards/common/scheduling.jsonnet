local panel = import '../../lib/dashboard-panel.libsonnet';
local target = import '../../lib/dashboard-target.libsonnet';
local variable = import '../../lib/dashboard-variable.libsonnet';
local g = import '../../lib/g.libsonnet';

g.dashboard.new('Scheduling')
+ g.dashboard.withUid('abc4098b-10fd-4fc6-8eaa-e302a5a1b573')
+ g.dashboard.withTimezone('')
+ g.dashboard.time.withFrom('now-12h')
+ { annotations: { list: [{ builtIn: 1, datasource: { type: 'grafana', uid: '-- Grafana --' }, enable: true, hide: true, iconColor: 'rgba(0, 211, 255, 1)', name: 'Annotations & Alerts', type: 'dashboard' }] }, links: [], tags: [] }
+ g.dashboard.withPanels([
  panel.timeSeries(
    'Waiting Pods by Reason',
    [
      target.prometheus('prometheus', 'sum by(name, reason, namespace) (topk(5, label_replace(sum by(namespace, reason, pod) (max_over_time(kube_pod_container_status_waiting_reason[$__interval])) > 0, "name", "$1", "pod", "(.*)-[a-z0-9]*$")))', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '{{namespace}}/{{name}} {{reason}}', range: true, refId: 'B', useBackend: false }),
    ],
    { h: 7, w: 24, x: 0, y: 0 },
    6,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'bars', fillOpacity: 100, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'stepBefore', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['last'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last', sortDesc: true }, tooltip: { mode: 'multi', sort: 'desc' } } },
  ),
  panel.timeSeries(
    'Terminated Pods',
    [
      target.prometheus('prometheus', 'sum by(namespace, reason) (max_over_time(kube_pod_container_status_terminated_reason[$__interval])) > 0', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '{{reason}}: {{namespace}}', range: true, refId: 'A', useBackend: false }),
    ],
    { h: 6, w: 12, x: 0, y: 7 },
    5,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'bars', fillOpacity: 100, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'stepBefore', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['sum'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Total', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Terminated Pods',
    [
      target.prometheus('prometheus', 'sum by(namespace, reason, pod) (max_over_time(kube_pod_container_status_terminated_reason[$__interval])) > 0', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '{{reason}}: {{namespace}} {{pod}}', range: true, refId: 'A', useBackend: false }),
    ],
    { h: 6, w: 12, x: 12, y: 7 },
    16,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'bars', fillOpacity: 100, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'stepBefore', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['last'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'GPUs',
    [
      target.prometheus('prometheus', 'max(sum by(instance) (kube_node_status_allocatable{resource="nvidia_com_gpu"}))', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: 'Allocatable', range: true, refId: 'Allocatable', useBackend: false }),
      target.prometheus('prometheus', 'sum by(namespace) (kube_pod_container_resource_requests{resource="nvidia_com_gpu"})', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: 'Request {{namespace}}', range: true, refId: 'Requests', useBackend: false }),
      target.expression({ datasource: { name: 'Expression', type: '__expr__', uid: '__expr__' }, expression: '$Allocatable - $Requests', hide: false, refId: 'Remaining', type: 'math' }),
    ],
    { h: 6, w: 12, x: 0, y: 13 },
    4,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, description: '', fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'bars', fillOpacity: 84, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [{ matcher: { id: 'byName', options: 'Allocatable' }, properties: [{ id: 'custom.drawStyle', value: 'line' }, { id: 'custom.fillOpacity', value: 0 }, { id: 'custom.insertNulls', value: 3600000 }] }, { matcher: { id: 'byName', options: 'Util' }, properties: [{ id: 'custom.drawStyle', value: 'line' }, { id: 'custom.axisPlacement', value: 'right' }, { id: 'custom.fillOpacity', value: 5 }, { id: 'unit', value: 'percentunit' }, { id: 'noValue', value: '0' }] }, { matcher: { id: 'byName', options: 'Remaining' }, properties: [{ id: 'custom.drawStyle', value: 'line' }, { id: 'custom.fillOpacity', value: 0 }] }] }, maxDataPoints: 100, options: { legend: { calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last *', sortDesc: true }, tooltip: { mode: 'multi', sort: 'desc' } } },
  ),
  panel.timeSeries(
    'Pod Status Reasons by Namespace',
    [
      target.prometheus('prometheus', 'sum by(namespace, reason) (max_over_time(kube_pod_status_reason[$__interval])) > 0', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '{{reason}}: {{namespace}}', range: true, refId: 'A', useBackend: false }),
    ],
    { h: 6, w: 12, x: 12, y: 13 },
    1,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'bars', fillOpacity: 100, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'stepBefore', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['last'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Nodes with GPU Scheduling Impact',
    [
      target.prometheus('prometheus', 'bottomk(10,(max by(node) (max_over_time(kube_node_status_allocatable{resource="nvidia_com_gpu"}[$__interval])) - sum by(node) (max_over_time(kube_pod_container_resource_requests{resource="nvidia_com_gpu"}[$__interval]))) != 8) >= -10000', { disableTextWrap: false, editorMode: 'code', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '{{node}} {{node_prefix}}', range: true, refId: 'Remaining', useBackend: false }),
    ],
    { h: 6, w: 12, x: 0, y: 19 },
    10,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: 'Available GPUs', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'stepBefore', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'none' }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['last'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last', sortDesc: false }, tooltip: { mode: 'multi', sort: 'desc' } } },
  ),
  panel.timeSeries(
    'Extra Taints',
    [
      target.prometheus('prometheus', 'sum by(key) (max_over_time(kube_node_spec_taint{effect=~"NoSchedule|NoExecute", key!="nvidia.com/gpu"}[$__interval]))', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '{{key}}', range: true, refId: 'A', useBackend: false }),
    ],
    { h: 6, w: 12, x: 12, y: 19 },
    14,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'bars', fillOpacity: 100, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'stepBefore', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['last'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last', sortDesc: true }, tooltip: { mode: 'multi', sort: 'desc' } } },
  ),
  panel.timeSeries(
    'Node Allocatable Memory by Pool',
    [
      target.prometheus('prometheus', '(sum by(node_prefix) (label_replace(max by(node) (max_over_time(kube_node_status_allocatable{resource="memory"}[$__interval])), "node_prefix", "$2", "node", "(.*)-(gpu|cpu)-.*")) > 0) - (sum by(node_prefix) (label_replace(sum by(node) (max_over_time(kube_pod_container_resource_requests{resource="memory"}[$__interval])), "node_prefix", "$2", "node", "(.*)-(gpu|cpu)-.*")) > 0)', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '{{node}} {{node_prefix}}', range: true, refId: 'Remaining', useBackend: false }),
    ],
    { h: 6, w: 8, x: 0, y: 25 },
    9,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'stepBefore', lineWidth: 1, pointSize: 5, scaleDistribution: { log: 2, type: 'log' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['last'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Unavailable DaemonSet Pods',
    [
      target.prometheus('prometheus', 'max by(daemonset) (max_over_time(kube_daemonset_status_number_unavailable[$__interval])) > 0', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'A', useBackend: false }),
    ],
    { h: 7, w: 16, x: 8, y: 25 },
    2,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last *', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Node Allocatable CPU Cores by Pool',
    [
      target.prometheus('prometheus', '(sum by(node_prefix) (label_replace(max by(node) (max_over_time(kube_node_status_allocatable{resource="cpu"}[$__interval])), "node_prefix", "$2", "node", "(.*)-(gpu|cpu)-.*")) > 0) - (sum by(node_prefix) (label_replace(sum by(node) (max_over_time(kube_pod_container_resource_requests{resource="cpu"}[$__interval])), "node_prefix", "$2", "node", "(.*)-(gpu|cpu)-.*")) > 0)', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '{{node_prefix}}', range: true, refId: 'Remaining', useBackend: false }),
    ],
    { h: 6, w: 8, x: 0, y: 31 },
    12,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'stepBefore', lineWidth: 1, pointSize: 5, scaleDistribution: { log: 2, type: 'log' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'none' }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['last'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Node Software Versions',
    [
      target.prometheus('prometheus', 'sum by(kubeproxy_version) (max by(node, kubeproxy_version) (max_over_time(kube_node_info[$__interval])))', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: 'kube-proxy {{kubeproxy_version}}', range: true, refId: 'A', useBackend: false }),
      target.prometheus('prometheus', 'sum by(kubelet_version) (max by(node, kubelet_version) (max_over_time(kube_node_info[$__interval])))', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: 'kubelet {{kubelet_version}}', range: true, refId: 'B', useBackend: false }),
      target.prometheus('prometheus', 'sum by(container_runtime_version) (max by(node, container_runtime_version) (max_over_time(kube_node_info[$__interval])))', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '{{container_runtime_version}}', range: true, refId: 'C', useBackend: false }),
      target.prometheus('prometheus', 'sum by(kernel_version) (max by(node, kernel_version) (max_over_time(kube_node_info[$__interval])))', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: 'linux {{kernel_version}}', range: true, refId: 'D', useBackend: false }),
    ],
    { h: 6, w: 16, x: 8, y: 32 },
    15,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'stepBefore', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['last'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last', sortDesc: true }, tooltip: { mode: 'multi', sort: 'desc' } } },
  ),
  panel.timeSeries(
    'Node Lowest Allocatable Ephemeral Storage by Pool',
    [
      target.prometheus('prometheus', '(min by(node_prefix) (label_replace(min by(node) (max_over_time(kube_node_status_allocatable{resource="ephemeral_storage"}[$__interval])), "node_prefix", "$2", "node", "(.*)-(gpu|cpu)-.*")) > 0) - (min by(node_prefix) (label_replace(min by(node) (max_over_time(kube_pod_container_resource_requests{resource="ephemeral_storage"}[$__interval])), "node_prefix", "$2", "node", "(.*)-(gpu|cpu)-.*")) > 0)', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '{{node_prefix}}', range: true, refId: 'Remaining', useBackend: false }),
    ],
    { h: 6, w: 8, x: 0, y: 37 },
    13,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'stepBefore', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['last'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Node Error Conditions',
    [
      target.prometheus('prometheus', 'sum(max by(node) (max_over_time(kube_node_status_condition{condition="Ready", status="false"}[$__interval])) > 0)', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: 'NotReady', range: true, refId: 'A', useBackend: false }),
      target.prometheus('prometheus', 'sum(max by(node) (max_over_time(kube_node_status_condition{condition="MemoryPressure", status="true"}[$__interval]))) > 0', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: 'MemoryPressure', range: true, refId: 'B', useBackend: false }),
      target.prometheus('prometheus', 'sum(max by(node) (max_over_time(kube_node_status_condition{condition="DiskPressure", status="true"}[$__interval]))) > 0', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: 'DiskPressure', range: true, refId: 'C', useBackend: false }),
      target.prometheus('prometheus', 'sum(max by(node) (max_over_time(kube_node_status_condition{condition="PIDPressure", status="true"}[$__interval]))) > 0', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: 'PIDPressure', range: true, refId: 'D', useBackend: false }),
    ],
    { h: 6, w: 12, x: 8, y: 38 },
    7,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'bars', fillOpacity: 100, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'stepBefore', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['last'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last *', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
], setPanelIDs=false)
