local g = import './g.libsonnet';
local var = g.dashboard.variable;

{
  prometheus:
    var.datasource.new('PROMETHEUS_DS', 'prometheus')
    + var.datasource.generalOptions.showOnDashboard.withValueOnly(),

  instance_shape:
    var.query.new('instance_shape')
    + var.query.queryTypes.withLabelValues('instance_shape', 'node_uname_info')
    + var.query.generalOptions.withLabel('Instance Shape')
    + var.query.selectionOptions.withMulti()
    + var.query.selectionOptions.withIncludeAll()
    + var.query.withRefresh(1),
}
