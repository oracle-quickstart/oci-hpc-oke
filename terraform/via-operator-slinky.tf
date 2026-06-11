# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  slinky_workdir = "/home/${local.operator_user}/tf-slinky"

  slinky_openldap_prereqs_yaml = templatefile("${path.module}/files/slinky/openldap-prereqs.yaml.tftpl", {
    openldap_namespace         = var.slinky_openldap_namespace
    slurm_namespace            = var.slinky_slurm_namespace
    openldap_base_dn           = var.slinky_openldap_base_dn
    openldap_admin_password    = var.slinky_openldap_admin_password
    readonly_replica_dns_names = local.slinky_readonly_replica_dns_names
  })

  slinky_openldap_values_yaml = templatefile("${path.module}/files/slinky/openldap-values.yaml.tftpl", {
    openldap_domain            = var.slinky_openldap_domain
    openldap_base_dn           = var.slinky_openldap_base_dn
    openldap_dc                = local.slinky_openldap_dc
    openldap_admin_password    = var.slinky_openldap_admin_password
    openldap_config_password   = var.slinky_openldap_config_password
    openldap_primary_replicas  = var.slinky_openldap_primary_replicas
    openldap_readonly_replicas = var.slinky_openldap_readonly_replicas
    openldap_storage_size      = var.slinky_openldap_storage_size
    system_node_shape          = var.worker_ops_shape
  })

  slinky_home_pvc_yaml = templatefile("${path.module}/files/slinky/slurm-home-pvc.yaml.tftpl", {
    slurm_namespace = var.slinky_slurm_namespace
    home_pv_name    = var.slinky_home_pv_name
    home_pvc_size   = var.slinky_home_pvc_size
  })

  slinky_mariadb_yaml = templatefile("${path.module}/files/slinky/mariadb.yaml.tftpl", {
    slurm_namespace      = var.slinky_slurm_namespace
    mariadb_storage_size = var.slinky_mariadb_storage_size
  })

  slinky_slurm_values_yaml = templatefile("${path.module}/files/slinky/slurm-values.yaml.tftpl", {
    cluster_name                   = local.cluster_name
    identity_enabled               = var.slinky_identity_enabled
    home_enabled                   = var.slinky_home_enabled
    accounting_enabled             = var.slinky_accounting_enabled
    system_node_shape              = var.worker_ops_shape
    controller_image_repository    = var.slinky_controller_image_repository
    controller_image_tag           = var.slinky_controller_image_tag
    sssd_image_repository          = var.slinky_sssd_image_repository
    sssd_image_tag                 = var.slinky_sssd_image_tag
    login_image_repository         = var.slinky_login_image_repository
    login_image_tag                = var.slinky_login_image_tag
    gpu_autodetect                 = local.slinky_gpu_autodetect
    login_enabled                  = var.slinky_login_enabled
    login_root_ssh_authorized_keys = local.slinky_login_root_ssh_authorized_keys
    nodeset_name                   = var.slinky_nodeset_name
    worker_replicas                = local.slinky_worker_replicas
    worker_image_repository        = var.slinky_worker_image_repository
    worker_image_tag               = local.slinky_worker_image_tag
    gpu_resource                   = local.slinky_gpu_resource
    gpus_per_node                  = local.slinky_gpus_per_node
    mount_infiniband               = var.slinky_worker_mount_infiniband
    worker_ssh_enabled             = var.slinky_worker_ssh_enabled
    worker_host_network            = local.slinky_worker_host_network
    worker_sriov_enabled           = local.slinky_worker_sriov_enabled
    worker_rdma_resource           = var.slinky_worker_rdma_resource
    worker_rdma_vfs_per_node       = var.slinky_worker_rdma_vfs_per_node
    worker_rdma_networks           = local.slinky_worker_rdma_networks_annotation
    worker_slurmd_parameters       = local.slinky_worker_slurmd_parameters
    worker_numa_topology_enabled   = local.slinky_worker_numa_topology_enabled
    worker_features_yaml           = join("\n", [for feature in local.slinky_worker_features : "        - ${feature}"])
    worker_shape                   = local.slinky_worker_shape
  })

  slinky_deploy_script = templatefile("${path.module}/files/slinky/deploy-slinky-full-suite.sh.tftpl", {
    operator_user                 = local.operator_user
    identity_enabled              = var.slinky_identity_enabled
    home_enabled                  = var.slinky_home_enabled
    accounting_enabled            = var.slinky_accounting_enabled
    install_slurm_cluster         = var.slinky_install_slurm_cluster
    login_enabled                 = var.slinky_login_enabled
    slinky_operator_namespace     = var.slinky_operator_namespace
    slurm_namespace               = var.slinky_slurm_namespace
    openldap_namespace            = var.slinky_openldap_namespace
    openldap_readonly_replicas    = var.slinky_openldap_readonly_replicas
    openldap_admin_password       = var.slinky_openldap_admin_password
    openldap_config_password      = var.slinky_openldap_config_password
    openldap_base_dn              = var.slinky_openldap_base_dn
    openldap_dc                   = local.slinky_openldap_dc
    nodeset_name                  = var.slinky_nodeset_name
    cert_manager_chart_version    = var.cert_manager_chart_version
    openldap_chart_version        = var.slinky_openldap_chart_version
    slinky_operator_chart_version = var.slinky_operator_chart_version
    slinky_slurm_chart_version    = var.slinky_slurm_chart_version
  })

  slinky_manifest_bundle_md5 = nonsensitive(md5(join("\n---\n", [
    local.slinky_openldap_prereqs_yaml,
    local.slinky_openldap_values_yaml,
    local.slinky_home_pvc_yaml,
    local.slinky_mariadb_yaml,
    local.slinky_slurm_values_yaml,
    local.slinky_deploy_script,
    var.slinky_operator_values_override,
    var.slinky_slurm_values_override,
  ])))
}

resource "null_resource" "slinky_full_suite_via_operator" {
  count = local.slinky_deploy_from_operator ? 1 : 0

  triggers = {
    manifest_md5       = local.slinky_manifest_bundle_md5
    bastion_host       = module.oke.bastion_public_ip
    bastion_user       = local.bastion_user
    ssh_private_key    = tls_private_key.stack_key.private_key_openssh
    operator_host      = module.oke.operator_private_ip
    operator_user      = local.operator_user
    slurm_namespace    = var.slinky_slurm_namespace
    slinky_namespace   = var.slinky_operator_namespace
    openldap_namespace = var.slinky_openldap_namespace
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
      "mkdir -p ${local.slinky_workdir}",
      "chmod 700 ${local.slinky_workdir}",
    ]
  }

  provisioner "file" {
    content     = local.slinky_openldap_prereqs_yaml
    destination = "${local.slinky_workdir}/openldap-prereqs.yaml"
  }

  provisioner "file" {
    content     = local.slinky_openldap_values_yaml
    destination = "${local.slinky_workdir}/openldap-values.yaml"
  }

  provisioner "file" {
    source      = "${path.module}/files/slinky/openldap-tls-config.ldif"
    destination = "${local.slinky_workdir}/openldap-tls-config.ldif"
  }

  provisioner "file" {
    source      = "${path.module}/files/slinky/openldap-primary-syncprov.ldif"
    destination = "${local.slinky_workdir}/openldap-primary-syncprov.ldif"
  }

  provisioner "file" {
    content     = local.slinky_home_pvc_yaml
    destination = "${local.slinky_workdir}/slurm-home-pvc.yaml"
  }

  provisioner "file" {
    content     = local.slinky_mariadb_yaml
    destination = "${local.slinky_workdir}/mariadb.yaml"
  }

  provisioner "file" {
    content     = local.slinky_slurm_values_yaml
    destination = "${local.slinky_workdir}/slurm-values.yaml"
  }

  provisioner "file" {
    content     = var.slinky_operator_values_override
    destination = "${local.slinky_workdir}/slinky-operator-values-override.yaml"
  }

  provisioner "file" {
    content     = var.slinky_slurm_values_override
    destination = "${local.slinky_workdir}/slurm-values-override.yaml"
  }

  provisioner "file" {
    content     = local.slinky_deploy_script
    destination = "${local.slinky_workdir}/deploy-slinky-full-suite.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 700 ${local.slinky_workdir}/deploy-slinky-full-suite.sh",
      "${local.slinky_workdir}/deploy-slinky-full-suite.sh",
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [
      "export PATH=$PATH:/usr/local/bin:/home/${self.triggers.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "helm uninstall slurm --namespace ${self.triggers.slurm_namespace} --wait || true",
      "helm uninstall slurm-operator --namespace ${self.triggers.slinky_namespace} --wait || true",
      "helm uninstall slurm-operator-crds --namespace ${self.triggers.slinky_namespace} --wait || true",
      "helm uninstall openldap --namespace ${self.triggers.openldap_namespace} --wait || true",
      "kubectl delete mariadb mariadb --namespace ${self.triggers.slurm_namespace} --ignore-not-found=true || true",
      "helm uninstall mariadb-operator --namespace mariadb --wait || true",
      "helm uninstall mariadb-operator-crds --namespace mariadb --wait || true",
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
      triggers["slurm_namespace"],
      triggers["slinky_namespace"],
      triggers["openldap_namespace"],
    ]
  }

  depends_on = [
    module.oke,
    helm_release.cert_manager,
    module.certmanager,
    null_resource.fss_pv_via_operator,
    kubernetes_persistent_volume_v1.fss,
  ]
}
