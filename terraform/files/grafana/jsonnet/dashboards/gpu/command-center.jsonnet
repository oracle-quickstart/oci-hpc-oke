local variables = import '../../lib/cluster-level-metrics-variables.libsonnet';
local g = import '../../lib/g.libsonnet';
local statPanel = import '../../lib/stat-panel-single.libsonnet';
local stateTimelinePanel = import '../../lib/state-timeline-panel.libsonnet';
local statusStatPanel = import '../../lib/status-stat-panel.libsonnet';

g.dashboard.new('Command Center')
+ g.dashboard.withUid('command-center')
+ g.dashboard.withDescription('Command Center\n')
+ g.dashboard.withTimezone('browser')
+ g.dashboard.time.withFrom('now-5m')
+ g.dashboard.graphTooltip.withSharedCrosshair()
+ g.dashboard.withLinks([])
+ g.dashboard.withVariables([
  variables.prometheus,
  variables.instance_shape,
])
+ g.dashboard.withPanels([
  statPanel(
    'Total Nodes',
    'count(count by(node) (kube_node_info))',
    { w: 8, h: 4, x: 0, y: 0 },
    id=1,
  ),
  statPanel(
    'CPU Nodes',
    'count(count by(node) (kube_node_info))\n-\ncount(count by(node) (kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu"} > 0))',
    { w: 8, h: 4, x: 8, y: 0 },
    id=2,
  ),
  statPanel(
    'GPU Nodes',
    'count(count by(node) (kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu"} > 0))',
    { w: 8, h: 4, x: 16, y: 0 },
    id=3,
  ),
  statPanel(
    'Healthy GPU Nodes',
    'count(\n  node_health_status == 1\n  and on(hostname)\n  label_replace(\n    max by(node) (\n      kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu"} > 0\n    ),\n    "hostname", "$1", "node", "(.*)"\n  )\n)\nor vector(0)',
    { w: 8, h: 4, x: 0, y: 4 },
    id=4,
  ),
  statPanel(
    'Total GPUs',
    'sum(kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu"})',
    { w: 8, h: 4, x: 8, y: 4 },
    id=5,
  ),
  statPanel(
    'Healthy GPUs',
    'sum(\n  label_replace(\n    kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu"},\n    "hostname", "$1", "node", "(.*)"\n  )\n  * on(hostname) group_left()\n  (node_health_status == 1)\n)\nor vector(0)',
    { w: 8, h: 4, x: 16, y: 4 },
    id=6,
  ),
  statusStatPanel(
    'Compute Node Health',
    'node_health_status\nand on(hostname)\nlabel_replace(\n  max by(node) (\n    kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu"} > 0\n  ),\n  "hostname", "$1", "node", "(.*)"\n)',
    '{{ hostname }}',
    { w: 24, h: 5, x: 0, y: 8 },
    [{ targetBlank: true, title: 'Cluster Metrics', url: '/d/cluster-level-metrics/cluster-level-metrics' }, { targetBlank: true, title: 'Multi Node Metrics', url: '/d/multi-node-metrics/multi-node-metrics?var-hostname=$__all' }],
    [{ targetBlank: true, title: 'Host Metrics', url: '/d/host-metrics-single/host-metrics?var-hostname=${__field.labels.hostname}' }, { targetBlank: true, title: 'GPU Metrics', url: '/d/gpu-metrics-single/gpu-metrics?var-hostname=${__field.labels.hostname}' }, { targetBlank: true, title: 'GPU Health', url: '/d/gpu-health/gpu-health-status?var-hostname=${__field.labels.hostname}' }],
    id=7,
    valueMap={ '0': { color: 'red', text: 'Failed' }, '1': { color: 'green', text: 'Healthy' }, '2': { color: 'yellow', text: 'Unknown' } },
  ),
  stateTimelinePanel(
    'Historical Cluster Node Health',
    'node_health_status\nand on(hostname)\nlabel_replace(\n  max by(node) (\n    kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu"} > 0\n  ),\n  "hostname", "$1", "node", "(.*)"\n)',
    '{{hostname}}',
    { w: 24, h: 10, x: 0, y: 13 },
    id=8,
    perPage=20,
    valueMap={ '0': { color: 'red', text: 'Failed' }, '1': { color: 'green', text: 'Healthy' }, '2': { color: 'yellow', text: 'Unknown' } },
  ),
  g.panel.alertList.new('Cluster Alerts')
  + g.panel.alertList.gridPos.withW(24)
  + g.panel.alertList.gridPos.withH(5)
  + g.panel.alertList.gridPos.withX(0)
  + g.panel.alertList.gridPos.withY(23)
  + { id: 9 },
  stateTimelinePanel(
    'Historical Cluster Node Issues',
    '0 * label_replace(\n  max by(node, condition) (\n    kube_node_status_condition{condition=~"CpuProfile|DcgmiHealth|GpuBadPages|GpuBus|GpuCount|GpuEcc|GpuFabricMgr|GpuImex|GpuPcie|GpuRowRemap|GpuXid|IpAddress|NodeHasPcieErrors|NvlinkSpeed|OcaVersion|RdmaLink|RdmaLinkFlapping|RdmaRttcc|RdmaVfCounters|RdmaVfRoutes|RdmaWpaAuth|Rocminfo", status="true"} == 1\n  ),\n  "hostname", "$1", "node", "(.*)"\n)\nor\n2 * label_replace(\n  max by(node, condition) (\n    kube_node_status_condition{condition=~"CpuProfile|DcgmiHealth|GpuBadPages|GpuBus|GpuCount|GpuEcc|GpuFabricMgr|GpuImex|GpuPcie|GpuRowRemap|GpuXid|IpAddress|NodeHasPcieErrors|NvlinkSpeed|OcaVersion|RdmaLink|RdmaLinkFlapping|RdmaRttcc|RdmaVfCounters|RdmaVfRoutes|RdmaWpaAuth|Rocminfo", status="unknown"} == 1\n  ),\n  "hostname", "$1", "node", "(.*)"\n)',
    '{{hostname}} / {{condition}}',
    { w: 24, h: 10, x: 0, y: 28 },
    id=10,
    perPage=20,
    valueMap={ '0': { color: 'red', text: 'Failed' }, '2': { color: 'yellow', text: 'Unknown' } },
  ),
], setPanelIDs=false)
