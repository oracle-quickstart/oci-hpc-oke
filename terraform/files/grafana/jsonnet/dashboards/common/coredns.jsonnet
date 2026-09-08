local panel = import '../../lib/dashboard-panel.libsonnet';
local target = import '../../lib/dashboard-target.libsonnet';
local variable = import '../../lib/dashboard-variable.libsonnet';
local g = import '../../lib/g.libsonnet';

g.dashboard.new('CoreDNS')
+ g.dashboard.withUid('vkQ0UHxik')
+ g.dashboard.withDescription('A dashboard for the CoreDNS DNS server with updated metrics for version 1.7.0+.  Based on the CoreDNS dashboard by buhay.')
+ g.dashboard.withTimezone('utc')
+ g.dashboard.withRefresh('10s')
+ g.dashboard.time.withFrom('now-3h')
+ g.dashboard.withVariables([
  variable.datasource('datasource', 'prometheus', { current: { text: 'Prometheus', value: 'prometheus' }, includeAll: false, options: [], refresh: 1, regex: '' }),
  variable.query('cluster', { type: 'prometheus', uid: '$datasource' }, 'label_values(coredns_dns_requests_total, cluster)', { allValue: '.*', current: { text: 'All', value: '$__all' }, definition: 'label_values(coredns_dns_requests_total, cluster)', hide: 2, includeAll: true, label: 'Cluster', options: [], refresh: 2, regex: '', sort: 1 }),
  variable.query('job', { type: 'prometheus', uid: '${datasource}' }, { qryType: 1, query: 'label_values(coredns_dns_requests_total{cluster=~"$cluster"},job)', refId: 'PrometheusVariableQueryEditor-VariableQuery' }, { allValue: '.*', current: { text: 'All', value: '$__all' }, definition: 'label_values(coredns_dns_requests_total{cluster=~"$cluster"},job)', includeAll: true, label: 'Job', options: [], refresh: 2, regex: '', sort: 1 }),
  variable.query('instance', { type: 'prometheus', uid: '$datasource' }, 'label_values(coredns_dns_requests_total{job=~"$job",cluster=~"$cluster"}, instance)', { allValue: '.*', current: { text: 'All', value: '$__all' }, definition: 'label_values(coredns_dns_requests_total{job=~"$job",cluster=~"$cluster"}, instance)', includeAll: true, label: 'Instance', options: [], refresh: 2, regex: '', sort: 3 }),
])
+ { annotations: { list: [{ builtIn: 1, datasource: { type: 'datasource', uid: 'grafana' }, enable: true, hide: true, iconColor: 'rgba(0, 211, 255, 1)', name: 'Annotations & Alerts', type: 'dashboard' }] }, links: [{ icon: 'external link', tags: [], targetBlank: true, title: 'CoreDNS.io', type: 'link', url: 'https://coredns.io' }], tags: ['dns', 'coredns'] }
+ g.dashboard.withPanels([
  panel.timeSeries(
    'Requests (total)',
    [
      target.prometheus('$datasource', 'sum(rate(coredns_dns_request_count_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) by (proto) or\nsum(rate(coredns_dns_requests_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) by (proto)', { format: 'time_series', interval: '1m', intervalFactor: 2, legendFormat: '{{ proto }}', refId: 'A', step: 60 }),
    ],
    { h: 7, w: 8, x: 0, y: 0 },
    2,
    config={ datasource: { uid: '$datasource' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 2, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, links: [], mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'pps' }, overrides: [] }, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { hideZeros: false, mode: 'multi', sort: 'desc' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Requests (by qtype)',
    [
      target.prometheus('$datasource', 'sum(rate(coredns_dns_request_type_count_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) by (type) or \nsum(rate(coredns_dns_requests_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) by (type)', { interval: '1m', intervalFactor: 2, legendFormat: '{{ type }}', refId: 'A', step: 60 }),
    ],
    { h: 7, w: 8, x: 8, y: 0 },
    4,
    config={ datasource: { uid: '$datasource' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 2, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, links: [], mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'pps' }, overrides: [] }, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { hideZeros: false, mode: 'multi', sort: 'desc' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Requests (by zone)',
    [
      target.prometheus('$datasource', 'sum(rate(coredns_dns_request_count_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) by (zone) or\nsum(rate(coredns_dns_requests_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) by (zone)', { interval: '1m', intervalFactor: 2, legendFormat: '{{ zone }}', refId: 'A', step: 60 }),
    ],
    { h: 7, w: 8, x: 16, y: 0 },
    6,
    config={ datasource: { uid: '$datasource' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 2, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, links: [], mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'pps' }, overrides: [] }, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { hideZeros: false, mode: 'multi', sort: 'desc' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Requests (DO bit)',
    [
      target.prometheus('$datasource', 'sum(rate(coredns_dns_request_do_count_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) or\nsum(rate(coredns_dns_do_requests_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m]))', { interval: '1m', intervalFactor: 2, legendFormat: 'DO', refId: 'A', step: 40 }),
      target.prometheus('$datasource', 'sum(rate(coredns_dns_request_count_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) or\nsum(rate(coredns_dns_requests_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m]))', { interval: '1m', intervalFactor: 2, legendFormat: 'total', refId: 'B', step: 40 }),
    ],
    { h: 7, w: 12, x: 0, y: 7 },
    8,
    config={ datasource: { uid: '$datasource' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 2, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, links: [], mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'pps' }, overrides: [] }, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { hideZeros: false, mode: 'multi', sort: 'desc' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Requests (size, udp)',
    [
      target.prometheus('$datasource', 'histogram_quantile(0.99, sum(rate(coredns_dns_request_size_bytes_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance",proto="udp"}[5m])) by (le,proto))', { interval: '1m', intervalFactor: 2, legendFormat: '{{ proto }}:99 ', refId: 'A', step: 60 }),
      target.prometheus('$datasource', 'histogram_quantile(0.90, sum(rate(coredns_dns_request_size_bytes_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance",proto="udp"}[5m])) by (le,proto))', { intervalFactor: 2, legendFormat: '{{ proto }}:90', refId: 'B', step: 60 }),
      target.prometheus('$datasource', 'histogram_quantile(0.50, sum(rate(coredns_dns_request_size_bytes_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance",proto="udp"}[5m])) by (le,proto))', { intervalFactor: 2, legendFormat: '{{ proto }}:50', refId: 'C', step: 60 }),
    ],
    { h: 7, w: 6, x: 12, y: 7 },
    10,
    config={ datasource: { uid: '$datasource' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 2, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, links: [], mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [{ matcher: { id: 'byName', options: 'tcp:90' }, properties: [{ id: 'unit', value: 'short' }] }, { matcher: { id: 'byName', options: 'tcp:99 ' }, properties: [{ id: 'unit', value: 'short' }] }, { matcher: { id: 'byName', options: 'tcp:50' }, properties: [{ id: 'unit', value: 'short' }] }] }, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { hideZeros: false, mode: 'multi', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Requests (size,tcp)',
    [
      target.prometheus('$datasource', 'histogram_quantile(0.99, sum(rate(coredns_dns_request_size_bytes_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance",proto="tcp"}[5m])) by (le,proto))', { format: 'time_series', interval: '1m', intervalFactor: 2, legendFormat: '{{ proto }}:99 ', refId: 'A', step: 60 }),
      target.prometheus('$datasource', 'histogram_quantile(0.90, sum(rate(coredns_dns_request_size_bytes_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance",proto="tcp"}[5m])) by (le,proto))', { format: 'time_series', interval: '1m', intervalFactor: 2, legendFormat: '{{ proto }}:90', refId: 'B', step: 60 }),
      target.prometheus('$datasource', 'histogram_quantile(0.50, sum(rate(coredns_dns_request_size_bytes_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance",proto="tcp"}[5m])) by (le,proto))', { format: 'time_series', interval: '1m', intervalFactor: 2, legendFormat: '{{ proto }}:50', refId: 'C', step: 60 }),
    ],
    { h: 7, w: 6, x: 18, y: 7 },
    12,
    config={ datasource: { uid: '$datasource' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 2, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, links: [], mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [] }, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { hideZeros: false, mode: 'multi', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Responses (by rcode)',
    [
      target.prometheus('$datasource', 'sum(rate(coredns_dns_response_rcode_count_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) by (rcode) or\nsum(rate(coredns_dns_responses_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) by (rcode)', { interval: '1m', intervalFactor: 2, legendFormat: '{{ rcode }}', refId: 'A', step: 40 }),
    ],
    { h: 7, w: 12, x: 0, y: 14 },
    14,
    config={ datasource: { uid: '$datasource' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 2, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, links: [], mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'pps' }, overrides: [] }, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { hideZeros: false, mode: 'multi', sort: 'desc' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Responses (duration)',
    [
      target.prometheus('$datasource', 'histogram_quantile(0.99, sum(rate(coredns_dns_request_duration_seconds_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) by (le, job))', { format: 'time_series', intervalFactor: 2, legendFormat: '99%', refId: 'A', step: 40 }),
      target.prometheus('$datasource', 'histogram_quantile(0.90, sum(rate(coredns_dns_request_duration_seconds_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) by (le))', { format: 'time_series', intervalFactor: 2, legendFormat: '90%', refId: 'B', step: 40 }),
      target.prometheus('$datasource', 'histogram_quantile(0.50, sum(rate(coredns_dns_request_duration_seconds_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) by (le))', { format: 'time_series', intervalFactor: 2, legendFormat: '50%', refId: 'C', step: 40 }),
    ],
    { h: 7, w: 12, x: 12, y: 14 },
    32,
    config={ datasource: { uid: '$datasource' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 2, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, links: [], mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 's' }, overrides: [] }, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { hideZeros: false, mode: 'multi', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Responses (size, udp)',
    [
      target.prometheus('$datasource', 'histogram_quantile(0.99, sum(rate(coredns_dns_response_size_bytes_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance",proto="udp"}[5m])) by (le,proto)) ', { interval: '1m', intervalFactor: 2, legendFormat: '{{ proto }}:99%', refId: 'A', step: 40 }),
      target.prometheus('$datasource', 'histogram_quantile(0.90, sum(rate(coredns_dns_response_size_bytes_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance",proto="udp"}[5m])) by (le,proto)) ', { interval: '1m', intervalFactor: 2, legendFormat: '{{ proto }}:90%', refId: 'B', step: 40 }),
      target.prometheus('$datasource', 'histogram_quantile(0.50, sum(rate(coredns_dns_response_size_bytes_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance",proto="udp"}[5m])) by (le,proto)) ', { hide: false, intervalFactor: 2, legendFormat: '{{ proto }}:50%', metric: '', refId: 'C', step: 40 }),
    ],
    { h: 7, w: 12, x: 0, y: 21 },
    18,
    config={ datasource: { uid: '$datasource' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 2, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, links: [], mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [{ matcher: { id: 'byName', options: 'tcp:50%' }, properties: [{ id: 'unit', value: 'short' }] }, { matcher: { id: 'byName', options: 'tcp:90%' }, properties: [{ id: 'unit', value: 'short' }] }, { matcher: { id: 'byName', options: 'tcp:99%' }, properties: [{ id: 'unit', value: 'short' }] }] }, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { hideZeros: false, mode: 'multi', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Responses (size, tcp)',
    [
      target.prometheus('$datasource', 'histogram_quantile(0.99, sum(rate(coredns_dns_response_size_bytes_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance",proto="tcp"}[5m])) by (le,proto)) ', { format: 'time_series', intervalFactor: 2, legendFormat: '{{ proto }}:99%', refId: 'A', step: 40 }),
      target.prometheus('$datasource', 'histogram_quantile(0.90, sum(rate(coredns_dns_response_size_bytes_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance",proto="tcp"}[5m])) by (le,proto)) ', { format: 'time_series', intervalFactor: 2, legendFormat: '{{ proto }}:90%', refId: 'B', step: 40 }),
      target.prometheus('$datasource', 'histogram_quantile(0.50, sum(rate(coredns_dns_response_size_bytes_bucket{job=~"$job",cluster=~"$cluster",instance=~"$instance",proto="tcp"}[5m])) by (le, proto)) ', { format: 'time_series', intervalFactor: 2, legendFormat: '{{ proto }}:50%', metric: '', refId: 'C', step: 40 }),
    ],
    { h: 7, w: 12, x: 12, y: 21 },
    20,
    config={ datasource: { uid: '$datasource' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 2, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, links: [], mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [] }, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { hideZeros: false, mode: 'multi', sort: 'none' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Cache (size)',
    [
      target.prometheus('$datasource', 'sum(coredns_cache_size{job=~"$job",cluster=~"$cluster",instance=~"$instance"}) by (type) or\nsum(coredns_cache_entries{job=~"$job",cluster=~"$cluster",instance=~"$instance"}) by (type)', { interval: '1m', intervalFactor: 2, legendFormat: '{{ type }}', refId: 'A', step: 40 }),
    ],
    { h: 7, w: 12, x: 0, y: 28 },
    22,
    config={ datasource: { uid: '$datasource' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 2, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, links: [], mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'decbytes' }, overrides: [] }, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { hideZeros: false, mode: 'multi', sort: 'desc' } }, pluginVersion: '11.5.2' },
  ),
  panel.timeSeries(
    'Cache (hitrate)',
    [
      target.prometheus('$datasource', 'sum(rate(coredns_cache_hits_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) by (type)', { hide: false, intervalFactor: 2, legendFormat: 'hits:{{ type }}', refId: 'A', step: 40 }),
      target.prometheus('$datasource', 'sum(rate(coredns_cache_misses_total{job=~"$job",cluster=~"$cluster",instance=~"$instance"}[5m])) by (type)', { hide: false, intervalFactor: 2, legendFormat: 'misses', refId: 'B', step: 40 }),
    ],
    { h: 7, w: 12, x: 12, y: 28 },
    24,
    config={ datasource: { uid: '$datasource' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, barWidthFactor: 0.6, drawStyle: 'line', fillOpacity: 10, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 2, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: true, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, links: [], mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'pps' }, overrides: [] }, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { hideZeros: false, mode: 'multi', sort: 'desc' } }, pluginVersion: '11.5.2' },
  ),
], setPanelIDs=false)
