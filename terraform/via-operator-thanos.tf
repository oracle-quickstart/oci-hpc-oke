# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

module "thanos" {
  count  = alltrue([local.thanos_enabled, local.deploy_from_operator]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = local.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = local.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name = "thanos"
  namespace       = var.monitoring_namespace
  helm_chart_path = "${path.module}/files/thanos"

  deployment_extra_args = [
    "--history-max 1",
    "--wait",
  ]

  helm_template_values_override = local.thanos_chart_values
  helm_user_values_override     = ""

  depends_on = [module.oke, oci_objectstorage_bucket.thanos, time_sleep.wait_for_thanos_policy]
}

# Operator-path counterpart of thanos_predestroy_purge_via_orm (see there).
resource "null_resource" "thanos_predestroy_purge_via_operator" {
  count = alltrue([local.thanos_create_bucket, local.deploy_from_operator]) ? 1 : 0

  triggers = {
    bastion_host    = module.oke.bastion_public_ip
    bastion_user    = local.bastion_user
    operator_host   = module.oke.operator_private_ip
    operator_user   = local.operator_user
    ssh_private_key = tls_private_key.stack_key.private_key_openssh
    namespace       = var.monitoring_namespace
    bucket          = local.thanos_bucket_name
    region          = var.region
    purge_script    = file("${path.module}/files/thanos/predestroy-purge.sh")
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
      "cat > /tmp/thanos-predestroy-purge.sh <<'THANOS_PURGE_EOF'\n${self.triggers.purge_script}\nTHANOS_PURGE_EOF",
      "bash /tmp/thanos-predestroy-purge.sh '${self.triggers.namespace}' '${self.triggers.bucket}' '${self.triggers.region}'",
    ]
  }

  lifecycle {
    ignore_changes = [
      triggers["bastion_host"],
      triggers["bastion_user"],
      triggers["operator_host"],
      triggers["operator_user"],
      triggers["ssh_private_key"],
      triggers["purge_script"],
    ]
  }

  depends_on = [module.thanos, oci_objectstorage_bucket.thanos]
}
