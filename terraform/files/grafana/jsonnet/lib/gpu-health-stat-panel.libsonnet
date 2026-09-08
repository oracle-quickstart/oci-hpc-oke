local g = import './g.libsonnet';

function(title, promql, gridPos, id=null)
  g.panel.stat.new(title)
  + g.panel.stat.queryOptions.withTargets([
    g.query.prometheus.new(
      '$PROMETHEUS_DS',
      promql,
    )
    + { refId: 'A', range: true },
  ])
  + g.panel.stat.options.withOrientation('vertical')
  + g.panel.stat.standardOptions.withDisplayName('${__field.labels.gpu_id}')
  + g.panel.stat.standardOptions.withMappings(
    g.panel.stat.standardOptions.mapping.ValueMap.withType()
    + g.panel.stat.standardOptions.mapping.ValueMap.withOptions({
      '0': { text: 'Unhealthy', color: 'red' },
      '1': { text: 'Healthy', color: 'green' },
    })
  )
  + g.panel.stat.standardOptions.withUnit('none')
  + g.panel.stat.standardOptions.thresholds.withMode('absolute')
  + g.panel.stat.standardOptions.thresholds.withSteps([{ color: 'green', value: 0 }, { color: 'red', value: 80 }])
  + g.panel.stat.gridPos.withW(gridPos.w)
  + g.panel.stat.gridPos.withH(gridPos.h)
  + g.panel.stat.gridPos.withX(gridPos.x)
  + g.panel.stat.gridPos.withY(gridPos.y)
  + g.panel.stat.options.text.withValueSize(15)
  + g.panel.stat.options.text.withTitleSize(15)
  + (if id == null then {} else { id: id })
