local g = import './g.libsonnet';

function(title, promql, legend, gridPos, panelLinks, fieldLinks, id=null, valueMap={
  '0': { text: 'Failed', color: 'red' },
  '1': { text: 'Healthy', color: 'green' },
  '2': { text: 'Unknown', color: 'yellow' },
})
  g.panel.stat.new(title)
  + g.panel.stat.queryOptions.withTargets([
    g.query.prometheus.new('$PROMETHEUS_DS', promql)
    + g.query.prometheus.withLegendFormat(legend),
  ])
  + g.panel.stat.standardOptions.withUnit('none')
  + g.panel.stat.options.withTextMode('name')
  + g.panel.stat.options.withColorMode('background')
  + g.panel.stat.options.withGraphMode('none')
  + g.panel.stat.standardOptions.withMappings(
    g.panel.stat.standardOptions.mapping.ValueMap.withType()
    + g.panel.stat.standardOptions.mapping.ValueMap.withOptions(valueMap)
  )
  + g.panel.stat.gridPos.withW(gridPos.w)
  + g.panel.stat.gridPos.withH(gridPos.h)
  + g.panel.stat.gridPos.withX(gridPos.x)
  + g.panel.stat.gridPos.withY(gridPos.y)
  + g.panel.stat.panelOptions.withLinks(panelLinks)
  + g.panel.stat.standardOptions.withLinks(fieldLinks)
  + (if id == null then {} else { id: id })
