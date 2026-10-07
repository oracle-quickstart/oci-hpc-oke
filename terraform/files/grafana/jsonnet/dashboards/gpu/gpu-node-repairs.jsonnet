// OKE GPU Health Monitoring add-on: NodeHealthReport faults and repairs, exported by kube-state-metrics.
local variables = import '../../lib/cluster-level-metrics-variables.libsonnet';
local panel = import '../../lib/dashboard-panel.libsonnet';
local target = import '../../lib/dashboard-target.libsonnet';
local g = import '../../lib/g.libsonnet';
local statPanel = import '../../lib/stat-panel-single.libsonnet';
local stateTimelinePanel = import '../../lib/state-timeline-panel.libsonnet';

// Scrape and kube-state-metrics labels that are not useful in the tables.
local hiddenColumns = {
  Time: true,
  __name__: true,
  container: true,
  customresource_group: true,
  customresource_kind: true,
  customresource_version: true,
  endpoint: true,
  instance: true,
  job: true,
  namespace: true,
  pod: true,
  service: true,
};

local tableConfig(renames, timeColumns, sortColumn=null) = {
  fieldConfig: {
    defaults: {
      custom: { align: 'auto', cellOptions: { type: 'auto' }, inspect: false },
      // Some signals have no fault code (user-initiated repair) or no action (hpcFault). Show "none" in those cells.
      mappings: [
        { type: 'special', options: { match: 'null+nan', result: { text: 'none', index: 0 } } },
        { type: 'special', options: { match: 'empty', result: { text: 'none', index: 1 } } },
      ],
    },
    overrides: [
      { matcher: { id: 'byName', options: name }, properties: [{ id: 'unit', value: 'dateTimeAsIso' }] }
      for name in timeColumns
    ],
  },
  options: { cellHeight: 'sm', showHeader: true, sortBy: [{ displayName: if sortColumn != null then sortColumn else timeColumns[0], desc: true }] },
  transformations: [
    { id: 'merge', options: {} },
    { id: 'organize', options: { excludeByName: hiddenColumns, renameByName: renames } },
  ],
};

local instantTable(expr, refId) = target.prometheus('$PROMETHEUS_DS', expr, { format: 'table', instant: true, refId: refId });

g.dashboard.new('GPU Node Repairs')
+ g.dashboard.withUid('gpu-node-repairs')
+ g.dashboard.withDescription('Faults and repairs reported by the OKE GPU Health Monitoring add-on (NodeHealthReport).\n')
+ g.dashboard.withTimezone('browser')
+ g.dashboard.time.withFrom('now-24h')
+ g.dashboard.graphTooltip.withSharedCrosshair()
+ g.dashboard.withLinks([])
+ g.dashboard.withVariables([
  variables.prometheus,
])
+ g.dashboard.withPanels([
  statPanel(
    'Nodes in Repair',
    'count(oke_node_health_report_repair_info{phase!="", terminal_state=""}) or vector(0)',
    { w: 4, h: 4, x: 0, y: 0 },
    id=1,
  ),
  statPanel(
    'Nodes with Faults (last 15m)',
    'count(count by(node) (time() - oke_node_health_report_signal_last_observed_timestamp_seconds < 900)) or vector(0)',
    { w: 4, h: 4, x: 4, y: 0 },
    id=2,
  ),
  statPanel(
    'Repairs Completed (time range)',
    'count(\n  (oke_node_health_report_last_repair_completed_timestamp_seconds > time() - $__range_s)\n  * on(node) group_left()\n  oke_node_health_report_last_repair_info{dry_run="false", result="Completed"}\n)\nor vector(0)',
    { w: 4, h: 4, x: 8, y: 0 },
    id=3,
  ),
  statPanel(
    'Repairs Failed (time range)',
    'count(\n  (oke_node_health_report_last_repair_completed_timestamp_seconds > time() - $__range_s)\n  * on(node) group_left()\n  oke_node_health_report_last_repair_info{result="Failed"}\n)\nor vector(0)',
    { w: 4, h: 4, x: 12, y: 0 },
    id=4,
  ),
  statPanel(
    'Nodes with Stale Health Results',
    'count(max by(hostname) (gfm_passive_result_age_seconds > 900 or gfm_hpc_fault_file_age_seconds > 900)) or vector(0)',
    { w: 4, h: 4, x: 16, y: 0 },
    id=10,
  ),
  statPanel(
    'Nodes with Scan Errors (last 15m)',
    'count(\n  count by(hostname) (\n    (increase(gfm_scan_total{result!="success"}[15m]) > 0)\n    or\n    (increase(gfm_hpc_scan_total{result!="success"}[15m]) > 0)\n  )\n)\nor vector(0)',
    { w: 4, h: 4, x: 20, y: 0 },
    id=11,
  ),
  panel.table(
    'Repair Status',
    [
      instantTable(
        '(oke_node_health_report_repair_started_timestamp_seconds > 0) * 1000\n* on(node) group_left(action, phase, terminal_state, dry_run, admission)\noke_node_health_report_repair_info',
        'A'
      ),
    ],
    { w: 24, h: 7, x: 0, y: 4 },
    5,
    config=tableConfig({ Value: 'Started', node: 'Node', action: 'Action', phase: 'Phase', terminal_state: 'Terminal State', dry_run: 'Dry Run', admission: 'Admission' }, ['Started']),
  ),
  panel.table(
    'Fault Signals',
    [
      instantTable('(oke_node_health_report_signal_last_observed_timestamp_seconds > 0) * 1000', 'A'),
      instantTable('(oke_node_health_report_signal_first_observed_timestamp_seconds > 0) * 1000', 'B'),
    ],
    { w: 24, h: 8, x: 0, y: 11 },
    6,
    config=tableConfig({ 'Value #A': 'Last Seen', 'Value #B': 'First Seen', node: 'Node', source: 'Source', fault_code: 'Fault Code', action: 'Action' }, ['Last Seen', 'First Seen']),
  ),
  panel.table(
    'Last Repair Attempts',
    [
      instantTable(
        '(oke_node_health_report_last_repair_completed_timestamp_seconds > 0) * 1000\n* on(node) group_left(action, result, dry_run)\noke_node_health_report_last_repair_info',
        'A'
      ),
    ],
    { w: 12, h: 7, x: 0, y: 19 },
    7,
    config=tableConfig({ Value: 'Completed', node: 'Node', action: 'Action', result: 'Result', dry_run: 'Dry Run' }, ['Completed']),
  ),
  panel.table(
    'Maintenance Events',
    [
      instantTable('(oke_node_health_report_maintenance_event_last_observed_timestamp_seconds > 0) * 1000', 'A'),
    ],
    { w: 12, h: 7, x: 12, y: 19 },
    8,
    config=tableConfig({ Value: 'Last Seen', node: 'Node', action: 'Action', maintenance_state: 'State' }, ['Last Seen']),
  ),
  stateTimelinePanel(
    'Repair Phase History',
    'max by(node, phase) (oke_node_health_report_repair_info{phase!=""})',
    '{{node}} / {{phase}}',
    { w: 24, h: 8, x: 0, y: 26 },
    id=9,
    perPage=20,
    valueMap={ '1': { color: 'blue', text: 'Active' } },
  ),
  panel.table(
    'Fault Monitor Scan Errors (last 15m)',
    [
      instantTable(
        'label_replace(\n  sum by(hostname, result) (increase(gfm_scan_total{result!="success"}[15m])) > 0,\n  "input", "Health check results", "", ""\n)\nor\nlabel_replace(\n  sum by(hostname, result) (increase(gfm_hpc_scan_total{result!="success"}[15m])) > 0,\n  "input", "FMS fault file", "", ""\n)',
        'A'
      ),
    ],
    { w: 24, h: 6, x: 0, y: 34 },
    12,
    config=tableConfig({ Value: 'Failed Scans', hostname: 'Node', input: 'Input', result: 'Result' }, [], sortColumn='Failed Scans')
           + { fieldConfig+: { overrides+: [{ matcher: { id: 'byName', options: 'Failed Scans' }, properties: [{ id: 'decimals', value: 0 }] }] } },
  ),
], setPanelIDs=false)
