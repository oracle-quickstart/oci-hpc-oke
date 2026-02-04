# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  operator_helm_values_path = coalesce(var.operator_helm_values_path, "/home/${var.operator_user}/tf-helm-values")
  operator_helm_charts_path = coalesce(var.operator_helm_charts_path, "/home/${var.operator_user}/tf-helm-charts")
  operator_helm_chart_path  = "${local.operator_helm_charts_path}/${var.namespace}-${var.deployment_name}-${basename(var.helm_chart_path)}"

  helm_values_override_user_file     = "${var.namespace}-${var.deployment_name}-user-values-override.yaml"
  helm_values_override_template_file = "${var.namespace}-${var.deployment_name}-template-values-override.yaml"

  operator_helm_values_override_user_file_path     = join("/", [local.operator_helm_values_path, local.helm_values_override_user_file])
  operator_helm_values_override_template_file_path = join("/", [local.operator_helm_values_path, local.helm_values_override_template_file])
}

resource "null_resource" "copy_chart_top_operator" {
  count = var.helm_chart_path != "" ? 1 : 0

  triggers = {
    helm_chart_path = var.helm_chart_path
  }

  connection {
    bastion_host        = var.bastion_host
    bastion_user        = var.bastion_user
    bastion_private_key = var.ssh_private_key
    host                = var.operator_host
    user                = var.operator_user
    private_key         = var.ssh_private_key
    timeout             = "40m"
    type                = "ssh"
  }

  provisioner "remote-exec" {
    inline = [
      "rm -rf ${local.operator_helm_chart_path}",
      "mkdir -p ${local.operator_helm_charts_path}"
    ]
  }

  provisioner "file" {
    source      = var.helm_chart_path
    destination = local.operator_helm_chart_path
  }
}

resource "null_resource" "helm_deployment_via_operator" {

  triggers = {
    manifest_md5    = try(md5("${var.helm_template_values_override}-${var.helm_user_values_override}"), null)
    deployment_name = var.deployment_name
    namespace       = var.namespace
    bastion_host    = var.bastion_host
    bastion_user    = var.bastion_user
    ssh_private_key = var.ssh_private_key
    operator_host   = var.operator_host
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
    inline = ["mkdir -p ${local.operator_helm_values_path}"]
  }

  provisioner "file" {
    content     = var.helm_template_values_override
    destination = local.operator_helm_values_override_template_file_path
  }

  provisioner "file" {
    content     = var.helm_user_values_override
    destination = local.operator_helm_values_override_user_file_path
  }

  provisioner "remote-exec" {
    inline = compact(concat(
      [
        "export PATH=$PATH:/usr/local/bin:/home/${var.operator_user}/bin",
        "export OCI_CLI_AUTH=instance_principal",
        "echo 'Checking for kubeconfig...'",       
        "for i in $(seq 1 30); do if [ -f ~/.kube/config ] && timeout 10 kubectl cluster-info >/dev/null 2>&1; then echo 'Kubeconfig is ready!'; break; else echo \"Waiting for kubeconfig... ($i/30)\"; sleep 10; fi; done",
        "if ! kubectl cluster-info >/dev/null 2>&1; then echo 'ERROR: Kubeconfig not available after 5 minutes!'; exit 1; fi",
        "echo 'Checking for helm installation...'",
        "for i in $(seq 1 30); do if which helm >/dev/null 2>&1; then echo 'Helm found!'; break; else echo \"Waiting for helm... ($i/30)\"; sleep 10; fi; done",
        "if ! which helm >/dev/null 2>&1; then echo 'ERROR: Helm not found after 5 minutes!'; exit 1; fi"
      ],
      var.pre_deployment_commands,
      [
        "if [ -s \"${local.operator_helm_values_override_user_file_path}\" ]; then",
        join(" ", compact(concat([
          "helm upgrade --install ${var.deployment_name}",
          var.helm_chart_path != "" ? local.operator_helm_chart_path : "%{if var.helm_repository_url != "" && lower(substr(var.helm_repository_url, 0, 4)) == "http"}${var.helm_chart_name} --repo ${var.helm_repository_url}%{else}${var.helm_repository_url}/${var.helm_chart_name}%{endif}",
          var.helm_chart_path != "" ? "%{if var.helm_chart_version != ""}--version ${var.helm_chart_version}%{endif}": "",
          "--namespace ${var.namespace} --create-namespace",
          "-f ${local.operator_helm_values_override_template_file_path}",
          "-f ${local.operator_helm_values_override_user_file_path}"
        ], var.deployment_extra_args))),
        "else",
        join(" ", compact(concat([
          "helm upgrade --install ${var.deployment_name}",
          var.helm_chart_path != "" ? local.operator_helm_chart_path : "%{if var.helm_repository_url != "" && lower(substr(var.helm_repository_url, 0, 4)) == "http"}${var.helm_chart_name} --repo ${var.helm_repository_url}%{else}${var.helm_repository_url}/${var.helm_chart_name}%{endif}",
          var.helm_chart_path != "" ? "%{if var.helm_chart_version != ""}--version ${var.helm_chart_version}%{endif}" : "",
          "--namespace ${var.namespace} --create-namespace",
          "-f ${local.operator_helm_values_override_template_file_path}"
        ], var.deployment_extra_args))),
        "fi"
      ],
      var.post_deployment_commands
    ))

  }

  provisioner "remote-exec" {
    when = destroy
    inline = [
      "export PATH=$PATH:/home/${self.triggers.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
    "helm uninstall ${self.triggers.deployment_name} --namespace ${self.triggers.namespace} --wait"]
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

  depends_on = [null_resource.copy_chart_top_operator]
}
