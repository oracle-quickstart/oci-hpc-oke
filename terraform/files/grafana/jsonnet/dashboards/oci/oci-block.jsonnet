local g = import '../../lib/g.libsonnet';
local variables = import '../../lib/oci-block-variables.libsonnet';
local timeseriesPanel = import '../../lib/timeseries-panel.libsonnet';

g.dashboard.new('Block Volumes')
+ g.dashboard.withUid('oci-block')
+ g.dashboard.withDescription('Block Volumes\n')
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
    'Read Ops Top 10',
    'topk(10, oci_blockstore:volume_read_ops_count)',
    '{{display_name}}:{{hostname}}:{{size}}',
    'ops',
    { w: 12, h: 8, x: 0, y: 0 },
  ),
  timeseriesPanel(
    'Write Ops Top 10',
    'topk(10, oci_blockstore:volume_write_ops_count)',
    '{{display_name}}:{{hostname}}:{{size}}',
    'ops',
    { w: 12, h: 8, x: 12, y: 0 },
  ),
  timeseriesPanel(
    'Read Throughput Top 10',
    'topk(10, oci_blockstore:volume_read_throughput_count)',
    '{{display_name}}:{{hostname}}:{{size}}',
    'Bps',
    { w: 12, h: 8, x: 0, y: 8 },
  ),
  timeseriesPanel(
    'Write Throughput Top 10',
    'topk(10, oci_blockstore:volume_write_throughput_count)',
    '{{display_name}}:{{hostname}}:{{size}}',
    'Bps',
    { w: 12, h: 8, x: 12, y: 8 },
  ),
  timeseriesPanel(
    'Throttled I/Os Top 10',
    'topk(10, oci_blockstore:volume_throttled_ios_count)',
    '{{display_name}}:{{hostname}}:{{size}}',
    'iops',
    { w: 12, h: 8, x: 0, y: 16 },
  ),
])
