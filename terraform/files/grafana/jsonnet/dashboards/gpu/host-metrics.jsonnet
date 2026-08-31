local g = import '../../lib/g.libsonnet';
local gaugePanel = import '../../lib/gauge-panel.libsonnet';
local variables = import '../../lib/host-metrics-variables.libsonnet';
local timeseriesPanel = import '../../lib/timeseries-panel.libsonnet';

g.dashboard.new('Host Metrics')
+ g.dashboard.withUid('host-metrics-single')
+ g.dashboard.withDescription('Host Metrics Dashboard for a single cluster node.\n')
+ g.dashboard.withTimezone('browser')
+ g.dashboard.time.withFrom('now-5m')
+ g.dashboard.graphTooltip.withSharedCrosshair()
+ g.dashboard.withLinks([])
+ g.dashboard.withVariables([
  variables.prometheus,
  variables.instance_shape,
  variables.hostname,
  variables.oci_name,
  variables.fstype,
  variables.interface,
  variables.device,
  variables.mountpoint,
])
+ g.dashboard.withPanels([
  gaugePanel(
    'CPU Avail',
    'ceil(100 * (avg by (hostname, oci_name) (irate(node_cpu_seconds_total{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape",mode="idle"}[5m]))))',
    { w: 4, h: 4, x: 0, y: 0 },
    id=1,
    legend='{{hostname}}',
    thresholdSteps=[{ color: 'red', value: 0 }, { color: 'yellow', value: 10 }, { color: 'green', value: 20 }],
  ),
  gaugePanel(
    'Memory Avail',
    'ceil((node_memory_MemAvailable_bytes{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape"}/node_memory_MemTotal_bytes{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape"})*100)',
    { w: 4, h: 4, x: 4, y: 0 },
    id=2,
    legend='{{hostname}}',
    thresholdSteps=[{ color: 'red', value: 0 }, { color: 'yellow', value: 10 }, { color: 'green', value: 20 }],
  ),
  gaugePanel(
    'Boot Vol Avail',
    'ceil((node_filesystem_avail_bytes{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape",mountpoint=~"/"} / node_filesystem_size_bytes{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape",mountpoint=~"/"})*100)',
    { w: 4, h: 4, x: 8, y: 0 },
    id=3,
    legend='{{hostname}}',
    thresholdSteps=[{ color: 'red', value: 0 }, { color: 'yellow', value: 10 }, { color: 'green', value: 20 }],
  ),
  gaugePanel(
    'CPU Pressure',
    'ceil(avg by (hostname, oci_name) (rate(node_pressure_cpu_waiting_seconds_total{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape"}[5m]) * 100))',
    { w: 4, h: 4, x: 12, y: 0 },
    id=4,
    legend='{{hostname}}',
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'yellow', value: 70 }, { color: 'orange', value: 85 }, { color: 'red', value: 95 }],
  ),
  gaugePanel(
    'Memory Stalled',
    'ceil(avg by (hostname, oci_name) (rate(node_pressure_memory_stalled_seconds_total{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape"}[5m]) * 100))',
    { w: 4, h: 4, x: 16, y: 0 },
    id=5,
    legend='{{hostname}}',
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'yellow', value: 70 }, { color: 'orange', value: 85 }, { color: 'red', value: 95 }],
  ),
  gaugePanel(
    'IO Stalled',
    'ceil(avg by (hostname, oci_name) (rate(node_pressure_io_stalled_seconds_total{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape"}[5m]) * 100))',
    { w: 4, h: 4, x: 20, y: 0 },
    id=6,
    legend='{{hostname}}',
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'yellow', value: 70 }, { color: 'orange', value: 85 }, { color: 'red', value: 95 }],
  ),
  timeseriesPanel(
    'Memory Utilization',
    'ceil((1 - (node_memory_MemAvailable_bytes{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape"}/node_memory_MemTotal_bytes{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape"}))*100)',
    '{{ hostname }}',
    'percent',
    { w: 24, h: 8, x: 0, y: 4 },
    id=8,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'red', value: 80 }],
  ),
  timeseriesPanel(
    'Disk reads',
    'irate(node_disk_read_bytes_total{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape"}[5m])',
    '{{ device }}',
    'Bps',
    { w: 12, h: 8, x: 0, y: 12 },
    id=9,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'red', value: 80 }],
  ),
  timeseriesPanel(
    'Disk writes',
    'irate(node_disk_written_bytes_total{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape"}[5m])',
    '{{ device }}',
    'Bps',
    { w: 12, h: 8, x: 12, y: 12 },
    id=10,
    thresholdSteps=[{ color: 'green', value: 0 }, { color: 'red', value: 80 }],
  ),
  timeseriesPanel(
    'Network Traffic Received',
    'rate(node_network_receive_bytes_total{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape",device=~"$device",device!~"lo|docker.*|rdma.*"}[5m])',
    '{{ device }}',
    'Bps',
    { w: 12, h: 8, x: 0, y: 20 },
    id=11,
    thresholdSteps=[{ color: 'green' }, { color: 'red', value: 80 }],
  ),
  timeseriesPanel(
    'Network Traffic Transmitted',
    'rate(node_network_transmit_bytes_total{hostname=~"$hostname",oci_name=~"$oci_name",instance_shape=~"$instance_shape",device=~"$device",device!~"lo|docker.*|rdma.*"}[5m])',
    '{{ device }}',
    'Bps',
    { w: 12, h: 8, x: 12, y: 20 },
    id=12,
    thresholdSteps=[{ color: 'green' }, { color: 'red', value: 80 }],
  ),
], setPanelIDs=false)
