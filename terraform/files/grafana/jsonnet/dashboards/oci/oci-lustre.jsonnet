local g = import '../../lib/g.libsonnet';
local variables = import '../../lib/oci-lustre-variables.libsonnet';
local timeseriesPanel = import '../../lib/timeseries-panel.libsonnet';

g.dashboard.new('Lustre File System')
+ g.dashboard.withUid('oci-lustre')
+ g.dashboard.withDescription('Lustre File System\n')
+ g.dashboard.withTimezone('browser')
+ g.dashboard.withRefresh('30s')
+ g.dashboard.time.withFrom('now-5m')
+ g.dashboard.graphTooltip.withSharedCrosshair()
+ g.dashboard.withVariables([
  variables.prometheus,
  variables.hostname,
  variables.oci_name,
])
+ g.dashboard.withPanels([
  timeseriesPanel(
    'Read Throughput',
    'avg(oci_lustrefilesystem:read_throughput_count)',
    '{{display_name}}:{{performance_tier}}',
    'Bps',
    { w: 12, h: 8, x: 0, y: 0 },
  ),
  timeseriesPanel(
    'Write Throughput',
    'avg(oci_lustrefilesystem:write_throughput_count)',
    '{{display_name}}:{{performance_tier}}',
    'Bps',
    { w: 12, h: 8, x: 12, y: 0 },
  ),
  timeseriesPanel(
    'Data Read Operations',
    'oci_lustrefilesystem:data_read_operations_count',
    '{{display_name}}:{{performance_tier}}',
    'ops',
    { w: 12, h: 8, x: 0, y: 8 },
  ),
  timeseriesPanel(
    'Data Write Operations',
    'oci_lustrefilesystem:data_write_operations_count',
    '{{display_name}}:{{performance_tier}}',
    'ops',
    { w: 12, h: 8, x: 12, y: 8 },
  ),
  timeseriesPanel(
    'Capacity Util - Space',
    'avg(oci_lustrefilesystem:file_system_capacity_count)',
    '{{display_name}}:{{ad}}',
    'percent',
    { w: 12, h: 8, x: 0, y: 16 },
  ),
  timeseriesPanel(
    'Capacity Util - Inode',
    'avg(oci_lustrefilesystem:file_system_inode_capacity_count)',
    '{{display_name}}:{{ad}}',
    'percent',
    { w: 12, h: 8, x: 12, y: 16 },
  ),
])
