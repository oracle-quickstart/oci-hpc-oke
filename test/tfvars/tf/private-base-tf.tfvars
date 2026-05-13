create_public_subnets         = false
control_plane_is_public       = false
preferred_kubernetes_services = "internal"
cni_type                      = "VCN-Native Pod Networking"

create_bastion             = false
create_operator            = false
create_oci_bastion_service = true

create_fss    = false
create_lustre = false

deploy_to_oke_from_orm = false

install_monitoring                                  = false
install_node_problem_detector_kube_prometheus_stack = false
install_grafana                                     = false
install_grafana_dashboards                          = false
install_amd_device_metrics_exporter                 = false
install_mpi_operator                                = false
install_kueue                                       = false
install_oci_hpc_oke_utils                           = false
install_rdma_labeler                                = false
setup_alerting                                      = false

worker_cpu_enabled  = true
worker_gpu_enabled  = true
worker_rdma_enabled = false

create_policies      = true
create_dynamic_group = true
