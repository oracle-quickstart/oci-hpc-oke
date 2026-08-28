local g = import './g.libsonnet';

function(title, promql, legend, unit, gridPos, legendOptions={
  calcs: ['p99', 'p95', 'p90'],
  displayMode: 'table',
  placement: 'right',
}, id=null, thresholdSteps=null)
  g.panel.timeSeries.new(title)
  + g.panel.timeSeries.queryOptions.withTargets([
    g.query.prometheus.new(
      '$PROMETHEUS_DS',
      promql,
    )
    + g.query.prometheus.withLegendFormat(legend),
  ])
  + g.panel.timeSeries.standardOptions.withUnit(unit)
  + (if thresholdSteps == null then {} else
       g.panel.timeSeries.standardOptions.thresholds.withMode('absolute')
       + g.panel.timeSeries.standardOptions.thresholds.withSteps(thresholdSteps))
  + g.panel.timeSeries.options.withLegend(value=legendOptions)
  + g.panel.timeSeries.gridPos.withW(gridPos.w)
  + g.panel.timeSeries.gridPos.withH(gridPos.h)
  + g.panel.timeSeries.gridPos.withX(gridPos.x)
  + g.panel.timeSeries.gridPos.withY(gridPos.y)
  + (if id == null then {} else { id: id })
