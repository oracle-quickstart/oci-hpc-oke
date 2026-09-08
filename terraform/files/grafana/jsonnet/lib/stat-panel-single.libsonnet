local g = import './g.libsonnet';

function(title, promql, gridPos, id=null, instant=true, legend=null)
  g.panel.stat.new(title)
  + g.panel.stat.queryOptions.withTargets([
    g.query.prometheus.new(
      '$PROMETHEUS_DS',
      promql,
    )
    + { refId: 'A', instant: instant, range: !instant }
    + (if legend == null then {} else { legendFormat: legend }),
  ])
  + g.panel.stat.gridPos.withW(gridPos.w)
  + g.panel.stat.gridPos.withH(gridPos.h)
  + g.panel.stat.gridPos.withX(gridPos.x)
  + g.panel.stat.gridPos.withY(gridPos.y)
  + g.panel.stat.options.withGraphMode('none')
  + g.panel.stat.standardOptions.thresholds.withMode('absolute')
  + g.panel.stat.standardOptions.thresholds.withSteps([{ color: 'green', value: 0 }])
  + { options+: {
    colorMode: 'value',
    justifyMode: 'auto',
    orientation: 'auto',
    reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false },
    textMode: 'auto',
  } }
  + (if id == null then {} else { id: id })
