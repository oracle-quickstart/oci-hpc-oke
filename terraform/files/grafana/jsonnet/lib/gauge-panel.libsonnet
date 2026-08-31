local g = import './g.libsonnet';

function(title, promql, gridPos, id=null, legend=null, thresholdSteps=[
  g.panel.gauge.thresholdStep.withColor('green') + g.panel.gauge.thresholdStep.withValue(0),
  g.panel.gauge.thresholdStep.withColor('yellow') + g.panel.gauge.thresholdStep.withValue(70),
  g.panel.gauge.thresholdStep.withColor('orange') + g.panel.gauge.thresholdStep.withValue(85),
  g.panel.gauge.thresholdStep.withColor('red') + g.panel.gauge.thresholdStep.withValue(95),
])
  g.panel.gauge.new(title)
  + g.panel.gauge.queryOptions.withTargets([
    g.query.prometheus.new(
      '$PROMETHEUS_DS',
      promql,
    )
    + { refId: 'A', range: true }
    + (if legend == null then {} else { legendFormat: legend }),
  ])
  + g.panel.gauge.gridPos.withW(gridPos.w)
  + g.panel.gauge.gridPos.withH(gridPos.h)
  + g.panel.gauge.gridPos.withX(gridPos.x)
  + g.panel.gauge.gridPos.withY(gridPos.y)
  + g.panel.gauge.standardOptions.withUnit('percent')
  + g.panel.gauge.standardOptions.thresholds.withMode('absolute')
  + g.panel.gauge.standardOptions.thresholds.withSteps(thresholdSteps)
  + { options+: {
    minVizHeight: 75,
    minVizWidth: 75,
    orientation: 'auto',
    reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false },
    showThresholdLabels: false,
    showThresholdMarkers: true,
    sizing: 'auto',
  } }
  + (if id == null then {} else { id: id })
