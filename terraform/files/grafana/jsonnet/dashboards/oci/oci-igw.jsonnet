local g = import '../../lib/g.libsonnet';
local variables = import '../../lib/oci-igw-variables.libsonnet';
local timeseriesPanel = import '../../lib/timeseries-panel.libsonnet';

g.dashboard.new('Internet Gateway')
+ g.dashboard.withUid('oci-igw')
+ g.dashboard.withDescription('Internet Gateway\n')
+ g.dashboard.withTimezone('browser')
+ g.dashboard.withRefresh('30s')
+ g.dashboard.time.withFrom('now-5m')
+ g.dashboard.graphTooltip.withSharedCrosshair()
+ g.dashboard.withVariables([
  variables.prometheus,
])
+ g.dashboard.withPanels([
  timeseriesPanel(
    'Bytes From Internet Gateway',
    'oci_internet_gateway:bytes_from_igw_count',
    '{{display_name}}',
    'Bps',
    { w: 12, h: 8, x: 0, y: 0 },
  ),
  timeseriesPanel(
    'Bytes To Internet Gateway',
    'oci_internet_gateway:bytes_to_igw_count',
    '{{display_name}}',
    'Bps',
    { w: 12, h: 8, x: 12, y: 0 },
  ),
  timeseriesPanel(
    'Packets From Internet Gateway',
    'oci_internet_gateway:packets_from_igw_count',
    '{{display_name}}',
    'pps',
    { w: 12, h: 8, x: 0, y: 8 },
  ),
  timeseriesPanel(
    'Packets To Internet Gateway',
    'oci_internet_gateway:packets_to_igw_count',
    '{{display_name}}',
    'pps',
    { w: 12, h: 8, x: 12, y: 8 },
  ),
  timeseriesPanel(
    'Packet Drops From Internet Gateway',
    'oci_internet_gateway:packet_drops_from_igw_count',
    '{{display_name}}',
    'pps',
    { w: 12, h: 8, x: 0, y: 16 },
  ),
  timeseriesPanel(
    'Packet Drops To Internet Gateway',
    'oci_internet_gateway:packet_drops_to_igw_count',
    '{{display_name}}',
    'pps',
    { w: 12, h: 8, x: 12, y: 16 },
  ),
])
