local panel = import '../../lib/dashboard-panel.libsonnet';
local target = import '../../lib/dashboard-target.libsonnet';
local variable = import '../../lib/dashboard-variable.libsonnet';
local g = import '../../lib/g.libsonnet';

g.dashboard.new('Kubernetes / API server')
+ g.dashboard.withUid('09ec8aa1e996d6ffcd6817bbaff4db1b')
+ g.dashboard.withTimezone('utc')
+ g.dashboard.withRefresh('10s')
+ g.dashboard.time.withFrom('now-1h')
+ g.dashboard.withVariables([
  variable.datasource('datasource', 'prometheus', { current: { text: 'default', value: 'default' }, label: 'Data source', options: [], refresh: 1, regex: '' }),
  variable.query('cluster', { type: 'prometheus', uid: '${datasource}' }, 'label_values(up{job="apiserver"}, cluster)', { allValue: '.*', current: { text: '', value: '' }, hide: 2, label: 'cluster', options: [], refresh: 2, sort: 1 }),
  variable.query('instance', { type: 'prometheus', uid: '${datasource}' }, 'label_values(up{job="apiserver", cluster="$cluster"}, instance)', { current: { text: 'All', value: '$__all' }, includeAll: true, options: [], refresh: 2, sort: 1 }),
])
+ { annotations: { list: [{ builtIn: 1, datasource: { type: 'grafana', uid: '-- Grafana --' }, enable: true, hide: true, iconColor: 'rgba(0, 211, 255, 1)', name: 'Annotations & Alerts', type: 'dashboard' }] }, links: [{ asDropdown: true, includeVars: true, keepTime: true, tags: ['kubernetes-mixin'], targetBlank: false, title: 'Kubernetes', type: 'dashboards' }], tags: ['kubernetes-mixin'] }
+ g.dashboard.withPanels([
  panel.text('', { h: 3, w: 24, x: 0, y: 0 }, 1, config={ description: 'The SLO (service level objective) and other metrics displayed on this dashboard are for informational purposes only.', fieldConfig: { defaults: {}, overrides: [] }, options: { code: { language: 'plaintext', showLineNumbers: false, showMiniMap: false }, content: 'The SLO (service level objective) and other metrics displayed on this dashboard are for informational purposes only.', mode: 'markdown' }, pluginVersion: '11.5.2', transparent: true }),
  panel.stat(
    'Availability (30d) > 99.000%',
    [
      target.prometheus('${datasource}', 'apiserver_request:availability30d{verb="all", cluster="$cluster"}', { refId: 'A' }),
    ],
    { h: 7, w: 8, x: 0, y: 3 },
    2,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, description: 'How many percent of requests (both read and write) in 30 days have been answered successfully and fast enough?', fieldConfig: { defaults: { decimals: 3, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'percentunit' }, overrides: [] }, interval: '1m', options: { colorMode: 'value', graphMode: 'area', justifyMode: 'auto', orientation: 'auto', percentChangeColorMode: 'standard', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showPercentChange: false, textMode: 'auto', wideLayout: true }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'ErrorBudget (30d) > 99.000%',
    [
      target.prometheus('${datasource}', '100 * (apiserver_request:availability30d{verb="all", cluster="$cluster"} - 0.990000)', { legendFormat: 'errorbudget', refId: 'A' }),
    ],
    { h: 7, w: 16, x: 8, y: 3 },
    3,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, description: 'How much error budget is left looking at our 0.990% availability guarantees?', fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 100, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, decimals: 3, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'percentunit' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: [], displayMode: 'list', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.stat(
    'Read Availability (30d)',
    [
      target.prometheus('${datasource}', 'apiserver_request:availability30d{verb="read", cluster="$cluster"}', { refId: 'A' }),
    ],
    { h: 7, w: 6, x: 0, y: 10 },
    4,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, description: 'How many percent of read requests (LIST,GET) in 30 days have been answered successfully and fast enough?', fieldConfig: { defaults: { decimals: 3, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'percentunit' }, overrides: [] }, interval: '1m', options: { colorMode: 'value', graphMode: 'area', justifyMode: 'auto', orientation: 'auto', percentChangeColorMode: 'standard', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showPercentChange: false, textMode: 'auto', wideLayout: true }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Read SLI - Requests',
    [
      target.prometheus('${datasource}', 'sum by (code) (code_resource:apiserver_request_total:rate5m{verb="read", cluster="$cluster"})', { legendFormat: '{{ code }}', refId: 'A' }),
    ],
    { h: 7, w: 6, x: 6, y: 10 },
    5,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, description: 'How many read requests (LIST,GET) per second do the apiservers get by code?', fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 100, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'reqps' }, overrides: [{ matcher: { id: 'byRegexp', options: '/2../i' }, properties: [{ id: 'color', value: '#56A64B' }] }, { matcher: { id: 'byRegexp', options: '/3../i' }, properties: [{ id: 'color', value: '#F2CC0C' }] }, { matcher: { id: 'byRegexp', options: '/4../i' }, properties: [{ id: 'color', value: '#3274D9' }] }, { matcher: { id: 'byRegexp', options: '/5../i' }, properties: [{ id: 'color', value: '#E02F44' }] }] }, interval: '1m', options: { legend: { asTable: true, calcs: [], displayMode: 'list', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Read SLI - Errors',
    [
      target.prometheus('${datasource}', 'sum by (resource) (code_resource:apiserver_request_total:rate5m{verb="read",code=~"5..", cluster="$cluster"}) / sum by (resource) (code_resource:apiserver_request_total:rate5m{verb="read", cluster="$cluster"})', { legendFormat: '{{ resource }}', refId: 'A' }),
    ],
    { h: 7, w: 6, x: 12, y: 10 },
    6,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, description: 'How many percent of read requests (LIST,GET) per second are returned with errors (5xx)?', fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'percentunit' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: [], displayMode: 'list', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Read SLI - Duration',
    [
      target.prometheus('${datasource}', 'cluster_quantile:apiserver_request_sli_duration_seconds:histogram_quantile{verb="read", cluster="$cluster"}', { legendFormat: '{{ resource }}', refId: 'A' }),
    ],
    { h: 7, w: 6, x: 18, y: 10 },
    7,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, description: 'How many seconds is the 99th percentile for reading (LIST|GET) a given resource?', fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 's' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: [], displayMode: 'list', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.stat(
    'Write Availability (30d)',
    [
      target.prometheus('${datasource}', 'apiserver_request:availability30d{verb="write", cluster="$cluster"}', { refId: 'A' }),
    ],
    { h: 7, w: 6, x: 0, y: 17 },
    8,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, description: 'How many percent of write requests (POST|PUT|PATCH|DELETE) in 30 days have been answered successfully and fast enough?', fieldConfig: { defaults: { decimals: 3, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'percentunit' }, overrides: [] }, interval: '1m', options: { colorMode: 'value', graphMode: 'area', justifyMode: 'auto', orientation: 'auto', percentChangeColorMode: 'standard', reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false }, showPercentChange: false, textMode: 'auto', wideLayout: true }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Write SLI - Requests',
    [
      target.prometheus('${datasource}', 'sum by (code) (code_resource:apiserver_request_total:rate5m{verb="write", cluster="$cluster"})', { legendFormat: '{{ code }}', refId: 'A' }),
    ],
    { h: 7, w: 6, x: 6, y: 17 },
    9,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, description: 'How many write requests (POST|PUT|PATCH|DELETE) per second do the apiservers get by code?', fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 100, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'reqps' }, overrides: [{ matcher: { id: 'byRegexp', options: '/2../i' }, properties: [{ id: 'color', value: '#56A64B' }] }, { matcher: { id: 'byRegexp', options: '/3../i' }, properties: [{ id: 'color', value: '#F2CC0C' }] }, { matcher: { id: 'byRegexp', options: '/4../i' }, properties: [{ id: 'color', value: '#3274D9' }] }, { matcher: { id: 'byRegexp', options: '/5../i' }, properties: [{ id: 'color', value: '#E02F44' }] }] }, interval: '1m', options: { legend: { asTable: true, calcs: [], displayMode: 'list', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Write SLI - Errors',
    [
      target.prometheus('${datasource}', 'sum by (resource) (code_resource:apiserver_request_total:rate5m{verb="write",code=~"5..", cluster="$cluster"}) / sum by (resource) (code_resource:apiserver_request_total:rate5m{verb="write", cluster="$cluster"})', { legendFormat: '{{ resource }}', refId: 'A' }),
    ],
    { h: 7, w: 6, x: 12, y: 17 },
    10,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, description: 'How many percent of write requests (POST|PUT|PATCH|DELETE) per second are returned with errors (5xx)?', fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'percentunit' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: [], displayMode: 'list', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Write SLI - Duration',
    [
      target.prometheus('${datasource}', 'cluster_quantile:apiserver_request_sli_duration_seconds:histogram_quantile{verb="write", cluster="$cluster"}', { legendFormat: '{{ resource }}', refId: 'A' }),
    ],
    { h: 7, w: 6, x: 18, y: 17 },
    11,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, description: 'How many seconds is the 99th percentile for writing (POST|PUT|PATCH|DELETE) a given resource?', fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 's' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: [], displayMode: 'list', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Work Queue Add Rate',
    [
      target.prometheus('${datasource}', 'sum(rate(workqueue_adds_total{job="apiserver", instance=~"$instance", cluster="$cluster"}[$__rate_interval])) by (instance, name)', { legendFormat: '{{instance}} {{name}}', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 0, y: 24 },
    12,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'ops' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: [], displayMode: 'list', placement: 'right', showLegend: false }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Work Queue Depth',
    [
      target.prometheus('${datasource}', 'sum(rate(workqueue_depth{job="apiserver", instance=~"$instance", cluster="$cluster"}[$__rate_interval])) by (instance, name)', { legendFormat: '{{instance}} {{name}}', refId: 'A' }),
    ],
    { h: 7, w: 12, x: 12, y: 24 },
    13,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'short' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: [], displayMode: 'list', placement: 'right', showLegend: false }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Work Queue Latency',
    [
      target.prometheus('${datasource}', 'histogram_quantile(0.99, sum(rate(workqueue_queue_duration_seconds_bucket{job="apiserver", instance=~"$instance", cluster="$cluster"}[$__rate_interval])) by (instance, name, le))', { legendFormat: '{{instance}} {{name}}', refId: 'A' }),
    ],
    { h: 7, w: 24, x: 0, y: 31 },
    14,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 's' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: ['lastNotNull'], displayMode: 'list', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Memory',
    [
      target.prometheus('${datasource}', 'process_resident_memory_bytes{job="apiserver",instance=~"$instance", cluster="$cluster"}', { legendFormat: '{{instance}}', refId: 'A' }),
    ],
    { h: 7, w: 8, x: 0, y: 38 },
    15,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: [], displayMode: 'list', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'CPU usage',
    [
      target.prometheus('${datasource}', 'rate(process_cpu_seconds_total{job="apiserver",instance=~"$instance", cluster="$cluster"}[$__rate_interval])', { legendFormat: '{{instance}}', refId: 'A' }),
    ],
    { h: 7, w: 8, x: 8, y: 38 },
    16,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'short' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: [], displayMode: 'list', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Goroutines',
    [
      target.prometheus('${datasource}', 'go_goroutines{job="apiserver",instance=~"$instance", cluster="$cluster"}', { legendFormat: '{{instance}}', refId: 'A' }),
    ],
    { h: 7, w: 8, x: 16, y: 38 },
    17,
    config={ datasource: { type: 'datasource', uid: '-- Mixed --' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'short' }, overrides: [] }, interval: '1m', options: { legend: { asTable: true, calcs: [], displayMode: 'list', placement: 'right', showLegend: true }, tooltip: { hideZeros: false, mode: 'single', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
], setPanelIDs=false)
