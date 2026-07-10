# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "null_resource" "nccl_rccl_configmap" {
  # Slurm-namespace copies follow the Slinky deploy gate: with a public control
  # plane the cluster deploys via the provider while Slinky still deploys via
  # the operator, and only this path ensures the Slurm namespace exists.
  for_each = local.deploy_nccl_rccl_param_configmap ? { for k, cm in local.nccl_rccl_configmaps : k => cm if(cm.namespace == "default" ? local.deploy_from_operator : local.slinky_deploy_from_operator) } : {}

  triggers = {
    manifest_md5    = md5(local.nccl_rccl_configmap_manifests[each.key])
    manifest_path   = "/tmp/${each.value.name}-${each.value.namespace}.yaml"
    configmap_name  = each.value.name
    namespace       = each.value.namespace
    bastion_host    = module.oke.bastion_public_ip
    bastion_user    = local.bastion_user
    ssh_private_key = tls_private_key.stack_key.private_key_openssh
    operator_host   = module.oke.operator_private_ip
    operator_user   = local.operator_user
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

  provisioner "file" {
    content     = local.nccl_rccl_configmap_manifests[each.key]
    destination = self.triggers.manifest_path
  }

  provisioner "remote-exec" {
    inline = [
      "export PATH=$PATH:/usr/local/bin:/home/${local.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "export PYTHONWARNINGS=\"ignore:the 'strict' parameter::urllib3.poolmanager\"",
      "for i in $(seq 1 30); do if [ -f ~/.kube/config ] && timeout 10 kubectl cluster-info >/dev/null 2>&1; then echo 'Kubeconfig is ready!'; break; else echo \"Waiting for kubeconfig... ($i/30)\"; sleep 10; fi; done",
      "if ! timeout 30 kubectl cluster-info >/dev/null 2>&1; then echo 'ERROR: Kubeconfig not available after 5 minutes!'; exit 1; fi",
      "kubectl create namespace ${each.value.namespace} --dry-run=client -o yaml | kubectl apply -f -",
      "kubectl apply --server-side -f ${self.triggers.manifest_path}",
      "rm -f ${self.triggers.manifest_path}"
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [
      "export PATH=$PATH:/usr/local/bin:/home/${self.triggers.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "export PYTHONWARNINGS=\"ignore:the 'strict' parameter::urllib3.poolmanager\"",
      "kubectl delete configmap ${self.triggers.configmap_name} --namespace ${self.triggers.namespace} --ignore-not-found"
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

  depends_on = [module.oke]
}
