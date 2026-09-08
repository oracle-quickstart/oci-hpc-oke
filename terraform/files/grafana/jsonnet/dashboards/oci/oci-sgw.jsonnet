local g = import '../../lib/g.libsonnet';
local variables = import '../../lib/oci-sgw-variables.libsonnet';
local timeseriesPanel = import '../../lib/timeseries-panel.libsonnet';

g.dashboard.new('Service Gateway')
+ g.dashboard.withUid('oci-sgw')
+ g.dashboard.withDescription('Service Gateway\n')
+ g.dashboard.withTimezone('browser')
+ g.dashboard.withRefresh('30s')
+ g.dashboard.time.withFrom('now-5m')
+ g.dashboard.graphTooltip.withSharedCrosshair()
+ g.dashboard.withVariables([
  variables.prometheus,
])
+ g.dashboard.withPanels([
  timeseriesPanel(
    'Bytes From Service',
    'oci_service_gateway:bytes_from_service_count',
    '{{display_name}}',
    'Bps',
    { w: 12, h: 8, x: 0, y: 0 },
  ),
  timeseriesPanel(
    'Bytes To Service',
    'oci_service_gateway:bytes_to_service_count',
    '{{display_name}}',
    'Bps',
    { w: 12, h: 8, x: 12, y: 0 },
  ),
  timeseriesPanel(
    'Packets From Service',
    'oci_service_gateway:packets_from_service_count',
    '{{display_name}}',
    'pps',
    { w: 12, h: 8, x: 0, y: 8 },
  ),
  timeseriesPanel(
    'Packets To Service',
    'oci_service_gateway:packets_to_service_count',
    '{{display_name}}',
    'pps',
    { w: 12, h: 8, x: 12, y: 8 },
  ),
  timeseriesPanel(
    'Drops From Service',
    'oci_service_gateway:sgw_drops_from_service_count',
    '{{display_name}}',
    'none',
    { w: 12, h: 8, x: 0, y: 16 },
  ),
  timeseriesPanel(
    'Drops To Service',
    'oci_service_gateway:sgw_drops_to_service_count',
    '{{drop_type}}',
    'none',
    { w: 12, h: 8, x: 12, y: 16 },
  ),
])
