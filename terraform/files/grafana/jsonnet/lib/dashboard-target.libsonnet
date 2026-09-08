local g = import './g.libsonnet';

{
  prometheus(datasource, expr, config={}):
    g.query.prometheus.new(datasource, expr)
    + config,

  expression(config): config,
}
