local g = import '../../lib/g.libsonnet';
local variables = import '../../lib/oci-vcn-variables.libsonnet';
local timeseriesPanel = import '../../lib/timeseries-panel.libsonnet';

g.dashboard.new('Virtual Cloud Network')
+ g.dashboard.withUid('oci-vcn')
+ g.dashboard.withDescription('Virtual Cloud Network\n')
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
    'VNIC Ingress Bytes Top 10',
    'topk(10, oci_vcn:vnic_from_network_bytes_count)',
    '{{display_name}}:{{hostname}}',
    'Bps',
    { w: 12, h: 8, x: 0, y: 0 },
  ),
  timeseriesPanel(
    'VNIC Egress Bytes Top 10',
    'topk(10, oci_vcn:vnic_to_network_bytes_count)',
    '{{display_name}}:{{hostname}}',
    'Bps',
    { w: 12, h: 8, x: 12, y: 0 },
  ),
  timeseriesPanel(
    'VNIC Ingress Drops',
    'topk(10, oci_vcn:vnic_ingress_drops_throttle_count)',
    '{{display_name}}:{{hostname}}',
    'pps',
    { w: 12, h: 8, x: 0, y: 8 },
  ),
  timeseriesPanel(
    'VNIC Egress Drops',
    'topk(10, oci_vcn:vnic_egress_drops_throttle_count)',
    '{{display_name}}:{{hostname}}',
    'pps',
    { w: 12, h: 8, x: 12, y: 8 },
  ),
  timeseriesPanel(
    'VNIC ConnTrack Util',
    'topk(10, oci_vcn:vnic_conntrack_util_percent_count)',
    '{{display_name}}:{{hostname}}',
    'percent',
    { w: 12, h: 8, x: 0, y: 16 },
  ),
  timeseriesPanel(
    'VNIC ConnTrack Is Full',
    'topk(10, oci_vcn:vnic_conntrack_is_full_count)',
    '{{display_name}}:{{hostname}}',
    'none',
    { w: 12, h: 8, x: 12, y: 16 },
  ),
  timeseriesPanel(
    'VNIC To Network Packets',
    'topk(10, oci_vcn:vnic_to_network_packet_count)',
    '{{display_name}}:{{hostname}}',
    'percent',
    { w: 12, h: 8, x: 0, y: 24 },
  ),
  timeseriesPanel(
    'VNIC From Network Packets',
    'topk(10, oci_vcn:vnic_from_network_packet_count)',
    '{{display_name}}:{{hostname}}',
    'none',
    { w: 12, h: 8, x: 12, y: 24 },
  ),
  timeseriesPanel(
    'Smart NIC Buffer Drops From Host',
    'topk(10, oci_vcn:smart_nic_buffer_drops_from_host_count)',
    '{{display_name}}:{{hostname}}',
    'percent',
    { w: 12, h: 8, x: 0, y: 32 },
  ),
  timeseriesPanel(
    'Smart NIC Buffer Drops To Host',
    'topk(10, oci_vcn:smart_nic_buffer_drops_to_host_count)',
    '{{display_name}}:{{hostname}}',
    'none',
    { w: 12, h: 8, x: 12, y: 32 },
  ),
])
