# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

# Drain all Kueue CRs before the chart is uninstalled so the CRD cascade does not
# hang on resource-in-use finalizers. Operator path only (drains over
# bastion->operator SSH); ORM/local use wait = false on helm_release.kueue.
resource "null_resource" "kueue_predestroy_drain_via_operator" {
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
