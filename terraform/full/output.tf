# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

# Terraform
output "state_id" { value = module.oke.state_id }

# Identity
output "dynamic_group_ids" { value = module.oke.dynamic_group_ids }
output "policy_statements" { value = module.oke.policy_statements }

# Network
output "vcn_id" { value = module.oke.vcn_id }
output "vcn_name" { value = local.vcn_name }
output "ig_route_table_id" { value = module.oke.ig_route_table_id }
output "nat_route_table_id" { value = module.oke.nat_route_table_id }

# Bastion
output "bastion_id" { value = module.oke.bastion_id }
output "bastion_public_ip" { value = module.oke.bastion_public_ip }
output "bastion_ssh_command" { value = module.oke.ssh_to_bastion }
output "bastion_subnet_id" { value = module.oke.bastion_subnet_id }
output "bastion_subnet_cidr" { value = module.oke.bastion_subnet_cidr }
output "bastion_nsg_id" { value = module.oke.bastion_nsg_id }

# Operator
output "operator_id" { value = module.oke.operator_id }
output "operator_private_ip" { value = module.oke.operator_private_ip }
output "operator_ssh_command" { value = module.oke.ssh_to_operator }
output "operator_subnet_id" { value = module.oke.operator_subnet_id }
output "operator_subnet_cidr" { value = module.oke.operator_subnet_cidr }
output "operator_nsg_id" { value = module.oke.operator_nsg_id }

# Cluster
output "cluster_id" { value = module.oke.cluster_id }
output "cluster_name" { value = local.cluster_name }
output "cluster_public_endpoint" { value = local.cluster_public_endpoint }
output "cluster_private_endpoint" { value = local.cluster_private_endpoint }
output "cluster_kubeconfig" { value = module.oke.cluster_kubeconfig }
output "cluster_ca_cert" { value = base64decode(module.oke.cluster_ca_cert) }
output "control_plane_subnet_id" { value = module.oke.control_plane_subnet_id }
output "control_plane_subnet_cidr" { value = module.oke.control_plane_subnet_cidr }
output "control_plane_nsg_id" { value = module.oke.control_plane_nsg_id }
output "int_lb_subnet_id" { value = module.oke.int_lb_subnet_id }
output "int_lb_subnet_cidr" { value = module.oke.int_lb_subnet_cidr }
output "pub_lb_subnet_id" { value = module.oke.pub_lb_subnet_id }
output "pub_lb_subnet_cidr" { value = module.oke.pub_lb_subnet_cidr }

# Workers
output "worker_subnet_id" { value = module.oke.worker_subnet_id }
output "worker_nsg_id" { value = module.oke.worker_nsg_id }
output "worker_ops_pool_id" { value = lookup(module.oke.worker_pool_ids, "oke-ops", null) }
output "worker_cpu_pool_id" { value = lookup(module.oke.worker_pool_ids, "oke-cpu", null) }
output "worker_gpu_pool_id" { value = lookup(module.oke.worker_pool_ids, "oke-gpu", null) }
output "worker_rdma_pool_id" { value = lookup(module.oke.worker_pool_ids, "oke-rdma", null) }

# Storage
#output "fss_ad" { value = oci_file_storage_file_system.fss.0.availability_domain }
#output "fss_filesystem_id" { value = oci_file_storage_file_system.fss.0.id }
#output "fss_volume_name" { value = local.fss_volume_name }
#output "fss_nsg_id" { value = local.fss_nsg_id }
#output "fss_subnet_id" { value = local.fss_subnet_id }
#output "fss_mount_target_id" { value = oci_file_storage_mount_target.fss.0.id }
#output "fss_export_set_id" { value = oci_file_storage_export_set.fss.0.id }

# Monitoring
output "grafana_admin_password" {
  value = nonsensitive(random_password.grafana_admin_password.result)
}
output "prometheus_stack_version" { value = local.prometheus_stack_version }
output "prometheus_pushgateway_version" { value = local.prometheus_pushgateway_version }
output "prometheus_adapter_version" { value = local.prometheus_adapter_version }
output "metrics_server_version" { value = local.metrics_server_version }
output "dcgm_exporter_version" { value = local.dcgm_exporter_version }

output "prom_server_port_forward" {
  value = format("kubectl port-forward -n %v svc/prom-kube-prometheus-stack-prometheus 9090:9090", var.monitoring_namespace)
}
output "prom_pushgateway_port_forward" {
  value = format("kubectl port-forward -n %v svc/prom-pushgateway-prometheus-pushgateway 9091:9091", var.monitoring_namespace)
}
output "grafana_port_forward" {
  value = format("kubectl port-forward -n %v svc/prom-grafana 3000:80", var.monitoring_namespace)
}

output "access_k8s_public_endpoint" {
  value = format("oci ce cluster create-kubeconfig --cluster-id %v --file $HOME/.kube/config --region %v --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT", module.oke.cluster_id, var.region)
}

output "access_k8s_private_endpoint" {
  value = format("oci ce cluster create-kubeconfig --cluster-id %v --file $HOME/.kube/config --region %v --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT", module.oke.cluster_id, var.region)
}