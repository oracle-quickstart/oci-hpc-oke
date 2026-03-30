# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "null_resource" "lustre_pv_via_operator" {
  count = alltrue([var.create_lustre, var.create_lustre_pv, local.deploy_from_operator]) ? 1 : 0

  triggers = {
    lustre_ip       = one(oci_lustre_file_storage_lustre_file_system.lustre.*.management_service_address)
    lustre_fs_name  = var.lustre_file_system_name
    lustre_size     = floor(var.lustre_size_in_tb)
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
    inline = [
      "export PATH=$PATH:/usr/local/bin:/home/${var.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "for i in $(seq 1 30); do if [ -f ~/.kube/config ] && timeout 10 kubectl cluster-info >/dev/null 2>&1; then echo 'Kubeconfig is ready!'; break; else echo \"Waiting for kubeconfig... ($i/30)\"; sleep 10; fi; done",
      "if ! timeout 30 kubectl cluster-info >/dev/null 2>&1; then echo 'ERROR: Kubeconfig not available after 5 minutes!'; exit 1; fi",
      "printf 'apiVersion: v1\\nkind: PersistentVolume\\nmetadata:\\n  name: lustre-pv\\nspec:\\n  capacity:\\n    storage: %sTi\\n  volumeMode: Filesystem\\n  accessModes:\\n  - ReadWriteMany\\n  persistentVolumeReclaimPolicy: Retain\\n  csi:\\n    driver: lustre.csi.oraclecloud.com\\n    volumeHandle: \"%s@tcp:/%s\"\\n    fsType: lustre\\n    volumeAttributes:\\n      setupLnet: \"true\"\\n' '${self.triggers.lustre_size}' '${self.triggers.lustre_ip}' '${self.triggers.lustre_fs_name}' | kubectl apply -f -",
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [
      "export PATH=$PATH:/usr/local/bin:/home/${self.triggers.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "kubectl delete pv lustre-pv --ignore-not-found --wait=true --timeout=120s",
    ]
    on_failure = continue
  }

  lifecycle {
    ignore_changes = [
      triggers["bastion_host"],
      triggers["bastion_user"],
      triggers["ssh_private_key"],
      triggers["operator_host"],
      triggers["operator_user"],
    ]
  }

  depends_on = [module.oke, oci_lustre_file_storage_lustre_file_system.lustre]
}
