# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

module "nginx" {
  count  = alltrue([var.install_monitoring, local.deploy_from_operator, var.install_node_problem_detector_kube_prometheus_stack, var.preferred_kubernetes_services == "public"]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "ingress-nginx"
  helm_chart_name     = "ingress-nginx"
  namespace           = "nginx"
  helm_repository_url = "https://kubernetes.github.io/ingress-nginx"

  pre_deployment_commands = [
    "export PATH=$PATH:/home/${var.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal"
  ]
  post_deployment_commands = flatten([
    "cat <<'EOF' | kubectl apply -f -",
    split("\n", file("${path.root}/files/cert-manager/cluster-issuer.yaml")),
    "EOF",
    "sleep 60" #wait for the LB to be provisioned
  ])
  deployment_extra_args = ["--wait"]

  helm_template_values_override = templatefile(
    "${path.root}/files/nginx-ingress/values.yaml.tpl",
    {
      min_bw    = 100,
      max_bw    = 100,
      lb_nsg_id = module.oke.pub_lb_nsg_id,
      state_id  = local.state_id
    }
  )
  helm_user_values_override = ""

  depends_on = [module.oke]
}


module "kube_prometheus_stack" {
  count  = alltrue([var.install_monitoring, local.deploy_from_operator, var.install_node_problem_detector_kube_prometheus_stack]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "kube-prometheus-stack"
  helm_chart_name     = "kube-prometheus-stack"
  namespace           = var.monitoring_namespace
  helm_repository_url = "https://prometheus-community.github.io/helm-charts"
  helm_chart_version  = var.prometheus_stack_chart_version

  pre_deployment_commands = [
    "export PATH=$PATH:/home/${var.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal",
    "export INGRESS_IP=$(kubectl get svc -A -l app.kubernetes.io/name=ingress-nginx  -o json | jq -r '.items[] | select(.spec.type == \"LoadBalancer\") | .status.loadBalancer.ingress[].ip')"
  ]

  deployment_extra_args = flatten([
    [
      "--force",
      "--dependency-update",
      "--history-max 1",
      "--wait",
    ],
    var.preferred_kubernetes_services == "public" ? [
      "--set grafana.ingress.enabled=true",
      "--set grafana.ingress.ingressClassName=nginx",
      "--set grafana.ingress.annotations.'cert-manager\\.io\\/cluster-issuer'=le-clusterissuer",
      "--set grafana.ingress.hosts[0]=grafana.$${INGRESS_IP}.sslip.io",
      "--set grafana.ingress.tls[0].hosts[0]=grafana.$${INGRESS_IP}.sslip.io",
      "--set grafana.ingress.tls[0].secretName=grafana-tls"
    ] :
    [
      "--set grafana.service.type=LoadBalancer",
      "--set-string grafana.service.annotations.'oci\\.oraclecloud\\.com\\/load-balancer-type'=lb",
      "--set-string grafana.service.annotations.'service\\.beta\\.kubernetes\\.io\\/oci-load-balancer-internal'=true",
      "--set-string grafana.service.annotations.'service\\.beta\\.kubernetes\\.io\\/oci-load-balancer-shape'=flexible",
      "--set-string grafana.service.annotations.'service\\.beta\\.kubernetes\\.io\\/oci-load-balancer-shape-flex-min'=100",
      "--set-string grafana.service.annotations.'service\\.beta\\.kubernetes\\.io\\/oci-load-balancer-shape-flex-max'=100",
      "--set-string grafana.service.annotations.'service\\.beta\\.kubernetes\\.io\\/oci-load-balancer-security-list-management-mode'=None",
      format("--set-string grafana.service.annotations.'oci\\.oraclecloud\\.com\\/oci-network-security-groups'=%s", module.oke.int_lb_nsg_id)
    ]
  ])

  post_deployment_commands = []

  helm_template_values_override = templatefile("./files/kube-prometheus/values.yaml.tftpl", { preferred_kubernetes_services = var.preferred_kubernetes_services})

  helm_user_values_override = yamlencode(
    {
      grafana = merge(
        {
          adminPassword = random_password.grafana_admin_password.result
        },
        var.preferred_kubernetes_services == "internal" ?
        { 
          service = {
            annotations = {
              "oci.oraclecloud.com/initial-freeform-tags-override": jsonencode({"state_id"=local.state_id, "application": "grafana"})
            }
          }
        } : {})
      }
  )
  depends_on = [module.nginx]
}


module "node_problem_detector" {
  count  = alltrue([var.install_monitoring, local.deploy_from_operator, var.install_node_problem_detector_kube_prometheus_stack]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "gpu-rdma-node-problem-detector"
  helm_chart_name     = "node-problem-detector"
  namespace           = var.monitoring_namespace
  helm_repository_url = "oci://ghcr.io/deliveryhero/helm-charts"
  helm_chart_version  = var.node_problem_detector_chart_version

  pre_deployment_commands = [
    "export PATH=$PATH:/home/${var.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal"
  ]
  deployment_extra_args    = ["--force", "--dependency-update", "--history-max 1"]
  post_deployment_commands = []

  helm_template_values_override = file("${path.root}/files/node-problem-detector/values.yaml")
  helm_user_values_override     = ""

  depends_on = [module.kube_prometheus_stack]
}


module "nvidia_dcgm_exporter" {
  count  = alltrue([var.install_monitoring, local.deploy_from_operator, var.install_node_problem_detector_kube_prometheus_stack, var.install_nvidia_dcgm_exporter]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name    = "dcgm-exporter"
  namespace          = var.monitoring_namespace
  helm_chart_path    = "${path.root}/files/nvidia-dcgm-exporter"
  helm_chart_version = var.dcgm_exporter_chart_version

  pre_deployment_commands = [
    "export PATH=$PATH:/home/${var.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal"
  ]
  deployment_extra_args    = ["--force", "--dependency-update", "--history-max 1"]
  post_deployment_commands = []

  helm_template_values_override = file("${path.root}/files/nvidia-dcgm-exporter/oke-values.yaml")
  helm_user_values_override     = ""

  depends_on = [module.kube_prometheus_stack]
}


module "amd_device_metrics_exporter" {
  count  = alltrue([var.install_monitoring, local.deploy_from_operator, var.install_node_problem_detector_kube_prometheus_stack, var.install_amd_device_metrics_exporter && (var.worker_rdma_shape == "BM.GPU.MI300X.8" || var.worker_gpu_shape == "BM.GPU.MI300X.8")]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "amd-device-metrics-exporter"
  helm_chart_name     = "device-metrics-exporter-charts"
  namespace           = var.monitoring_namespace
  helm_repository_url = "https://rocm.github.io/device-metrics-exporter"
  helm_chart_version  = var.amd_device_metrics_exporter_chart_version

  pre_deployment_commands = [
    "export PATH=$PATH:/home/${var.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal"
  ]
  deployment_extra_args    = ["--force", "--dependency-update", "--history-max 1"]
  post_deployment_commands = []

  helm_template_values_override = file("${path.root}/files/amd-device-metrics-exporter/values.yaml")
  helm_user_values_override     = ""

  depends_on = [module.kube_prometheus_stack]
}

module "lustre_client" {
  count  = alltrue([local.deploy_from_operator, var.create_lustre, var.install_lustre_client]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "lustre-client-installer"
  helm_chart_name     = "lustre-client-installer"
  namespace           = "kube-system"
  helm_repository_url = "https://oci-hpc.github.io/oke-lustre-client/"
  helm_chart_version  = var.lustre_client_helm_chart_version

  pre_deployment_commands = [
    "export PATH=$PATH:/home/${var.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal"
  ]
  deployment_extra_args = ["--force", "--dependency-update", "--history-max 1"]
  post_deployment_commands = var.create_lustre_pv ? flatten([
    "cat <<'EOF' | kubectl apply -f -",
    split("\n", templatefile(
      "${path.root}/files/lustre/lustre-pv.yaml.tpl",
      {
        lustre_storage_size = floor(var.lustre_size_in_tb),
        lustre_ip           = one(oci_lustre_file_storage_lustre_file_system.lustre.*.management_service_address),
        lustre_fs_name      = var.lustre_file_system_name,
      }
    )),
    "EOF"
  ]) : []

  helm_template_values_override = ""
  helm_user_values_override     = ""

  depends_on = [module.oke]
}


module "oke-ons-webhook" {
  count  = alltrue([var.install_monitoring, local.deploy_from_operator, var.install_node_problem_detector_kube_prometheus_stack, var.setup_alerting]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name    = "oke-ons-webhook"
  namespace          = var.monitoring_namespace
  helm_chart_path    = "${path.root}/files/oke-ons-webhook"
  helm_chart_version = var.oke_ons_webhook_chart_version

  pre_deployment_commands = [
    "export PATH=$PATH:/home/${var.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal"
  ]
  deployment_extra_args    = ["--force", "--dependency-update", "--history-max 1"]
  post_deployment_commands = []

  helm_template_values_override = ""
  helm_user_values_override     = yamlencode({
    deploy = {
      env = {
        ONS_TOPIC_OCID           = try(oci_ons_notification_topic.grafana_alerts[0].id, "")
        GRAFANA_INITIAL_PASSWORD = base64encode(random_password.grafana_admin_password.result)
        GRAFANA_SERVICE_URL      = "http://kube-prometheus-stack-grafana"
      }
    }
  })

  depends_on = [module.kube_prometheus_stack]
}