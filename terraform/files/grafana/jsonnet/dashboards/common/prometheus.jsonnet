local panel = import '../../lib/dashboard-panel.libsonnet';
local target = import '../../lib/dashboard-target.libsonnet';
local variable = import '../../lib/dashboard-variable.libsonnet';
local g = import '../../lib/g.libsonnet';

g.dashboard.new('Prometheus')
+ g.dashboard.withUid('e0b5e43c-3332-4ce3-a680-4919458f7b1d')
+ g.dashboard.withTimezone('')
+ g.dashboard.time.withFrom('now-24h')
+ { annotations: { list: [{ builtIn: 1, datasource: { type: 'grafana', uid: '-- Grafana --' }, enable: true, hide: true, iconColor: 'rgba(0, 211, 255, 1)', name: 'Annotations & Alerts', type: 'dashboard' }] }, links: [], tags: ['monitoring'] }
+ g.dashboard.withPanels([
  panel.row(
    'TSDB',
    [

    ],
    { h: 1, w: 24, x: 0, y: 0 },
    12,
    config={},
  ),
  panel.timeSeries(
    'Persistent Volume usage',
    [
      target.prometheus('$datasource', 'sum by(namespace) (kubelet_volume_stats_capacity_bytes{job="kubelet", metrics_path="/metrics"}) - sum by(namespace) (kubelet_volume_stats_available_bytes{job="kubelet", metrics_path="/metrics"})', { disableTextWrap: false, editorMode: 'builder', format: 'time_series', fullMetaSearch: false, includeNullMetadata: true, intervalFactor: 1, legendFormat: 'Used: {{namespace}}', range: true, refId: 'A', useBackend: false }),
      target.prometheus('$datasource', 'sum by(namespace) (kubelet_volume_stats_available_bytes{job="kubelet", metrics_path="/metrics"})', { disableTextWrap: false, editorMode: 'builder', format: 'time_series', fullMetaSearch: false, includeNullMetadata: true, intervalFactor: 1, legendFormat: 'Free: {{namespace}}', range: true, refId: 'B', useBackend: false }),
    ],
    { h: 6, w: 12, x: 0, y: 1 },
    10,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'never', spanNulls: false, stacking: { group: 'A', mode: 'normal' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [{ __systemRef: 'hideSeriesFrom', matcher: { id: 'byNames', options: { mode: 'exclude', names: ['Used: monitoring'], prefix: 'All except:', readOnly: true } }, properties: [{ id: 'custom.hideFrom', value: { legend: false, tooltip: false, viz: true } }] }] }, links: [], maxDataPoints: 100, options: { legend: { calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last *', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } }, pluginVersion: '10.2.2' },
  ),
  panel.timeSeries(
    'TSDB WAL storage',
    [
      target.prometheus('prometheus', 'max by(instance) (max_over_time(prometheus_tsdb_wal_storage_size_bytes[$__interval]))', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'A', useBackend: false }),
    ],
    { h: 6, w: 12, x: 12, y: 1 },
    2,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [] }, options: { legend: { calcs: ['last'], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'TSDB head chunks storage',
    [
      target.prometheus('prometheus', 'max(prometheus_tsdb_head_chunks_storage_size_bytes)', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'B', useBackend: false }),
    ],
    { h: 5, w: 12, x: 0, y: 7 },
    8,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [] }, options: { legend: { calcs: ['lastNotNull'], displayMode: 'table', placement: 'bottom', showLegend: true, sortBy: 'Last *', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'TSDB storage blocks',
    [
      target.prometheus('prometheus', 'max(prometheus_tsdb_storage_blocks_bytes)', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'A', useBackend: false }),
    ],
    { h: 5, w: 12, x: 12, y: 7 },
    6,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [] }, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Target metadata cache size',
    [
      target.prometheus('prometheus', 'max by(scrape_job) (prometheus_target_metadata_cache_bytes)', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'B', useBackend: false }),
    ],
    { h: 5, w: 24, x: 0, y: 12 },
    7,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'bytes' }, overrides: [] }, options: { legend: { calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last *', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.row(
    'Discovery',
    [

    ],
    { h: 1, w: 24, x: 0, y: 17 },
    11,
    config={ collapsed: false },
  ),
  panel.timeSeries(
    'Discovered targets',
    [
      target.prometheus('prometheus', 'label_replace(max by(config) (prometheus_sd_discovered_targets), "prefix", "$2", "config", "(serviceMonitor/monitoring)/(.*)")', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '{{prefix}}', range: true, refId: 'B', useBackend: false }),
    ],
    { h: 6, w: 19, x: 0, y: 18 },
    15,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { log: 2, type: 'log' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'none' }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last *', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Grafana dashboard GET',
    [
      target.prometheus('prometheus', 'max by(quantile) (max_over_time(grafana_api_dashboard_get_milliseconds[$__interval])) > 0', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'A', useBackend: false }),
    ],
    { h: 10, w: 5, x: 19, y: 18 },
    9,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'points', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'ms' }, overrides: [{ matcher: { id: 'byName', options: '0.99' }, properties: [{ id: 'color', value: { fixedColor: 'red', mode: 'fixed' } }] }, { matcher: { id: 'byName', options: '0.9' }, properties: [{ id: 'color', value: { fixedColor: 'light-red', mode: 'fixed' } }] }, { matcher: { id: 'byName', options: '0.5' }, properties: [{ id: 'color', value: { fixedColor: 'yellow', mode: 'fixed' } }] }] }, maxDataPoints: 100, options: { legend: { calcs: ['mean'], displayMode: 'table', placement: 'bottom', showLegend: true, sortBy: 'Mean', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Scrape jobs',
    [
      target.prometheus('prometheus', 'max by(scrape_job) (prometheus_target_scrape_pool_targets) > 0', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'A', useBackend: false }),
    ],
    { h: 6, w: 19, x: 0, y: 24 },
    4,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'none' }, overrides: [] }, options: { legend: { calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last *', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Kubernetes work queue depth',
    [
      target.prometheus('prometheus', 'max by(queue_name) (prometheus_sd_kubernetes_workqueue_depth)', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'B', useBackend: false }),
    ],
    { h: 7, w: 5, x: 19, y: 28 },
    14,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'bars', fillOpacity: 100, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], min: 0, thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'none' }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['lastNotNull'], displayMode: 'table', placement: 'bottom', showLegend: true, sortBy: 'Last *', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Ready',
    [
      target.prometheus('prometheus', 'min(min_over_time(prometheus_ready[$__interval]))', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'A', useBackend: false }),
    ],
    { h: 5, w: 3, x: 0, y: 30 },
    17,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'bars', fillOpacity: 100, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 3, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] } }, overrides: [] }, interval: '60s', maxDataPoints: 100, options: { legend: { calcs: [], displayMode: 'list', placement: 'bottom', showLegend: false }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Scrape errors',
    [
      target.prometheus('prometheus', 'max by(scrape_job) (prometheus_target_scrapes_exceeded_body_size_limit_total)', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'A', useBackend: false }),
      target.prometheus('prometheus', 'max by(scrape_job) (prometheus_target_scrape_pool_exceeded_label_limits_total)', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'B', useBackend: false }),
      target.prometheus('prometheus', 'max by(scrape_job) (prometheus_target_scrapes_exceeded_sample_limit_total)', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'C', useBackend: false }),
      target.prometheus('prometheus', 'max by(job) (prometheus_target_scrape_pool_exceeded_target_limit_total)', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'D', useBackend: false }),
      target.prometheus('prometheus', 'max by(job) (prometheus_target_scrape_pool_reloads_failed_total)', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, hide: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'E', useBackend: false }),
    ],
    { h: 5, w: 16, x: 3, y: 30 },
    5,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green', value: null }, { color: 'red', value: 80 }] }, unit: 'none' }, overrides: [] }, options: { legend: { calcs: ['lastNotNull'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Last *', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.row(
    'Queries',
    [

    ],
    { h: 1, w: 24, x: 0, y: 35 },
    16,
    config={ collapsed: false },
  ),
  panel.timeSeries(
    'Queries',
    [
      target.prometheus('prometheus', 'sum by(instance) (sum_over_time(prometheus_engine_queries[$__interval])) > 0', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '__auto', range: true, refId: 'A', useBackend: false }),
    ],
    { h: 8, w: 3, x: 0, y: 36 },
    3,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'bars', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green' }, { color: 'red', value: 80 }] }, unit: 'none' }, overrides: [] }, maxDataPoints: 100, options: { legend: { calcs: ['sum'], displayMode: 'list', placement: 'bottom', showLegend: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Prometheus HTTP success',
    [
      target.prometheus('prometheus', 'max by(code, handler) (increase(prometheus_http_requests_total{code=~"2.+"}[$__interval])) > 0', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '{{handler}} {{code}}', range: true, refId: 'A', useBackend: false }),
    ],
    { h: 8, w: 13, x: 3, y: 36 },
    1,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green' }, { color: 'red', value: 80 }] } }, overrides: [] }, interval: '1m', options: { legend: { calcs: ['mean'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Mean', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
  panel.timeSeries(
    'Prometheus HTTP failure',
    [
      target.prometheus('prometheus', 'sum by(code, handler) (sum_over_time(prometheus_http_requests_total{code!~"2.+"}[$__interval])) > 0', { disableTextWrap: false, editorMode: 'builder', fullMetaSearch: false, includeNullMetadata: true, instant: false, legendFormat: '{{handler}} {{code}}', range: true, refId: 'A', useBackend: false }),
    ],
    { h: 8, w: 8, x: 16, y: 36 },
    13,
    config={ datasource: { type: 'prometheus', uid: 'prometheus' }, fieldConfig: { defaults: { color: { mode: 'palette-classic' }, custom: { axisBorderShow: false, axisCenteredZero: false, axisColorMode: 'text', axisLabel: '', axisPlacement: 'auto', barAlignment: 0, drawStyle: 'line', fillOpacity: 0, gradientMode: 'none', hideFrom: { legend: false, tooltip: false, viz: false }, insertNulls: false, lineInterpolation: 'linear', lineWidth: 1, pointSize: 5, scaleDistribution: { type: 'linear' }, showPoints: 'auto', spanNulls: false, stacking: { group: 'A', mode: 'none' }, thresholdsStyle: { mode: 'off' } }, mappings: [], thresholds: { mode: 'absolute', steps: [{ color: 'green' }, { color: 'red', value: 80 }] } }, overrides: [] }, options: { legend: { calcs: ['sum'], displayMode: 'table', placement: 'right', showLegend: true, sortBy: 'Total', sortDesc: true }, tooltip: { mode: 'single', sort: 'none' } } },
  ),
], setPanelIDs=false)
