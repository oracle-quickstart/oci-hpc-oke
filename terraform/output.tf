# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

# Terraform
output "state_id" { value = module.oke.state_id }
output "stack_version" { value = "v25.10.0" }

# Network
output "vcn_id" { value = var.create_vcn ? module.oke.vcn_id : null }
output "vcn_name" { value = var.create_vcn ? local.vcn_name : null }
output "ig_route_table_id" { value = var.create_vcn ? module.oke.ig_route_table_id : null }
output "nat_route_table_id" { value = var.create_vcn ? module.oke.nat_route_table_id : null }

# Bastion
output "bastion_id" { value = var.create_bastion ? module.oke.bastion_id : null }
output "bastion_public_ip" { value = var.create_bastion ? module.oke.bastion_public_ip : "" }
output "bastion_ssh_command" { value = var.create_bastion ? module.oke.ssh_to_bastion : "" }
output "bastion_subnet_id" { value = var.create_vcn ? module.oke.bastion_subnet_id : null }
output "bastion_subnet_cidr" { value = var.create_vcn ? module.oke.bastion_subnet_cidr : null }
output "bastion_nsg_id" { value = var.create_vcn ? module.oke.bastion_nsg_id : null }

# Operator
output "operator_id" { value = var.create_operator ? module.oke.operator_id : null }
output "operator_private_ip" { value = var.create_operator ? module.oke.operator_private_ip : null }
output "operator_ssh_command" { value = var.create_operator ? module.oke.ssh_to_operator : "" }
output "operator_subnet_id" { value = var.create_vcn ? module.oke.operator_subnet_id : null }
output "operator_subnet_cidr" { value = var.create_vcn ? module.oke.operator_subnet_cidr : null }
output "operator_nsg_id" { value = var.create_vcn ? module.oke.operator_nsg_id : null }

# Cluster
output "cluster_id" { value = module.oke.cluster_id }
output "cluster_name" { value = local.cluster_name }
output "cluster_public_endpoint" { value = var.create_cluster && var.control_plane_is_public ? local.cluster_public_endpoint : "" }
output "cluster_private_endpoint" { value = var.create_cluster ? local.cluster_private_endpoint : null }
output "cluster_ca_cert" { value = var.create_cluster ? base64decode(module.oke.cluster_ca_cert) : null }
output "control_plane_subnet_id" { value = var.create_vcn ? module.oke.control_plane_subnet_id : null }
output "control_plane_subnet_cidr" { value = var.create_vcn ? module.oke.control_plane_subnet_cidr : null }
output "control_plane_nsg_id" { value = var.create_vcn ? module.oke.control_plane_nsg_id : null }
output "int_lb_subnet_id" { value = var.create_vcn ? module.oke.int_lb_subnet_id : null }
output "int_lb_subnet_cidr" { value = var.create_vcn ? module.oke.int_lb_subnet_cidr : null }
output "int_lb_nsg_id" { value = var.create_vcn ? module.oke.int_lb_nsg_id : null }
output "pub_lb_subnet_id" { value = var.create_vcn ? module.oke.pub_lb_subnet_id : null }
output "pub_lb_subnet_cidr" { value = var.create_vcn ? module.oke.pub_lb_subnet_cidr : null }
output "pub_lb_nsg_id" { value = var.create_vcn ? module.oke.pub_lb_nsg_id : null }
output "pod_subnet_id" { value = var.create_vcn ? module.oke.pod_subnet_id : null }
output "pod_subnet_cidr" { value = var.create_vcn ? module.oke.pod_subnet_cidr : null }
output "pod_nsg_id" { value = var.create_vcn ? module.oke.pod_nsg_id : null }

# Workers
output "worker_subnet_id" { value = var.create_vcn ? module.oke.worker_subnet_id : null }
output "worker_nsg_id" { value = var.create_vcn ? module.oke.worker_nsg_id : null }
output "worker_subnet_cidr" { value = var.create_vcn ? module.oke.worker_subnet_cidr : null }
output "worker_ops_pool_id" { value = var.create_cluster ? lookup(module.oke.worker_pool_ids, "oke-system", null) : null }
output "worker_cpu_pool_id" { value = var.create_cluster ? lookup(module.oke.worker_pool_ids, "oke-cpu", null) : null }
output "worker_gpu_pool_id" { value = var.create_cluster ? lookup(module.oke.worker_pool_ids, "oke-gpu", null) : null }
output "worker_rdma_pool_id" { value = var.create_cluster ? lookup(module.oke.worker_pool_ids, "oke-rdma", null) : null }

# Monitoring

output "grafana_fetch_endpoint_command" {
  value = var.create_cluster ? (
    alltrue([var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public"]) ? 
      format("kubectl get ingress -n %v -l app.kubernetes.io/instance=kube-prometheus-stack -o jsonpath='{.items[0].spec.rules[0].host}'", var.monitoring_namespace) : 
      format("kubectl get svc -n %v -l app.kubernetes.io/instance=kube-prometheus-stack,app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'", var.monitoring_namespace) 
  ) : "N/A"
}

output "grafana_url" {
  value = alltrue([var.create_cluster, var.install_node_problem_detector_kube_prometheus_stack]) ? (
    var.preferred_kubernetes_services == "public" ?
    format("https://grafana.%s.%s", try(data.kubernetes_service.nginx_lb[0].status[0].load_balancer[0].ingress[0].ip, try(data.oci_load_balancer_load_balancers.lbs[0].load_balancers[0].ip_addresses[0], "N/A")), var.wildcard_dns_domain):
    format("http://%s", try(data.kubernetes_service.grafana_internal_ip[0].status[0].load_balancer[0].ingress[0].ip, try(data.oci_load_balancer_load_balancers.lbs[0].load_balancers[0].ip_addresses[0], try(data.oci_load_balancer_load_balancers.internal_lbs[0].load_balancers[0].ip_addresses[0], "N/A"))))
  ) : "N/A"
}

output "grafana_admin_password" {
  value = var.create_cluster ? nonsensitive(random_password.grafana_admin_password[0].result) : null
}

output "prom_server_port_forward" {
  value = var.create_cluster ? format("kubectl port-forward -n %v svc/kube-prometheus-stack-prometheus 9090:9090", var.monitoring_namespace) : null
}

output "grafana_port_forward" {
  value = var.create_cluster ? format("kubectl port-forward -n %v svc/kube-prometheus-stack-grafana 3000:80", var.monitoring_namespace) : null
}

output "access_k8s_public_endpoint" {
  value = alltrue([var.create_cluster, var.control_plane_is_public]) ? format("oci ce cluster create-kubeconfig --cluster-id %v --file $HOME/.kube/config --region %v --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT", module.oke.cluster_id, var.region) : "N/A"
}

output "access_k8s_private_endpoint" {
  value = var.create_cluster ? format("oci ce cluster create-kubeconfig --cluster-id %v --file $HOME/.kube/config --region %v --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT", module.oke.cluster_id, var.region) : null
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
