# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

# Terraform
output "state_id" { value = module.oke.state_id }
output "stack_version" { value = "v25.10.0" }

# Network
output "vcn_id" { value = module.oke.vcn_id }
output "vcn_name" { value = local.vcn_name }
output "ig_route_table_id" { value = module.oke.ig_route_table_id }
output "nat_route_table_id" { value = module.oke.nat_route_table_id }

# Bastion
output "bastion_id" { value = module.oke.bastion_id }
output "bastion_public_ip" { value = module.oke.bastion_public_ip }
output "bastion_ssh_command" { value = var.create_bastion ? module.oke.ssh_to_bastion : "" }
output "bastion_subnet_id" { value = module.oke.bastion_subnet_id }
output "bastion_subnet_cidr" { value = module.oke.bastion_subnet_cidr }
output "bastion_nsg_id" { value = module.oke.bastion_nsg_id }

# Operator
output "operator_id" { value = module.oke.operator_id }
output "operator_private_ip" { value = module.oke.operator_private_ip }
output "operator_ssh_command" { value = var.create_operator ? module.oke.ssh_to_operator : "" }
output "operator_subnet_id" { value = module.oke.operator_subnet_id }
output "operator_subnet_cidr" { value = module.oke.operator_subnet_cidr }
output "operator_nsg_id" { value = module.oke.operator_nsg_id }

# Cluster
output "cluster_id" { value = module.oke.cluster_id }
output "cluster_name" { value = local.cluster_name }
output "cluster_public_endpoint" { value = var.control_plane_is_public ? local.cluster_public_endpoint : "" }
output "cluster_private_endpoint" { value = local.cluster_private_endpoint }
output "cluster_ca_cert" { value = base64decode(module.oke.cluster_ca_cert) }
output "control_plane_subnet_id" { value = module.oke.control_plane_subnet_id }
output "control_plane_subnet_cidr" { value = module.oke.control_plane_subnet_cidr }
output "control_plane_nsg_id" { value = module.oke.control_plane_nsg_id }
output "int_lb_subnet_id" { value = module.oke.int_lb_subnet_id }
output "int_lb_subnet_cidr" { value = module.oke.int_lb_subnet_cidr }
output "int_lb_nsg_id" { value = module.oke.int_lb_nsg_id }
output "pub_lb_subnet_id" { value = module.oke.pub_lb_subnet_id }
output "pub_lb_subnet_cidr" { value = module.oke.pub_lb_subnet_cidr }
output "pub_lb_nsg_id" { value = module.oke.pub_lb_nsg_id }
output "pod_subnet_id" { value = module.oke.pod_subnet_id }
output "pod_subnet_cidr" { value = module.oke.pod_subnet_cidr }
output "pod_nsg_id" { value = module.oke.pod_nsg_id }

# Workers
output "worker_subnet_id" { value = module.oke.worker_subnet_id }
output "worker_nsg_id" { value = module.oke.worker_nsg_id }
output "worker_subnet_cidr" { value = module.oke.worker_subnet_cidr }
output "worker_ops_pool_id" { value = lookup(module.oke.worker_pool_ids, "oke-system", null) }
output "worker_cpu_pool_id" { value = lookup(module.oke.worker_pool_ids, "oke-cpu", null) }
output "worker_gpu_pool_id" { value = lookup(module.oke.worker_pool_ids, "oke-gpu", null) }
output "worker_rdma_pool_id" { value = lookup(module.oke.worker_pool_ids, "oke-rdma", null) }

# Monitoring

output "grafana_fetch_endpoint_command" {
  value = alltrue([var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public"]) ? format("kubectl get ingress -n %v -l app.kubernetes.io/instance=kube-prometheus-stack -o jsonpath='{.items[0].spec.rules[0].host}'", var.monitoring_namespace) : format("kubectl get svc -n %v -l app.kubernetes.io/instance=kube-prometheus-stack,app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'", var.monitoring_namespace)
}

output "grafana_url" {
  value = var.install_node_problem_detector_kube_prometheus_stack ? (
    var.preferred_kubernetes_services == "public" ?
    format("https://grafana.%s.sslip.io", try(data.kubernetes_service.nginx_lb[0].status[0].load_balancer[0].ingress[0].ip, try(data.oci_load_balancer_load_balancers.lbs[0].load_balancers[0].ip_addresses[0], "N/A"))) :
    format("http://%s", try(data.kubernetes_service.grafana_internal_ip[0].status[0].load_balancer[0].ingress[0].ip, try(data.oci_load_balancer_load_balancers.lbs[0].load_balancers[0].ip_addresses[0], try(data.oci_load_balancer_load_balancers.internal_lbs[0].load_balancers[0].ip_addresses[0], "N/A"))))
  ) : "N/A"
}

output "grafana_admin_password" {
  value = nonsensitive(random_password.grafana_admin_password.result)
}

output "prom_server_port_forward" {
  value = format("kubectl port-forward -n %v svc/kube-prometheus-stack-prometheus 9090:9090", var.monitoring_namespace)
}

output "grafana_port_forward" {
  value = format("kubectl port-forward -n %v svc/kube-prometheus-stack-grafana 3000:80", var.monitoring_namespace)
}

output "access_k8s_public_endpoint" {
  value = var.control_plane_is_public ? format("oci ce cluster create-kubeconfig --cluster-id %v --file $HOME/.kube/config --region %v --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT", module.oke.cluster_id, var.region) : "N/A"
}

output "access_k8s_private_endpoint" {
  value = format("oci ce cluster create-kubeconfig --cluster-id %v --file $HOME/.kube/config --region %v --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT", module.oke.cluster_id, var.region)
}

# output "cluster_orm_endpoint" {
#   value = local.cluster_orm_endpoint
# }

# output "deploy_to_oke_from_orm" {
#   value = var.deploy_to_oke_from_orm
# }

# output "current_user_ocid" {
#   value = var.current_user_ocid
# }