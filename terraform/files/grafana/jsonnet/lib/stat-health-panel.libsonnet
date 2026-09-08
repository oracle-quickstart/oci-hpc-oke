local g = import './g.libsonnet';

function(title, promql, legend, gridPos, id=null, valueMap={
  '0': { text: 'Failed', color: 'red' },
  '1': { text: 'OK', color: 'green' },
  '2': { text: 'Unknown', color: 'yellow' },
})
  g.panel.stat.new(title)
  + g.panel.stat.queryOptions.withTargets([
    g.query.prometheus.new('$PROMETHEUS_DS', promql)
    + g.query.prometheus.withLegendFormat(legend)
    + { refId: 'A', instant: true, range: false },
  ])
  + g.panel.stat.gridPos.withW(gridPos.w)
  + g.panel.stat.gridPos.withH(gridPos.h)
  + g.panel.stat.gridPos.withX(gridPos.x)
  + g.panel.stat.gridPos.withY(gridPos.y)
  + g.panel.stat.options.withGraphMode('none')
  + g.panel.stat.standardOptions.withMappings(
    g.panel.stat.standardOptions.mapping.ValueMap.withType()
    + g.panel.stat.standardOptions.mapping.ValueMap.withOptions(valueMap)
  )
  + g.panel.stat.standardOptions.thresholds.withMode('absolute')
  + g.panel.stat.standardOptions.thresholds.withSteps([{ color: 'green', value: 0 }, { color: 'red', value: 80 }])
  + { options+: {
    colorMode: 'value',
    justifyMode: 'auto',
    orientation: 'auto',
    reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false },
    textMode: 'auto',
  } }
  + (if id == null then {} else { id: id })
