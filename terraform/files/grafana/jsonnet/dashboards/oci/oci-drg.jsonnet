local g = import '../../lib/g.libsonnet';
local variables = import '../../lib/oci-drg-variables.libsonnet';
local timeseriesPanel = import '../../lib/timeseries-panel.libsonnet';

g.dashboard.new('Dynamic Routing Gateway')
+ g.dashboard.withUid('oci-drg')
+ g.dashboard.withDescription('Dynamic Routing Gateway\n')
+ g.dashboard.withTimezone('browser')
+ g.dashboard.withRefresh('30s')
+ g.dashboard.time.withFrom('now-5m')
+ g.dashboard.graphTooltip.withSharedCrosshair()
+ g.dashboard.withVariables([
  variables.prometheus,
])
+ g.dashboard.withPanels([
  timeseriesPanel(
    'Bytes From DRG Atchmnt',
    'oci_dynamic_routing_gateway:bytes_from_drg_attachment_count',
    '{{display_name}}',
    'Bps',
    { w: 12, h: 8, x: 0, y: 0 },
  ),
  timeseriesPanel(
    'Bytes To DRG Atchmnt',
    'oci_dynamic_routing_gateway:bytes_to_drg_attachment_count',
    '{{display_name}}',
    'Bps',
    { w: 12, h: 8, x: 12, y: 0 },
  ),
  timeseriesPanel(
    'Packets From DRG Atchmnt',
    'oci_dynamic_routing_gateway:packets_from_drg_attachment_count',
    '{{display_name}}',
    'pps',
    { w: 12, h: 8, x: 0, y: 8 },
  ),
  timeseriesPanel(
    'Packets To DRG Atchmnt',
    'oci_dynamic_routing_gateway:packets_to_drg_attachment_count',
    '{{display_name}}',
    'pps',
    { w: 12, h: 8, x: 12, y: 8 },
  ),
  timeseriesPanel(
    'Pkt Drops From DRG Atchmnt',
    'oci_dynamic_routing_gateway:packet_drops_from_drg_attachment_count',
    '{{display_name}}',
    'none',
    { w: 12, h: 8, x: 0, y: 16 },
  ),
  timeseriesPanel(
    'Pkt Drops To DRG Atchmnt',
    'oci_dynamic_routing_gateway:packet_drops_to_drg_attachment_count',
    '{{drop_type}}',
    'none',
    { w: 12, h: 8, x: 12, y: 16 },
  ),
])
