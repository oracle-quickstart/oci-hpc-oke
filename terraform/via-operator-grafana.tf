# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  kustomize_configmap_generator = {
    apiVersion = "kustomize.config.k8s.io/v1beta1"
    kind       = "Kustomization"
    configMapGenerator = concat(
      [for cdk, cdv in local.grafana_common_dashboards :
        {
          name      = "dashboard-${trimsuffix(cdk, ".json")}",
          namespace = var.monitoring_namespace,
          files     = [join("/", ["/home/${var.operator_user}/grafana/dashboards/common", cdk])]
          options = {
            labels = {
              grafana_dashboard = "1"
            }
            annotations = {
              grafana_dashboard_folder = "Kubernetes"
            }
            disableNameSuffixHash = true
          }
        }
      ],
      (can(regex("GPU", coalesce(var.worker_rdma_shape, ""))) && !contains(["BM.GPU.MI300X.8", "BM.GPU.MI355X-v1.8", "BM.GPU.MI355X.8"], var.worker_rdma_shape)) ||
      (can(regex("GPU", coalesce(var.worker_gpu_shape, ""))) && !contains(["BM.GPU.MI300X.8", "BM.GPU.MI355X-v1.8", "BM.GPU.MI355X.8"], var.worker_gpu_shape)) ?
      [for cdk, cdv in local.grafana_nvidia_dashboards :
        {
          name      = "dashboard-${trimsuffix(cdk, ".json")}",
          namespace = var.monitoring_namespace,
          files     = [join("/", ["/home/${var.operator_user}/grafana/dashboards/nvidia", cdk])]
          options = {
            labels = {
              grafana_dashboard = "1"
            }
            annotations = {
              grafana_dashboard_folder = "GPU Nodes"
            }
            disableNameSuffixHash = true
          }
        }
      ] : [],
      contains(["BM.GPU.MI300X.8", "BM.GPU.MI355X-v1.8", "BM.GPU.MI355X.8"], var.worker_rdma_shape) ||
      contains(["BM.GPU.MI300X.8", "BM.GPU.MI355X-v1.8", "BM.GPU.MI355X.8"], var.worker_gpu_shape) ?
      [for cdk, cdv in local.grafana_amd_dashboards :
        {
          name      = "dashboard-${trimsuffix(cdk, ".json")}",
          namespace = var.monitoring_namespace,
          files     = [join("/", ["/home/${var.operator_user}/grafana/dashboards/amd", cdk])]
          options = {
            labels = {
              grafana_dashboard = "1"
            }
            annotations = {
              grafana_dashboard_folder = "GPU Nodes"
            }
            disableNameSuffixHash = true
          }
        }
      ] : [],
      [for cak, cav in local.grafana_alerts :
        {
          name      = "alert-${trimsuffix(cak, ".yaml")}",
          namespace = var.monitoring_namespace,
          files     = [join("/", ["/home/${var.operator_user}/grafana/alerts", cak])]
          options = {
            labels = {
              grafana_alert = "1"
            }
            disableNameSuffixHash = true
          }
        }
      ],
    )
  }
}

resource "null_resource" "deploy_grafana_dashboards_and_alerts_from_operator" {
  count = alltrue([var.install_monitoring, var.install_node_problem_detector_kube_prometheus_stack, local.deploy_from_operator]) ? 1 : 0

  triggers = {
    manifest_md5    = sha256(join(".", [for entry in sort(flatten([local.grafana_common_dashboard_files_path, local.grafana_amd_dashboard_files_path, local.grafana_nvidia_dashboard_files_path, local.grafana_alert_files_path])) : filemd5(entry)]))
    namespace       = var.monitoring_namespace
    bastion_host    = module.oke.bastion_public_ip
    bastion_user    = var.bastion_user
    ssh_private_key = tls_private_key.stack_key.private_key_openssh
    operator_host   = module.oke.operator_private_ip
    operator_user   = var.operator_user
  }


  connection {
    bastion_host        = self.triggers.bastion_host
    bastion_user        = self.triggers.bastion_user
    bastion_private_key = self.triggers.ssh_private_key
    host                = self.triggers.operator_host
    user                = self.triggers.operator_user
    private_key         = self.triggers.ssh_private_key
    timeout             = "40m"
    type                = "ssh"
  }

  provisioner "remote-exec" {
    inline = compact(flatten([
      "mkdir -p /home/${self.triggers.operator_user}/grafana/dashboards/common",
      "mkdir -p /home/${self.triggers.operator_user}/grafana/dashboards/amd",
      "mkdir -p /home/${self.triggers.operator_user}/grafana/dashboards/nvidia",
      "mkdir -p /home/${self.triggers.operator_user}/grafana/alerts",
    ]))
  }

  provisioner "file" {
    source      = "${local.grafana_common_dashboard_dir}/"
    destination = "/home/${self.triggers.operator_user}/grafana/dashboards/common"
  }

  provisioner "file" {
    source      = "${local.grafana_amd_dashboard_dir}/"
    destination = "/home/${self.triggers.operator_user}/grafana/dashboards/amd"
  }

  provisioner "file" {
    source      = "${local.grafana_nvidia_dashboard_dir}/"
    destination = "/home/${self.triggers.operator_user}/grafana/dashboards/nvidia"
  }

  provisioner "file" {
    source      = "${local.grafana_alert_dir}/"
    destination = "/home/${self.triggers.operator_user}/grafana/alerts"
  }

  provisioner "file" {
    content     = yamlencode(local.kustomize_configmap_generator)
    destination = "/home/${self.triggers.operator_user}/grafana/kustomization.yaml"
  }

  provisioner "remote-exec" {
    inline = compact(flatten([
      "export PATH=$PATH:/home/${self.triggers.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "cd /home/${self.triggers.operator_user}/grafana/",
      "kubectl apply -k .",
    ]))
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [
      "export PATH=$PATH:/home/${self.triggers.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "cd /home/${self.triggers.operator_user}/grafana/",
      "kubectl delete -k ."
    ]
    on_failure = continue
  }

  lifecycle {
    ignore_changes = [
      triggers["bastion_host"],
      triggers["bastion_user"],
      triggers["ssh_private_key"],
      triggers["operator_host"],
      triggers["operator_user"]
    ]
  }

  depends_on = [module.kube_prometheus_stack]
}