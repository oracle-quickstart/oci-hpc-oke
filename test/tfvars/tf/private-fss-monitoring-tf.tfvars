# Private control plane with public bastion + operator so Terraform can reach
# the k8s API via the operator VM to create the FSS PV and deploy monitoring.
create_public_subnets         = true
control_plane_is_public       = false
preferred_kubernetes_services = "public"
cni_type                      = "VCN-Native Pod Networking"

create_bastion             = true
bastion_is_public          = true
create_operator            = true
create_oci_bastion_service = true

create_fss    = true
create_lustre = false

deploy_to_oke_from_orm = false

install_monitoring                                  = true
install_node_problem_detector_kube_prometheus_stack = true
install_grafana                                     = true
install_grafana_dashboards                          = true
install_nvidia_dcgm_exporter                        = false
install_amd_device_metrics_exporter                 = false
install_mpi_operator                                = false
install_kueue                                       = false
install_oci_hpc_oke_utils                           = false
install_rdma_labeler                                = false
use_lets_encrypt_prod_endpoint                      = false
setup_alerting                                      = false

worker_cpu_enabled  = false
worker_gpu_enabled  = false
worker_rdma_enabled = false

create_policies      = true
create_dynamic_group = true
