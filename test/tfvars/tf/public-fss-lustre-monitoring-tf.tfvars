create_public_subnets         = true
control_plane_is_public       = true
preferred_kubernetes_services = "public"
cni_type                      = "VCN-Native Pod Networking"

create_bastion  = false
create_operator = false

create_fss    = true
create_lustre = true

deploy_to_oke_from_orm = false

install_monitoring                                  = true
install_node_problem_detector_kube_prometheus_stack = true
install_grafana                                     = true
install_grafana_dashboards                          = true
install_amd_device_metrics_exporter                 = false
install_mpi_operator                                = false
install_kueue                                       = false
install_oci_hpc_oke_utils                           = false
install_rdma_labeler                                = false
use_lets_encrypt_prod_endpoint                      = false
setup_alerting                                      = false

worker_cpu_enabled  = true
worker_gpu_enabled  = true
worker_rdma_enabled = false

create_policies      = true
create_dynamic_group = true
