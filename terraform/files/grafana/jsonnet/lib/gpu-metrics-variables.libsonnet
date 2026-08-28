local g = import './g.libsonnet';
local var = g.dashboard.variable;

{
  prometheus:
    var.datasource.new('PROMETHEUS_DS', 'prometheus')
    + var.datasource.generalOptions.showOnDashboard.withValueOnly(),

  instance_shape:
    var.query.new('instance_shape')
    + var.query.withDatasourceFromVariable(self.prometheus)
    + var.query.queryTypes.withLabelValues('instance_shape', 'node_uname_info')
    + var.query.generalOptions.withLabel('Instance Shape')
    + var.query.selectionOptions.withMulti()
    + var.query.selectionOptions.withIncludeAll()
    + var.query.withRefresh(1),

  hostname:
    var.query.new('hostname')
    + var.query.withDatasourceFromVariable(self.prometheus)
    + var.query.queryTypes.withLabelValues('hostname', 'up{instance_shape=~"$instance_shape"}')
    + var.query.generalOptions.withLabel('Node')
    + var.query.selectionOptions.withMulti()
    + var.query.selectionOptions.withIncludeAll()
    + var.query.withRefresh(1),

  oci_name:
    var.query.new('oci_name')
    + var.query.withDatasourceFromVariable(self.prometheus)
    + var.query.queryTypes.withLabelValues('oci_name', 'up{instance_shape=~"$instance_shape"}')
    + var.query.generalOptions.withLabel('Display Name')
    + var.query.selectionOptions.withMulti()
    + var.query.selectionOptions.withIncludeAll()
    + var.query.withRefresh(1),
}
