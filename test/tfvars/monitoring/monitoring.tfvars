# Monitoring overrides (provider path).

install_monitoring                             = true
install_node_problem_detector_kube_prometheus_stack = true
install_grafana                                = true
install_grafana_dashboards                     = true
install_nvidia_dcgm_exporter                   = false
install_amd_device_metrics_exporter            = false
setup_alerting                                 = false
preferred_kubernetes_services                  = "public"
use_lets_encrypt_prod_endpoint = false