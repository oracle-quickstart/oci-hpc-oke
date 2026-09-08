local variables = import '../../lib/cluster-level-metrics-variables.libsonnet';
local g = import '../../lib/g.libsonnet';
local gaugePanel = import '../../lib/gauge-panel.libsonnet';
local timeseriesPanel = import '../../lib/timeseries-panel.libsonnet';

g.dashboard.new('Cluster Level Metrics')
+ g.dashboard.withUid('cluster-level-metrics')
+ g.dashboard.withDescription('Cluster Level Aggregated Metrics Dashboard\n')
+ g.dashboard.withTimezone('browser')
+ g.dashboard.time.withFrom('now-5m')
+ g.dashboard.graphTooltip.withSharedCrosshair()
+ g.dashboard.withLinks([])
+ g.dashboard.withVariables([
  variables.prometheus,
  variables.instance_shape,
])
+ g.dashboard.withPanels([
  gaugePanel(
    'Avg CPU Util %',
    '100 * (1 - avg(irate(node_cpu_seconds_total{mode="idle"}[5m])))',
    { w: 4, h: 4, x: 0, y: 0 },
    id=1,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'yellow', value: 70 }, { color: 'orange', value: 85 }, { color: 'red', value: 95 }],
  ),
  gaugePanel(
    'Avg GPU Util %',
    'avg(amd_gpu_gfx_activity or DCGM_FI_DEV_GPU_UTIL)',
    { w: 4, h: 4, x: 4, y: 0 },
    id=2,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'yellow', value: 70 }, { color: 'orange', value: 85 }, { color: 'red', value: 95 }],
  ),
  gaugePanel(
    'Avg Memory Usage %',
    'avg((1 - (node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes)) * 100)',
    { w: 4, h: 4, x: 8, y: 0 },
    id=3,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'yellow', value: 70 }, { color: 'orange', value: 85 }, { color: 'red', value: 95 }],
  ),
  gaugePanel(
    'Avg CPU Pressure %',
    'avg(rate(node_pressure_cpu_waiting_seconds_total[5m]) * 100)',
    { w: 4, h: 4, x: 12, y: 0 },
    id=4,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'yellow', value: 70 }, { color: 'orange', value: 85 }, { color: 'red', value: 95 }],
  ),
  gaugePanel(
    'Avg Memory Pressure %',
    'avg(rate(node_pressure_memory_stalled_seconds_total[5m]) * 100)',
    { w: 4, h: 4, x: 16, y: 0 },
    id=5,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'yellow', value: 70 }, { color: 'orange', value: 85 }, { color: 'red', value: 95 }],
  ),
  gaugePanel(
    'Avg IO Pressure %',
    'avg(rate(node_pressure_io_stalled_seconds_total[5m]) * 100)',
    { w: 4, h: 4, x: 20, y: 0 },
    id=6,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'yellow', value: 70 }, { color: 'orange', value: 85 }, { color: 'red', value: 95 }],
  ),
  timeseriesPanel(
    'Cluster Memory Usage',
    'avg by (instance_shape) ((1 - (node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes)) * 100)',
    '{{ instance_shape }}',
    'percent',
    { w: 12, h: 8, x: 0, y: 4 },
    id=8,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'red', value: 80 }],
  ),
  timeseriesPanel(
    'Cluster GPU Utilization',
    'avg by (instance_shape) (amd_gpu_gfx_activity or DCGM_FI_DEV_GPU_UTIL)',
    '{{ instance_shape }}',
    'percent',
    { w: 12, h: 8, x: 12, y: 4 },
    id=9,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'red', value: 80 }],
  ),
  timeseriesPanel(
    'Cluster GPU Temperature',
    'max by (instance_shape) (amd_gpu_junction_temperature or DCGM_FI_DEV_GPU_TEMP)',
    '{{ instance_shape }}',
    'celsius',
    { w: 8, h: 8, x: 0, y: 12 },
    id=10,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'red', value: 80 }],
  ),
  timeseriesPanel(
    'Cluster GPU Power Usage',
    'sum by (instance_shape) (amd_gpu_package_power or DCGM_FI_DEV_POWER_USAGE)',
    '{{ instance_shape }}',
    'watts',
    { w: 8, h: 8, x: 8, y: 12 },
    id=11,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'red', value: 80 }],
  ),
  timeseriesPanel(
    'Network Traffic Total RX',
    'sum by (instance_shape) (rate(node_network_receive_bytes_total{device!~"lo|docker.*|rdma.*"}[5m]))',
    '{{ instance_shape }}',
    'Bps',
    { w: 8, h: 8, x: 16, y: 12 },
    id=12,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'red', value: 80 }],
  ),
  timeseriesPanel(
    'Network Traffic Total TX',
    'sum by (instance_shape) (rate(node_network_transmit_bytes_total{device!~"lo|docker.*|rdma.*"}[5m]))',
    '{{ instance_shape }}',
    'Bps',
    { w: 8, h: 8, x: 0, y: 20 },
    id=13,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'red', value: 80 }],
  ),
  timeseriesPanel(
    'Disk Read Total',
    'sum by (instance_shape) (irate(node_disk_read_bytes_total[5m]))',
    '{{ instance_shape }}',
    'Bps',
    { w: 8, h: 8, x: 8, y: 20 },
    id=14,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'red', value: 80 }],
  ),
  timeseriesPanel(
    'Disk Write Total',
    'sum by (instance_shape) (irate(node_disk_written_bytes_total[5m]))',
    '{{ instance_shape }}',
    'Bps',
    { w: 8, h: 8, x: 16, y: 20 },
    id=15,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'red', value: 80 }],
  ),
], setPanelIDs=false)
