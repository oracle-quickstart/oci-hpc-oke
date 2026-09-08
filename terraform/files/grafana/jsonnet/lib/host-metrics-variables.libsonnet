local g = import './g.libsonnet';
local var = g.dashboard.variable;

local query(name, label, metric, labelName, datasource) =
  var.query.new(name)
  + var.query.withDatasourceFromVariable(datasource)
  + var.query.queryTypes.withLabelValues(labelName, metric)
  + var.query.generalOptions.withLabel(label)
  + var.query.selectionOptions.withMulti()
  + var.query.selectionOptions.withIncludeAll()
  + var.query.withRefresh(1);

{
  prometheus:
    var.datasource.new('PROMETHEUS_DS', 'prometheus')
    + var.datasource.generalOptions.showOnDashboard.withValueOnly(),

  instance_shape: query('instance_shape', 'Instance Shape', 'node_uname_info', 'instance_shape', self.prometheus),
  hostname: query('hostname', 'Node', 'up{instance_shape=~"$instance_shape"}', 'hostname', self.prometheus),
  oci_name: query('oci_name', 'Display Name', 'up{instance_shape=~"$instance_shape"}', 'oci_name', self.prometheus),
  fstype: query('fstype', 'File System Type', 'node_filesystem_free_bytes', 'fstype', self.prometheus),
  interface: query('interface', 'Interface', 'rdma_np_ecn_marked_roce_packets', 'interface', self.prometheus),
  device: query('device', 'Device', 'node_network_receive_bytes_total', 'device', self.prometheus),
  mountpoint: query('mountpoint', 'Mountpoint', 'node_filesystem_free_bytes', 'mountpoint', self.prometheus),
}
