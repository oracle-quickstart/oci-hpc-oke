local g = import './g.libsonnet';
local var = g.dashboard.variable;

{
  datasource(name, plugin, config={}):
    var.datasource.new(name, plugin)
    + config,

  query(name, datasource, query, config={}):
    var.query.new(name)
    + { datasource: datasource, query: query }
    + config,
}
