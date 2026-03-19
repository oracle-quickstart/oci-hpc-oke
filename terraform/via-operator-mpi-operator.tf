# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "null_resource" "mpi_operator" {
  count = alltrue([var.install_mpi_operator, local.deploy_from_operator]) ? 1 : 0

  triggers = {
    manifest_md5    = md5(file("${path.module}/files/mpi-operator/mpi-operator.yaml"))
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

  provisioner "file" {
    source      = "${path.module}/files/mpi-operator/mpi-operator.yaml"
    destination = "/tmp/mpi-operator.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "export PATH=$PATH:/usr/local/bin:/home/${var.operator_user}/bin",
      "for i in $(seq 1 30); do if [ -f ~/.kube/config ] && timeout 10 kubectl cluster-info >/dev/null 2>&1; then echo 'Kubeconfig is ready!'; break; else echo \"Waiting for kubeconfig... ($i/30)\"; sleep 10; fi; done",
      "if ! kubectl cluster-info >/dev/null 2>&1; then echo 'ERROR: Kubeconfig not available after 5 minutes!'; exit 1; fi",
      "kubectl apply --server-side -f /tmp/mpi-operator.yaml",
      "rm -f /tmp/mpi-operator.yaml"
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [
      "export PATH=$PATH:/usr/local/bin:/home/${self.triggers.operator_user}/bin",
      "kubectl delete namespace mpi-operator --ignore-not-found --wait=false"
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
