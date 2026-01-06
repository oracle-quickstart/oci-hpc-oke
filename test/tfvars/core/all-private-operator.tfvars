create_policies = false

create_bastion  = false
bastion_is_public = false
create_operator = true

control_plane_is_public = false
preferred_kubernetes_services = "internal"
create_public_subnets = false

cni_type = "VCN-Native Pod Networking"

create_bv_high = false
create_fss     = false
create_lustre  = false

deploy_to_oke_from_orm = false

install_monitoring                             = false
install_node_problem_detector_kube_prometheus_stack = false
install_grafana                                = false
install_grafana_dashboards                     = false
install_nvidia_dcgm_exporter                   = false
install_amd_device_metrics_exporter            = false
setup_alerting                                 = false

worker_cpu_enabled  = false
worker_gpu_enabled  = false
worker_rdma_enabled = false
