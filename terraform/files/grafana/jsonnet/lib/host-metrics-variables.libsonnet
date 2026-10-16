local g = import './g.libsonnet';
local var = g.dashboard.variable;

local query(name, label, metric, labelName, datasource, includeAll=true) =
  var.query.new(name)
  + var.query.withDatasourceFromVariable(datasource)
  + var.query.queryTypes.withLabelValues(labelName, metric)
  + var.query.generalOptions.withLabel(label)
  + var.query.selectionOptions.withMulti()
  + (if includeAll then var.query.selectionOptions.withIncludeAll(customAllValue='.*') else var.query.selectionOptions.withIncludeAll(false))
  + var.query.withRefresh(1);

{
  prometheus:
    var.datasource.new('PROMETHEUS_DS', 'prometheus')
    + var.datasource.generalOptions.showOnDashboard.withValueOnly(),

  instance_shape: query('instance_shape', 'Instance Shape', 'node_uname_info', 'instance_shape', self.prometheus),
  // No All option, so the dashboard opens on the first node. All nodes at once are too large to render.
  hostname: query('hostname', 'Node', 'up{instance_shape=~"$instance_shape"}', 'hostname', self.prometheus, includeAll=false),
  oci_name: query('oci_name', 'Display Name', 'up{instance_shape=~"$instance_shape"}', 'oci_name', self.prometheus),
  fstype: query('fstype', 'File System Type', 'node_filesystem_free_bytes', 'fstype', self.prometheus),
  // Devices of the selected nodes, without the per-pod interfaces (oci for NPN, veth for flannel) that change with every pod.
  device: query('device', 'Device', 'node_network_receive_bytes_total{hostname=~"$hostname",device!~"lo|docker.*|rdma.*|oci.*|veth.*"}', 'device', self.prometheus),
  mountpoint: query('mountpoint', 'Mountpoint', 'node_filesystem_free_bytes', 'mountpoint', self.prometheus),
}
