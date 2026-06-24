# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

# Kueue's Helm chart templates its CRDs, so "helm uninstall" deletes them and
# cascade-deletes every CR instance. An instance still carrying the
# kueue.x-k8s.io/resource-in-use finalizer cannot be cleared once the controller
# is gone, so the CRD deletion blocks and the uninstall times out
# ("context deadline exceeded"), failing the destroy. This drains all Kueue CRs
# (including ad-hoc ones Terraform does not manage) before the chart is
# uninstalled, ordered before the operator-path module.kueue.
#
# Operator path only: it drains over the bastion->operator SSH path. The ORM
# runner has no SSH route to the operator (it reaches the cluster solely through
# the ORM private endpoint), so for deploy_from_local/deploy_from_orm the
# equivalent protection is wait = false on helm_release.kueue in
# via-provider-kueue.tf instead.
resource "null_resource" "kueue_predestroy_drain" {
  count = alltrue([var.install_kueue, local.deploy_from_operator]) ? 1 : 0

  triggers = {
    bastion_host    = module.oke.bastion_public_ip
    bastion_user    = local.bastion_user
    operator_host   = module.oke.operator_private_ip
    operator_user   = local.operator_user
    ssh_private_key = tls_private_key.stack_key.private_key_openssh
    drain_script    = file("${path.module}/files/kueue/predestroy-drain.sh")
  }

  connection {
    type                = "ssh"
    bastion_host        = self.triggers.bastion_host
    bastion_user        = self.triggers.bastion_user
    bastion_private_key = self.triggers.ssh_private_key
    host                = self.triggers.operator_host
    user                = self.triggers.operator_user
    private_key         = self.triggers.ssh_private_key
    timeout             = "10m"
  }

  provisioner "remote-exec" {
    when       = destroy
    on_failure = continue
    inline = [
      "export PATH=$PATH:/home/${self.triggers.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "export PYTHONWARNINGS=\"ignore:the 'strict' parameter::urllib3.poolmanager\"",
      "cat > /tmp/kueue-predestroy-drain.sh <<'KUEUE_DRAIN_EOF'\n${self.triggers.drain_script}\nKUEUE_DRAIN_EOF",
      "bash /tmp/kueue-predestroy-drain.sh",
    ]
  }

  lifecycle {
    ignore_changes = [
      triggers["bastion_host"],
      triggers["bastion_user"],
      triggers["operator_host"],
      triggers["operator_user"],
      triggers["ssh_private_key"],
      triggers["drain_script"],
    ]
  }

  depends_on = [module.kueue]
}
