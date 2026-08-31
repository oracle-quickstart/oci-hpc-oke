local g = import '../../lib/g.libsonnet';
local variables = import '../../lib/gpu-health-status-variables.libsonnet';
local statHealthPanel = import '../../lib/stat-health-panel.libsonnet';
local stateTimelinePanel = import '../../lib/state-timeline-panel.libsonnet';

g.dashboard.new('GPU Health Status')
+ g.dashboard.withUid('gpu-health')
+ g.dashboard.withDescription('GPU Node Component Health Status\n')
+ g.dashboard.withTimezone('browser')
+ g.dashboard.time.withFrom('now-5m')
+ g.dashboard.graphTooltip.withSharedCrosshair()
+ g.dashboard.withLinks([])
+ g.dashboard.withVariables([
  variables.prometheus,
  variables.hostname,
])
+ g.dashboard.withPanels([
  statHealthPanel(
    'RTTCC',
    '0 * (\n  label_replace(\n        max by(node) (\n          max_over_time(\n            kube_node_status_condition{\n              condition="RdmaRttcc",\n              status="true",\n              node=~"$hostname"\n            }[$__range]\n          )\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    2 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="RdmaRttcc",\n            status="unknown",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    1 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="RdmaRttcc",\n            status="false",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 0, y: 0 },
    id=1,
  ),
  statHealthPanel(
    'OCA Ver',
    '0 * (\n  label_replace(\n        max by(node) (\n          max_over_time(\n            kube_node_status_condition{\n              condition="OcaVersion",\n              status="true",\n              node=~"$hostname"\n            }[$__range]\n          )\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    2 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="OcaVersion",\n            status="unknown",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    1 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="OcaVersion",\n            status="false",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 3, y: 0 },
    id=2,
  ),
  statHealthPanel(
    'RDMA Dev',
    '0 * (\n  label_replace(\n        max by(node) (\n          max_over_time(\n            kube_node_status_condition{\n              condition="RdmaLink",\n              status="true",\n              node=~"$hostname"\n            }[$__range]\n          )\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    2 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="RdmaLink",\n            status="unknown",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    1 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="RdmaLink",\n            status="false",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 6, y: 0 },
    id=3,
  ),
  statHealthPanel(
    'Bus Issue',
    '0 * (\n  label_replace(\n        max by(node) (\n          max_over_time(\n            kube_node_status_condition{\n              condition="GpuBus",\n              status="true",\n              node=~"$hostname"\n            }[$__range]\n          )\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    2 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="GpuBus",\n            status="unknown",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    1 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="GpuBus",\n            status="false",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 9, y: 0 },
    id=4,
  ),
  statHealthPanel(
    'Link Flap',
    '0 * (\n  label_replace(\n        max by(node) (\n          max_over_time(\n            kube_node_status_condition{\n              condition="RdmaLinkFlapping",\n              status="true",\n              node=~"$hostname"\n            }[$__range]\n          )\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    2 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="RdmaLinkFlapping",\n            status="unknown",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    1 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="RdmaLinkFlapping",\n            status="false",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 12, y: 0 },
    id=5,
  ),
  statHealthPanel(
    'GPU Bad Pages',
    '0 * (\n  label_replace(\n        max by(node) (\n          max_over_time(\n            kube_node_status_condition{\n              condition="GpuBadPages",\n              status="true",\n              node=~"$hostname"\n            }[$__range]\n          )\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    2 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="GpuBadPages",\n            status="unknown",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    1 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="GpuBadPages",\n            status="false",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 15, y: 0 },
    id=23,
  ),
  statHealthPanel(
    'Row Remap',
    '0 * (\n  label_replace(\n        max by(node) (\n          max_over_time(\n            kube_node_status_condition{\n              condition="GpuRowRemap",\n              status="true",\n              node=~"$hostname"\n            }[$__range]\n          )\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    2 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="GpuRowRemap",\n            status="unknown",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    1 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="GpuRowRemap",\n            status="false",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 18, y: 0 },
    id=7,
  ),
  statHealthPanel(
    'GPU Count',
    '0 * (\n  label_replace(\n        max by(node) (\n          max_over_time(\n            kube_node_status_condition{\n              condition="GpuCount",\n              status="true",\n              node=~"$hostname"\n            }[$__range]\n          )\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    2 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="GpuCount",\n            status="unknown",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    1 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="GpuCount",\n            status="false",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 21, y: 0 },
    id=24,
  ),
  statHealthPanel(
    'ECC',
    '0 * (\n  label_replace(\n        max by(node) (\n          max_over_time(\n            kube_node_status_condition{\n              condition="GpuEcc",\n              status="true",\n              node=~"$hostname"\n            }[$__range]\n          )\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    2 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="GpuEcc",\n            status="unknown",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    1 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="GpuEcc",\n            status="false",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 0, y: 3 },
    id=6,
  ),
  statHealthPanel(
    'GPU Health',
    '0 * (\n  (\n    (min by(hostname) (min_over_time(amd_gpu_health{hostname=~"$hostname"}[$__range]))) < bool 1\n  ) == 1\n  or\n  (\n    (max by(hostname) (max_over_time(DCGM_EXP_GPU_HEALTH_STATUS{hostname=~"$hostname"}[$__range]))) > bool 0\n  ) == 1\n)\nor\n(\n  (\n  0 * (\n    label_replace(\n      max by(node) (\n        kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu", node=~"$hostname"} > 0\n      ),\n      "hostname", "$1", "node", "(.*)"\n    )\n  )\n  + 2\n)\n  unless on(hostname)\n  (\n    max by(hostname) (\n  present_over_time(amd_gpu_health{hostname=~"$hostname"}[10m])\n)\n    or\n    max by(hostname) (\n  present_over_time(DCGM_EXP_GPU_HEALTH_STATUS{hostname=~"$hostname"}[10m])\n)\n  )\n)\nor\n1 * (\n  (\n    (min by(hostname) (min_over_time(amd_gpu_health{hostname=~"$hostname"}[$__range]))) == bool 1\n  ) == 1\n  or\n  (\n    (max by(hostname) (max_over_time(DCGM_EXP_GPU_HEALTH_STATUS{hostname=~"$hostname"}[$__range]))) == bool 0\n  ) == 1\n)',
    '{{hostname}}',
    { w: 3, h: 3, x: 3, y: 3 },
    id=8,
  ),
  statHealthPanel(
    'Power Throttle / Violation',
    '0 * (\n  (\n    (sum by(hostname) (increase(amd_gpu_violation_ppt_residency_accumulated{hostname=~"$hostname"}[$__range]))) > bool 0\n  ) == 1\n  or\n  (\n    (sum by(hostname) (increase(DCGM_FI_DEV_POWER_VIOLATION{hostname=~"$hostname"}[$__range]))) > bool 0\n  ) == 1\n)\nor\n(\n  (\n  0 * (\n    label_replace(\n      max by(node) (\n        kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu", node=~"$hostname"} > 0\n      ),\n      "hostname", "$1", "node", "(.*)"\n    )\n  )\n  + 2\n)\n  unless on(hostname)\n  (\n    max by(hostname) (\n  present_over_time(amd_gpu_violation_ppt_residency_accumulated{hostname=~"$hostname"}[10m])\n)\n    or\n    max by(hostname) (\n  present_over_time(DCGM_FI_DEV_POWER_VIOLATION{hostname=~"$hostname"}[10m])\n)\n  )\n)\nor\n1 * (\n  (\n    (sum by(hostname) (increase(amd_gpu_violation_ppt_residency_accumulated{hostname=~"$hostname"}[$__range]))) == bool 0\n  ) == 1\n  or\n  (\n    (sum by(hostname) (increase(DCGM_FI_DEV_POWER_VIOLATION{hostname=~"$hostname"}[$__range]))) == bool 0\n  ) == 1\n)',
    '{{hostname}}',
    { w: 3, h: 3, x: 6, y: 3 },
    id=9,
  ),
  statHealthPanel(
    'Processor Hot / Board Limit',
    '0 * (\n  (\n    (sum by(hostname) (increase(amd_gpu_violation_processor_hot_residency_accumulated{hostname=~"$hostname"}[$__range]))) > bool 0\n  ) == 1\n  or\n  (\n    (sum by(hostname) (increase(DCGM_FI_DEV_BOARD_LIMIT_VIOLATION{hostname=~"$hostname"}[$__range]))) > bool 0\n  ) == 1\n)\nor\n(\n  (\n  0 * (\n    label_replace(\n      max by(node) (\n        kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu", node=~"$hostname"} > 0\n      ),\n      "hostname", "$1", "node", "(.*)"\n    )\n  )\n  + 2\n)\n  unless on(hostname)\n  (\n    max by(hostname) (\n  present_over_time(amd_gpu_violation_processor_hot_residency_accumulated{hostname=~"$hostname"}[10m])\n)\n    or\n    max by(hostname) (\n  present_over_time(DCGM_FI_DEV_BOARD_LIMIT_VIOLATION{hostname=~"$hostname"}[10m])\n)\n  )\n)\nor\n1 * (\n  (\n    (sum by(hostname) (increase(amd_gpu_violation_processor_hot_residency_accumulated{hostname=~"$hostname"}[$__range]))) == bool 0\n  ) == 1\n  or\n  (\n    (sum by(hostname) (increase(DCGM_FI_DEV_BOARD_LIMIT_VIOLATION{hostname=~"$hostname"}[$__range]))) == bool 0\n  ) == 1\n)',
    '{{hostname}}',
    { w: 3, h: 3, x: 9, y: 3 },
    id=10,
  ),
  statHealthPanel(
    'Thermal Violation',
    '0 * (\n  (\n    (sum by(hostname) (increase(amd_gpu_violation_socket_thermal_residency_accumulated{hostname=~"$hostname"}[$__range]))) > bool 0\n  ) == 1\n  or\n  (\n    (sum by(hostname) (increase(DCGM_FI_DEV_THERMAL_VIOLATION{hostname=~"$hostname"}[$__range]))) > bool 0\n  ) == 1\n)\nor\n(\n  (\n  0 * (\n    label_replace(\n      max by(node) (\n        kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu", node=~"$hostname"} > 0\n      ),\n      "hostname", "$1", "node", "(.*)"\n    )\n  )\n  + 2\n)\n  unless on(hostname)\n  (\n    max by(hostname) (\n  present_over_time(amd_gpu_violation_socket_thermal_residency_accumulated{hostname=~"$hostname"}[10m])\n)\n    or\n    max by(hostname) (\n  present_over_time(DCGM_FI_DEV_THERMAL_VIOLATION{hostname=~"$hostname"}[10m])\n)\n  )\n)\nor\n1 * (\n  (\n    (sum by(hostname) (increase(amd_gpu_violation_socket_thermal_residency_accumulated{hostname=~"$hostname"}[$__range]))) == bool 0\n  ) == 1\n  or\n  (\n    (sum by(hostname) (increase(DCGM_FI_DEV_THERMAL_VIOLATION{hostname=~"$hostname"}[$__range]))) == bool 0\n  ) == 1\n)',
    '{{hostname}}',
    { w: 3, h: 3, x: 12, y: 3 },
    id=11,
  ),
  statHealthPanel(
    'HBM Thermal / Sync Boost',
    '0 * (\n  (\n    (sum by(hostname) (increase(amd_gpu_violation_hbm_thermal_residency_accumulated{hostname=~"$hostname"}[$__range]))) > bool 0\n  ) == 1\n  or\n  (\n    (sum by(hostname) (increase(DCGM_FI_DEV_SYNC_BOOST_VIOLATION{hostname=~"$hostname"}[$__range]))) > bool 0\n  ) == 1\n)\nor\n(\n  (\n  0 * (\n    label_replace(\n      max by(node) (\n        kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu", node=~"$hostname"} > 0\n      ),\n      "hostname", "$1", "node", "(.*)"\n    )\n  )\n  + 2\n)\n  unless on(hostname)\n  (\n    max by(hostname) (\n  present_over_time(amd_gpu_violation_hbm_thermal_residency_accumulated{hostname=~"$hostname"}[10m])\n)\n    or\n    max by(hostname) (\n  present_over_time(DCGM_FI_DEV_SYNC_BOOST_VIOLATION{hostname=~"$hostname"}[10m])\n)\n  )\n)\nor\n1 * (\n  (\n    (sum by(hostname) (increase(amd_gpu_violation_hbm_thermal_residency_accumulated{hostname=~"$hostname"}[$__range]))) == bool 0\n  ) == 1\n  or\n  (\n    (sum by(hostname) (increase(DCGM_FI_DEV_SYNC_BOOST_VIOLATION{hostname=~"$hostname"}[$__range]))) == bool 0\n  ) == 1\n)',
    '{{hostname}}',
    { w: 3, h: 3, x: 15, y: 3 },
    id=12,
  ),
  statHealthPanel(
    'VR Thermal / Reliability',
    '0 * (\n  (\n    (sum by(hostname) (increase(amd_gpu_violation_vr_thermal_residency_accumulated{hostname=~"$hostname"}[$__range]))) > bool 0\n  ) == 1\n  or\n  (\n    (sum by(hostname) (increase(DCGM_FI_DEV_RELIABILITY_VIOLATION{hostname=~"$hostname"}[$__range]))) > bool 0\n  ) == 1\n)\nor\n(\n  (\n  0 * (\n    label_replace(\n      max by(node) (\n        kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu", node=~"$hostname"} > 0\n      ),\n      "hostname", "$1", "node", "(.*)"\n    )\n  )\n  + 2\n)\n  unless on(hostname)\n  (\n    max by(hostname) (\n  present_over_time(amd_gpu_violation_vr_thermal_residency_accumulated{hostname=~"$hostname"}[10m])\n)\n    or\n    max by(hostname) (\n  present_over_time(DCGM_FI_DEV_RELIABILITY_VIOLATION{hostname=~"$hostname"}[10m])\n)\n  )\n)\nor\n1 * (\n  (\n    (sum by(hostname) (increase(amd_gpu_violation_vr_thermal_residency_accumulated{hostname=~"$hostname"}[$__range]))) == bool 0\n  ) == 1\n  or\n  (\n    (sum by(hostname) (increase(DCGM_FI_DEV_RELIABILITY_VIOLATION{hostname=~"$hostname"}[$__range]))) == bool 0\n  ) == 1\n)',
    '{{hostname}}',
    { w: 3, h: 3, x: 18, y: 3 },
    id=13,
  ),
  statHealthPanel(
    'PCIE Correctable',
    '0 * (\n  ((max by(hostname) (\n    max_over_time(problem_gauge{reason="PcieCorrectable", type="NodeHasPcieErrors", hostname=~"$hostname"}[$__range])\n  )) > bool 0) == 1\n    )\n    or\n    (\n      (\n        0 * (\n          label_replace(\n            max by(node) (\n              kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu", node=~"$hostname"} > 0\n            ),\n            "hostname", "$1", "node", "(.*)"\n          )\n        )\n        + 2\n      )\n      unless on(hostname)\n      max by(hostname) (\n        present_over_time(problem_gauge{reason="PcieCorrectable", type="NodeHasPcieErrors", hostname=~"$hostname"}[10m])\n      )\n    )\n    or\n    1 * (\n  ((max by(hostname) (\n    max_over_time(problem_gauge{reason="PcieCorrectable", type="NodeHasPcieErrors", hostname=~"$hostname"}[$__range])\n  )) == bool 0) == 1\n      and on(hostname)\n      max by(hostname) (\n        present_over_time(problem_gauge{reason="PcieCorrectable", type="NodeHasPcieErrors", hostname=~"$hostname"}[10m])\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 21, y: 3 },
    id=14,
  ),
  statHealthPanel(
    'PCIE Non Fatal',
    '0 * (\n  ((max by(hostname) (\n    max_over_time(problem_gauge{reason="PcieNonFatal", type="NodeHasPcieErrors", hostname=~"$hostname"}[$__range])\n  )) > bool 0) == 1\n    )\n    or\n    (\n      (\n        0 * (\n          label_replace(\n            max by(node) (\n              kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu", node=~"$hostname"} > 0\n            ),\n            "hostname", "$1", "node", "(.*)"\n          )\n        )\n        + 2\n      )\n      unless on(hostname)\n      max by(hostname) (\n        present_over_time(problem_gauge{reason="PcieNonFatal", type="NodeHasPcieErrors", hostname=~"$hostname"}[10m])\n      )\n    )\n    or\n    1 * (\n  ((max by(hostname) (\n    max_over_time(problem_gauge{reason="PcieNonFatal", type="NodeHasPcieErrors", hostname=~"$hostname"}[$__range])\n  )) == bool 0) == 1\n      and on(hostname)\n      max by(hostname) (\n        present_over_time(problem_gauge{reason="PcieNonFatal", type="NodeHasPcieErrors", hostname=~"$hostname"}[10m])\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 0, y: 6 },
    id=15,
  ),
  statHealthPanel(
    'PCIE Fatal',
    '0 * (\n  ((max by(hostname) (\n    max_over_time(problem_gauge{reason="PcieFatal", type="NodeHasPcieErrors", hostname=~"$hostname"}[$__range])\n  )) > bool 0) == 1\n    )\n    or\n    (\n      (\n        0 * (\n          label_replace(\n            max by(node) (\n              kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu", node=~"$hostname"} > 0\n            ),\n            "hostname", "$1", "node", "(.*)"\n          )\n        )\n        + 2\n      )\n      unless on(hostname)\n      max by(hostname) (\n        present_over_time(problem_gauge{reason="PcieFatal", type="NodeHasPcieErrors", hostname=~"$hostname"}[10m])\n      )\n    )\n    or\n    1 * (\n  ((max by(hostname) (\n    max_over_time(problem_gauge{reason="PcieFatal", type="NodeHasPcieErrors", hostname=~"$hostname"}[$__range])\n  )) == bool 0) == 1\n      and on(hostname)\n      max by(hostname) (\n        present_over_time(problem_gauge{reason="PcieFatal", type="NodeHasPcieErrors", hostname=~"$hostname"}[10m])\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 3, y: 6 },
    id=16,
  ),
  statHealthPanel(
    'PCIE Link Width',
    '0 * (\n  label_replace(\n        max by(node) (\n          max_over_time(\n            kube_node_status_condition{\n              condition="GpuPcie",\n              status="true",\n              node=~"$hostname"\n            }[$__range]\n          )\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    2 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="GpuPcie",\n            status="unknown",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )\n    or\n    1 * (\n  label_replace(\n        max by(node) (\n          kube_node_status_condition{\n            condition="GpuPcie",\n            status="false",\n            node=~"$hostname"\n          }\n        ) == 1,\n        "hostname", "$1", "node", "(.*)"\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 6, y: 6 },
    id=18,
  ),
  statHealthPanel(
    'Disk free',
    '0 * (\n  ((min by(hostname) (\n    min_over_time(node_filesystem_avail_bytes{mountpoint="/", device=~"/dev/sd.*", hostname=~"$hostname"}[$__range])\n  )) < bool 50 * 1024 * 1024 * 1024) == 1\n    )\n    or\n    (\n      (\n        0 * (\n          label_replace(\n            max by(node) (\n              kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu", node=~"$hostname"} > 0\n            ),\n            "hostname", "$1", "node", "(.*)"\n          )\n        )\n        + 2\n      )\n      unless on(hostname)\n      max by(hostname) (\n        present_over_time(node_filesystem_avail_bytes{mountpoint="/", device=~"/dev/sd.*", hostname=~"$hostname"}[10m])\n      )\n    )\n    or\n    1 * (\n  ((min by(hostname) (\n    min_over_time(node_filesystem_avail_bytes{mountpoint="/", device=~"/dev/sd.*", hostname=~"$hostname"}[$__range])\n  )) >= bool 50 * 1024 * 1024 * 1024) == 1\n      and on(hostname)\n      max by(hostname) (\n        present_over_time(node_filesystem_avail_bytes{mountpoint="/", device=~"/dev/sd.*", hostname=~"$hostname"}[10m])\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 9, y: 6 },
    id=19,
  ),
  statHealthPanel(
    'Mem free',
    '0 * (\n  ((min by(hostname) (\n    min_over_time(node_memory_MemAvailable_bytes{instance_shape=~"(BM|VM).GPU.*", hostname=~"$hostname"}[$__range])\n  )) < bool 50 * 1024 * 1024 * 1024) == 1\n    )\n    or\n    (\n      (\n        0 * (\n          label_replace(\n            max by(node) (\n              kube_node_status_capacity{resource=~"(amd|nvidia)_com_gpu", node=~"$hostname"} > 0\n            ),\n            "hostname", "$1", "node", "(.*)"\n          )\n        )\n        + 2\n      )\n      unless on(hostname)\n      max by(hostname) (\n        present_over_time(node_memory_MemAvailable_bytes{instance_shape=~"(BM|VM).GPU.*", hostname=~"$hostname"}[10m])\n      )\n    )\n    or\n    1 * (\n  ((min by(hostname) (\n    min_over_time(node_memory_MemAvailable_bytes{instance_shape=~"(BM|VM).GPU.*", hostname=~"$hostname"}[$__range])\n  )) >= bool 50 * 1024 * 1024 * 1024) == 1\n      and on(hostname)\n      max by(hostname) (\n        present_over_time(node_memory_MemAvailable_bytes{instance_shape=~"(BM|VM).GPU.*", hostname=~"$hostname"}[10m])\n      )\n    )',
    '{{hostname}}',
    { w: 3, h: 3, x: 12, y: 6 },
    id=20,
  ),
  stateTimelinePanel(
    'PCIE Health history',
    '0 * label_replace(\n  max by(node) (\n    kube_node_status_condition{condition=~"GpuPcie|NodeHasPcieErrors", status="true", node=~"$hostname"} == 1\n  ),\n  "hostname", "$1", "node", "(.*)"\n)\nor\n2 * label_replace(\n  max by(node) (\n    kube_node_status_condition{condition=~"GpuPcie|NodeHasPcieErrors", status="unknown", node=~"$hostname"} == 1\n  ),\n  "hostname", "$1", "node", "(.*)"\n)\nor\n1 * label_replace(\n  min by(node) (\n    kube_node_status_condition{condition=~"GpuPcie|NodeHasPcieErrors", status="false", node=~"$hostname"}\n  ) == 1,\n  "hostname", "$1", "node", "(.*)"\n)',
    '{{hostname}}',
    { w: 24, h: 12, x: 0, y: 9 },
    id=21,
  ),
  stateTimelinePanel(
    'RDMA Link Flapping history',
    '0 * label_replace(\n  max by(node) (\n    kube_node_status_condition{condition="RdmaLinkFlapping", status="true", node=~"$hostname"} == 1\n  ),\n  "hostname", "$1", "node", "(.*)"\n)\nor\n2 * label_replace(\n  max by(node) (\n    kube_node_status_condition{condition="RdmaLinkFlapping", status="unknown", node=~"$hostname"} == 1\n  ),\n  "hostname", "$1", "node", "(.*)"\n)\nor\n1 * label_replace(\n  max by(node) (\n    kube_node_status_condition{condition="RdmaLinkFlapping", status="false", node=~"$hostname"} == 1\n  ),\n  "hostname", "$1", "node", "(.*)"\n)',
    '{{hostname}}',
    { w: 24, h: 10, x: 0, y: 21 },
    id=22,
  ),
], setPanelIDs=false)
