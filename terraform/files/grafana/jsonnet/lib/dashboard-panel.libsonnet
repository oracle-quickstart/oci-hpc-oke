local g = import './g.libsonnet';

local grid(panel, gridPos) =
  panel
  { gridPos: gridPos };

local finish(panel, id, config) =
  panel
  + config
  + { id: id };

{
  timeSeries(title, targets, gridPos, id, config={}):
    finish(
      grid(g.panel.timeSeries.new(title), gridPos)
      + g.panel.timeSeries.queryOptions.withTargets(targets),
      id,
      config
    ),

  stat(title, targets, gridPos, id, config={}):
    finish(
      grid(g.panel.stat.new(title), gridPos)
      + g.panel.stat.queryOptions.withTargets(targets),
      id,
      config
    ),

  gauge(title, targets, gridPos, id, config={}):
    finish(
      grid(g.panel.gauge.new(title), gridPos)
      + g.panel.gauge.queryOptions.withTargets(targets),
      id,
      config
    ),

  table(title, targets, gridPos, id, config={}):
    finish(
      grid(g.panel.table.new(title), gridPos)
      + g.panel.table.queryOptions.withTargets(targets),
      id,
      config
    ),

  text(title, gridPos, id, config={}):
    finish(grid(g.panel.text.new(title), gridPos), id, config),

  row(title, panels, gridPos, id, config={}):
    finish(
      grid(g.panel.row.new(title), gridPos)
      + { panels: panels },
      id,
      config
    ),
}
