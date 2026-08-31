local g = import '../../lib/g.libsonnet';
local variables = import '../../lib/oci-fastconnect-variables.libsonnet';
local timeseriesPanel = import '../../lib/timeseries-panel.libsonnet';

g.dashboard.new('Fast Connect')
+ g.dashboard.withUid('oci-fastconnet')
+ g.dashboard.withDescription('Fast Connect\n')
+ g.dashboard.withTimezone('browser')
+ g.dashboard.withRefresh('30s')
+ g.dashboard.time.withFrom('now-5m')
+ g.dashboard.graphTooltip.withSharedCrosshair()
+ g.dashboard.withVariables([
  variables.prometheus,
])
+ g.dashboard.withPanels([
  timeseriesPanel(
    'Bits Received',
    'oci_fastconnect:bits_received_count',
    '{{display_name}}',
    'Bps',
    { w: 12, h: 8, x: 0, y: 0 },
  ),
  timeseriesPanel(
    'Bits Sent',
    'oci_fastconnect:bits_sent_count',
    '{{display_name}}',
    'Bps',
    { w: 12, h: 8, x: 12, y: 0 },
  ),
  timeseriesPanel(
    'Packets Received',
    'oci_fastconnect:packets_received_count',
    '{{display_name}}',
    'pps',
    { w: 12, h: 8, x: 0, y: 8 },
  ),
  timeseriesPanel(
    'Packets Sent',
    'oci_fastconnect:packets_sent_count',
    '{{display_name}}',
    'pps',
    { w: 12, h: 8, x: 12, y: 8 },
  ),
  timeseriesPanel(
    'Packets Discarded',
    'oci_fastconnect:packets_discarded_count',
    '{{display_name}}',
    'none',
    { w: 12, h: 8, x: 0, y: 16 },
  ),
  timeseriesPanel(
    'Packets Error',
    'oci_fastconnect:packets_error_count',
    '{{display_name}}',
    'none',
    { w: 12, h: 8, x: 12, y: 16 },
  ),
  timeseriesPanel(
    'Connection State',
    'avg(oci_fastconnect:connection_state_count)',
    '{{display_name}}',
    'none',
    { w: 12, h: 8, x: 12, y: 24 },
  ),
])
