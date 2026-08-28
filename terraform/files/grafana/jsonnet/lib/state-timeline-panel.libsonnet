local g = import './g.libsonnet';

function(title, promql, legend, gridPos, id=null, perPage=25, valueMap={
  '0': { text: 'Failed', color: 'red' },
  '1': { text: 'OK', color: 'green' },
  '2': { text: 'Unknown', color: 'yellow' },
})
  g.panel.stateTimeline.new(title)
  + g.panel.stateTimeline.queryOptions.withTargets([
    g.query.prometheus.new('$PROMETHEUS_DS', promql)
    + g.query.prometheus.withLegendFormat(legend),
  ])
  + g.panel.stateTimeline.options.withShowValue('never')
  + g.panel.stateTimeline.options.withPerPage(value=perPage)
  + g.panel.stateTimeline.standardOptions.withMappings(
    g.panel.stateTimeline.standardOptions.mapping.ValueMap.withType()
    + g.panel.stateTimeline.standardOptions.mapping.ValueMap.withOptions(valueMap)
  )
  + g.panel.stateTimeline.gridPos.withW(gridPos.w)
  + g.panel.stateTimeline.gridPos.withH(gridPos.h)
  + g.panel.stateTimeline.gridPos.withX(gridPos.x)
  + g.panel.stateTimeline.gridPos.withY(gridPos.y)
  + (if id == null then {} else { id: id })
