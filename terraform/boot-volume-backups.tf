# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

# Without a compartment_id, this lists only the Oracle-defined policies.
data "oci_core_volume_backup_policies" "bastion" {
  count = var.create_bastion && var.bastion_boot_volume_backup ? 1 : 0

  filter {
    name   = "display_name"
    values = [lower(var.bastion_boot_volume_backup_policy)]
  }
}

# The OKE module outputs only the instance ID, so read the boot volume ID here.
data "oci_core_instance" "bastion" {
  count = var.create_bastion && var.bastion_boot_volume_backup ? 1 : 0

  instance_id = module.oke.bastion_id
}

resource "oci_core_volume_backup_policy_assignment" "bastion_boot_volume" {
  count = var.create_bastion && var.bastion_boot_volume_backup ? 1 : 0

  asset_id  = data.oci_core_instance.bastion[0].boot_volume_id
  policy_id = data.oci_core_volume_backup_policies.bastion[0].volume_backup_policies[0].id
}

data "oci_core_volume_backup_policies" "operator" {
  count = var.create_operator && var.operator_boot_volume_backup ? 1 : 0

  filter {
    name   = "display_name"
    values = [lower(var.operator_boot_volume_backup_policy)]
  }
}

data "oci_core_instance" "operator" {
  count = var.create_operator && var.operator_boot_volume_backup ? 1 : 0

  instance_id = module.oke.operator_id
}

resource "oci_core_volume_backup_policy_assignment" "operator_boot_volume" {
  count = var.create_operator && var.operator_boot_volume_backup ? 1 : 0

  asset_id  = data.oci_core_instance.operator[0].boot_volume_id
  policy_id = data.oci_core_volume_backup_policies.operator[0].volume_backup_policies[0].id
}
