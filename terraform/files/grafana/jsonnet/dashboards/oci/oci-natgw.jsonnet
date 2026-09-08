local g = import '../../lib/g.libsonnet';
local variables = import '../../lib/oci-natgw-variables.libsonnet';
local timeseriesPanel = import '../../lib/timeseries-panel.libsonnet';

g.dashboard.new('NAT Gateway')
+ g.dashboard.withUid('oci-natgw')
+ g.dashboard.withDescription('NAT Gateway\n')
+ g.dashboard.withTimezone('browser')
+ g.dashboard.withRefresh('30s')
+ g.dashboard.time.withFrom('now-5m')
+ g.dashboard.graphTooltip.withSharedCrosshair()
+ g.dashboard.withVariables([
  variables.prometheus,
])
+ g.dashboard.withPanels([
  timeseriesPanel(
    'Bytes From NAT Gateway',
    'oci_nat_gateway:bytes_from_natgw_count',
    '{{display_name}}',
    'Bps',
    { w: 12, h: 8, x: 0, y: 0 },
  ),
  timeseriesPanel(
    'Bytes To NAT Gateway',
    'oci_nat_gateway:bytes_to_natgw_count',
    '{{display_name}}',
    'Bps',
    { w: 12, h: 8, x: 12, y: 0 },
  ),
  timeseriesPanel(
    'Packets From NAT Gateway',
    'oci_nat_gateway:packets_from_natgw_count',
    '{{display_name}}',
    'pps',
    { w: 12, h: 8, x: 0, y: 8 },
  ),
  timeseriesPanel(
    'Packets To NAT Gateway',
    'oci_nat_gateway:packets_to_natgw_count',
    '{{display_name}}',
    'pps',
    { w: 12, h: 8, x: 12, y: 8 },
  ),
  timeseriesPanel(
    'Drops To NAT Gateway',
    'oci_nat_gateway:drops_to_natgw_count',
    '{{drop_type}}',
    'none',
    { w: 12, h: 8, x: 12, y: 16 },
  ),
])
