local g = import '../../lib/g.libsonnet';
local utilGaugePanel = import '../../lib/gauge-panel-util.libsonnet';
local gpuHealthPanel = import '../../lib/gpu-health-stat-panel.libsonnet';
local variables = import '../../lib/gpu-metrics-variables.libsonnet';
local statPanel = import '../../lib/stat-panel-single.libsonnet';
local tempGaugePanel = import '../../lib/temperature-gauge-panel.libsonnet';
local timeseriesPanel = import '../../lib/timeseries-panel.libsonnet';
local roce = import './roce-queries.libsonnet';

g.dashboard.new('GPU Metrics')
+ g.dashboard.withUid('gpu-metrics-single')
+ g.dashboard.withDescription(|||
  GPU Metrics Dashboard for a single cluster node.
|||)
+ g.dashboard.withTimezone('browser')
+ g.dashboard.time.withFrom('now-5m')
+ g.dashboard.graphTooltip.withSharedCrosshair()
+ g.dashboard.withLinks([])
+ g.dashboard.withVariables([
  variables.prometheus,
  variables.instance_shape,
  variables.hostname,
  variables.oci_name,
])
+ g.dashboard.withPanels([
  statPanel(
    'Avail GPU',
    'count by (hostname) (sum by (hostname, gpu_id) (amd_gpu_health == 1)) or label_replace(count by (Hostname) (sum by (Hostname, gpu) (DCGM_EXP_GPU_HEALTH_STATUS == 0)), "hostname", "$1", "Hostname", "(.*)")',
    { w: 4, h: 4, x: 0, y: 0 },
    id=1,
    instant=false,
    legend='__auto',
  ),
  tempGaugePanel(
    'Max GPU Temperature',
    'ceil(max by (hostname) (amd_gpu_junction_temperature{hostname=~"$hostname", instance_shape=~"$instance_shape"})) or label_replace(ceil(max by (Hostname) (DCGM_FI_DEV_GPU_TEMP{Hostname=~"$hostname", oci_name=~"$oci_name", instance_shape=~"$instance_shape"})), "hostname", "$1", "Hostname", "(.*)")',
    { w: 4, h: 4, x: 4, y: 0 },
    id=2,
    legend='__auto',
  ),
  tempGaugePanel(
    'Max Memory Temperature',
    'ceil(max by (hostname) (amd_gpu_memory_temperature{hostname=~"$hostname", instance_shape=~"$instance_shape"})) or label_replace(ceil(max by (Hostname) (DCGM_FI_DEV_MEMORY_TEMP{Hostname=~"$hostname", oci_name=~"$oci_name", instance_shape=~"$instance_shape"})), "hostname", "$1", "Hostname", "(.*)")',
    { w: 4, h: 4, x: 8, y: 0 },
    id=3,
    legend='__auto',
  ),
  utilGaugePanel(
    'Avg GPU Util by Node',
    'avg by (hostname) (amd_gpu_gfx_activity{hostname=~"$hostname", instance_shape=~"$instance_shape"}) or label_replace(avg by (Hostname) (DCGM_FI_DEV_GPU_UTIL{Hostname=~"$hostname", oci_name=~"$oci_name", instance_shape=~"$instance_shape"}), "hostname", "$1", "Hostname", "(.*)")',
    { w: 4, h: 4, x: 12, y: 0 },
    id=4,
    legend='__auto',
  ),
  gpuHealthPanel(
    'GPU Health',
    'amd_gpu_health{hostname=~"$hostname", instance_shape=~"$instance_shape"} or label_replace(label_replace(DCGM_EXP_GPU_HEALTH_STATUS{Hostname=~"$hostname", oci_name=~"$oci_name", instance_shape=~"$instance_shape"} == bool 0, "hostname", "$1", "Hostname", "(.*)"), "gpu_id", "$1", "gpu", "(.*)")',
    { w: 8, h: 4, x: 16, y: 0 },
    id=5,
  ),
  timeseriesPanel(
    'GPU Temperature',
    'amd_gpu_junction_temperature{hostname=~"$hostname", instance_shape=~"$instance_shape"} or label_replace(label_replace(DCGM_FI_DEV_GPU_TEMP{Hostname=~"$hostname", oci_name=~"$oci_name", instance_shape=~"$instance_shape"}, "hostname", "$1", "Hostname", "(.*)"), "gpu_id", "$1", "gpu", "(.*)")',
    '{{ gpu_id }}',
    'celsius',
    { w: 8, h: 8, x: 0, y: 4 },
    id=6,
  ),
  timeseriesPanel(
    'GPU Powerdraw',
    'amd_gpu_package_power{hostname=~"$hostname", instance_shape=~"$instance_shape"} or label_replace(label_replace(DCGM_FI_DEV_POWER_USAGE{Hostname=~"$hostname", oci_name=~"$oci_name", instance_shape=~"$instance_shape"}, "hostname", "$1", "Hostname", "(.*)"), "gpu_id", "$1", "gpu", "(.*)")',
    '{{ gpu_id }}',
    'watts',
    { w: 8, h: 8, x: 8, y: 4 },
    id=7,
  ),
  timeseriesPanel(
    'GPU Utilization',
    'amd_gpu_gfx_activity{hostname=~"$hostname", instance_shape=~"$instance_shape"} or label_replace(label_replace(DCGM_FI_DEV_GPU_UTIL{Hostname=~"$hostname", oci_name=~"$oci_name", instance_shape=~"$instance_shape"}, "hostname", "$1", "Hostname", "(.*)"), "gpu_id", "$1", "gpu", "(.*)")',
    '{{ gpu_id }}',
    'percent',
    { w: 8, h: 8, x: 16, y: 4 },
    id=8,
  ),
  timeseriesPanel(
    'GPU Memory Temperature',
    'amd_gpu_memory_temperature{hostname=~"$hostname", instance_shape=~"$instance_shape"} or label_replace(label_replace(DCGM_FI_DEV_MEMORY_TEMP{Hostname=~"$hostname", oci_name=~"$oci_name", instance_shape=~"$instance_shape"}, "hostname", "$1", "Hostname", "(.*)"), "gpu_id", "$1", "gpu", "(.*)")',
    '{{ gpu_id }}',
    'celsius',
    { w: 8, h: 8, x: 0, y: 12 },
    id=9,
  ),
  timeseriesPanel(
    'GPU Clock (System)',
    'max by (hostname, gpu_id) (amd_gpu_clock{clock_type="system", hostname=~"$hostname", instance_shape=~"$instance_shape"}) or label_replace(label_replace(DCGM_FI_DEV_SM_CLOCK{Hostname=~"$hostname", oci_name=~"$oci_name", instance_shape=~"$instance_shape"}, "hostname", "$1", "Hostname", "(.*)"), "gpu_id", "$1", "gpu", "(.*)")',
    '{{ gpu_id }}',
    'MHz',
    { w: 8, h: 8, x: 8, y: 12 },
    id=10,
  ),
  timeseriesPanel(
    'GPU Memory Controller Activity (UMC)',
    'amd_gpu_umc_activity{hostname=~"$hostname", instance_shape=~"$instance_shape"} or label_replace(label_replace(DCGM_FI_DEV_MEM_COPY_UTIL{Hostname=~"$hostname", oci_name=~"$oci_name", instance_shape=~"$instance_shape"}, "hostname", "$1", "Hostname", "(.*)"), "gpu_id", "$1", "gpu", "(.*)")',
    '{{ gpu_id }}',
    'percent',
    { w: 8, h: 8, x: 16, y: 12 },
    id=11,
  ),
  timeseriesPanel(
    'GPU Fabric Rx + Tx Combined B/W',
    'sum by (hostname, gpu_id) ((rate(amd_gpu_xgmi_link_rx{hostname=~"$hostname", instance_shape=~"$instance_shape"}[5m]) + rate(amd_gpu_xgmi_link_tx{hostname=~"$hostname", instance_shape=~"$instance_shape"}[5m])) * 1024) or label_replace(sum by (hostname, gpu) (rate(DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL{hostname=~"$hostname", oci_name=~"$oci_name", instance_shape=~"$instance_shape"}[5m])) * 1024, "gpu_id", "$1", "gpu", "(.*)")',
    '{{ gpu_id }}',
    'Bps',
    { w: 24, h: 8, x: 0, y: 20 },
    id=12,
  ),
  timeseriesPanel(
    'ROCEv2 Rx + Tx Combined B/W',
    roce.combined,
    '{{ device }}',
    'Bps',
    { w: 8, h: 10, x: 0, y: 28 },
    { calcs: ['delta'], displayMode: 'table', placement: 'right' },
    id=15,
  ),
  timeseriesPanel(
    'ROCEv2 Tx B/W',
    roce.transmit,
    '{{ device }}',
    'Bps',
    { w: 8, h: 10, x: 8, y: 28 },
    { calcs: ['delta'], displayMode: 'table', placement: 'right' },
    id=16,
  ),
  timeseriesPanel(
    'ROCEv2 Rx B/W',
    roce.receive,
    '{{ device }}',
    'Bps',
    { w: 8, h: 10, x: 16, y: 28 },
    { calcs: ['delta'], displayMode: 'table', placement: 'right' },
    id=17,
  ),
], setPanelIDs=false)
