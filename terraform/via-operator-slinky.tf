# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  slinky_workdir = "/home/${local.operator_user}/tf-slinky"

  slinky_openldap_prereqs_yaml = templatefile("${path.module}/files/slinky/openldap-prereqs.yaml.tftpl", {
    openldap_namespace         = var.slinky_openldap_namespace
    slurm_namespace            = var.slinky_slurm_namespace
    openldap_base_dn           = var.slinky_openldap_base_dn
    openldap_admin_password    = local.slinky_openldap_admin_password
    readonly_replica_dns_names = local.slinky_readonly_replica_dns_names
  })

  slinky_openldap_values_yaml = templatefile("${path.module}/files/slinky/openldap-values.yaml.tftpl", {
    openldap_domain            = var.slinky_openldap_domain
    openldap_base_dn           = var.slinky_openldap_base_dn
    openldap_dc                = local.slinky_openldap_dc
    openldap_admin_password    = local.slinky_openldap_admin_password
    openldap_config_password   = local.slinky_openldap_config_password
    openldap_primary_replicas  = var.slinky_openldap_primary_replicas
    openldap_readonly_replicas = var.slinky_openldap_readonly_replicas
    openldap_storage_size      = var.slinky_openldap_storage_size
    system_node_shape          = var.worker_ops_shape
  })

  slinky_configure_openldap_script = templatefile("${path.module}/files/slinky/configure-openldap.sh.tftpl", {
    operator_user                   = local.operator_user
    openldap_namespace              = var.slinky_openldap_namespace
    slurm_namespace                 = var.slinky_slurm_namespace
    openldap_readonly_replicas      = var.slinky_openldap_readonly_replicas
    openldap_admin_password_base64  = base64encode(local.slinky_openldap_admin_password)
    openldap_config_password_base64 = base64encode(local.slinky_openldap_config_password)
    openldap_base_dn                = var.slinky_openldap_base_dn
    openldap_dc                     = local.slinky_openldap_dc
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

  slinky_slurm_auth_secret_yaml = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    immutable  = true
    type       = "Opaque"
    metadata = {
      name      = "slurm-auth-slurm"
      namespace = var.slinky_slurm_namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/part-of"    = "slurm"
      }
    }
    data = {
      "slurm.key" = try(random_bytes.slinky_slurm_key[0].base64, "")
    }
  })

  slinky_jwt_auth_secret_yaml = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    immutable  = true
    type       = "Opaque"
    metadata = {
      name      = "slurm-auth-jwt"
      namespace = var.slinky_slurm_namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/part-of"    = "slurm"
      }
    }
    data = {
      "jwt.key" = try(random_bytes.slinky_jwt_key[0].base64, "")
    }
  })

  slinky_slurm_values_yaml = templatefile("${path.module}/files/slinky/slurm-values.yaml.tftpl", {
    cluster_name                   = local.cluster_name
    identity_enabled               = var.slinky_identity_enabled
    home_enabled                   = var.slinky_home_enabled
    accounting_enabled             = var.slinky_accounting_enabled
    accounting_image_repository    = local.slinky_accounting_image_repository
    accounting_image_tag           = local.slinky_accounting_image_tag
    restapi_image_repository       = local.slinky_restapi_image_repository
    restapi_image_tag              = local.slinky_restapi_image_tag
    system_node_shape              = var.worker_ops_shape
    controller_image_repository    = var.slinky_controller_image_repository
    controller_image_tag           = local.slinky_controller_image_tag
    sssd_image_repository          = local.slinky_sssd_image_repository
    sssd_image_tag                 = local.slinky_sssd_image_tag
    login_image_repository         = var.slinky_login_image_repository
    login_image_tag                = local.slinky_login_image_tag
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
    worker_rdma_vfs_per_node       = local.slinky_worker_rdma_vfs_per_node
    worker_rdma_networks           = local.slinky_worker_rdma_networks_annotation
    worker_slurmd_parameters       = local.slinky_worker_slurmd_parameters
    worker_numa_topology_enabled   = local.slinky_worker_numa_topology_enabled
    worker_features_yaml           = join("\n", [for feature in local.slinky_worker_features : "        - ${feature}"])
    worker_pool_name               = local.slinky_worker_pool_name
    gpu_nodeset_enabled            = local.slinky_gpu_nodeset_enabled
    cpu_nodeset_enabled            = local.slinky_cpu_nodeset_enabled
    cpu_nodeset_name               = var.slinky_cpu_nodeset_name
    cpu_worker_replicas            = var.worker_cpu_pool_size
    cpu_worker_image_repository    = local.slinky_cpu_worker_image_repository
    cpu_worker_image_tag           = local.slinky_cpu_worker_image_tag
    cpu_worker_features_yaml       = join("\n", [for feature in local.slinky_cpu_worker_features : "        - ${feature}"])
    cpu_partition_default          = local.slinky_gpu_nodeset_enabled ? "NO" : "YES"
  })
}

resource "random_bytes" "slinky_slurm_key" {
  count  = alltrue([local.slinky_deploy_from_operator, var.slinky_install_slurm_cluster]) ? 1 : 0
  length = 1024
}

resource "random_bytes" "slinky_jwt_key" {
  count  = alltrue([local.slinky_deploy_from_operator, var.slinky_install_slurm_cluster]) ? 1 : 0
  length = 1024
}

resource "null_resource" "slinky_auth_secrets_via_operator" {
  count = alltrue([local.slinky_deploy_from_operator, var.slinky_install_slurm_cluster]) ? 1 : 0

  triggers = {
    slurm_secret_md5 = nonsensitive(md5(local.slinky_slurm_auth_secret_yaml))
    jwt_secret_md5   = nonsensitive(md5(local.slinky_jwt_auth_secret_yaml))
    slurm_namespace  = var.slinky_slurm_namespace
    bastion_host     = module.oke.bastion_public_ip
    bastion_user     = local.bastion_user
    ssh_private_key  = tls_private_key.stack_key.private_key_openssh
    operator_host    = module.oke.operator_private_ip
    operator_user    = local.operator_user
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
    content     = local.slinky_slurm_auth_secret_yaml
    destination = "${local.slinky_workdir}/slurm-auth-slurm-secret.yaml"
  }

  provisioner "file" {
    content     = local.slinky_jwt_auth_secret_yaml
    destination = "${local.slinky_workdir}/slurm-auth-jwt-secret.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "export PATH=$PATH:/usr/local/bin:/home/${local.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "kubectl create namespace ${var.slinky_slurm_namespace} --dry-run=client -o yaml | kubectl apply -f -",
      "if kubectl -n ${var.slinky_slurm_namespace} get secret slurm-auth-slurm >/dev/null 2>&1; then echo 'Preserving existing slurm-auth-slurm Secret'; else kubectl apply -f ${local.slinky_workdir}/slurm-auth-slurm-secret.yaml; fi",
      "if kubectl -n ${var.slinky_slurm_namespace} get secret slurm-auth-jwt >/dev/null 2>&1; then echo 'Preserving existing slurm-auth-jwt Secret'; else kubectl apply -f ${local.slinky_workdir}/slurm-auth-jwt-secret.yaml; fi",
    ]
  }

  lifecycle {
    ignore_changes = [
      triggers["bastion_host"],
      triggers["bastion_user"],
      triggers["ssh_private_key"],
      triggers["operator_host"],
      triggers["operator_user"],
      triggers["slurm_namespace"],
    ]
  }

  depends_on = [module.oke]
}

# OpenLDAP namespaces, TLS certificates, and SSSD configuration. Applied before
# the OpenLDAP chart so the openldap-tls secret exists at install time.
resource "null_resource" "slinky_openldap_prereqs_via_operator" {
  count = alltrue([local.slinky_deploy_from_operator, var.slinky_identity_enabled]) ? 1 : 0

  triggers = {
    manifest_md5    = nonsensitive(md5(local.slinky_openldap_prereqs_yaml))
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

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "export PATH=$PATH:/usr/local/bin:/home/${local.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "for i in $(seq 1 30); do if [ -f ~/.kube/config ] && timeout 10 kubectl cluster-info >/dev/null 2>&1; then echo 'Kubeconfig is ready'; break; else echo \"Waiting for kubeconfig... ($i/30)\"; sleep 10; fi; done",
      "if ! timeout 30 kubectl cluster-info >/dev/null 2>&1; then echo 'ERROR: kubeconfig is not available'; exit 1; fi",
      "kubectl apply -f ${local.slinky_workdir}/openldap-prereqs.yaml",
      "kubectl -n ${var.slinky_openldap_namespace} wait --for=condition=Ready certificate/openldap-tls --timeout=300s",
    ]
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

  depends_on = [
    module.oke,
    helm_release.cert_manager,
    module.certmanager,
  ]
}

module "slinky_openldap" {
  count  = alltrue([local.slinky_deploy_from_operator, var.slinky_identity_enabled]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = local.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = local.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "openldap"
  helm_chart_name     = "openldap-stack-ha"
  namespace           = var.slinky_openldap_namespace
  helm_repository_url = "https://jp-gouin.github.io/helm-openldap/"
  helm_chart_version  = var.slinky_openldap_chart_version

  pre_deployment_commands = [
    "set -e",
    "export PATH=$PATH:/home/${local.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal",
  ]

  post_deployment_commands = concat(
    ["kubectl -n ${var.slinky_openldap_namespace} rollout status statefulset/openldap --timeout=600s"],
    var.slinky_openldap_readonly_replicas > 0 ? ["kubectl -n ${var.slinky_openldap_namespace} rollout status statefulset/openldap-readonly --timeout=600s"] : [],
  )

  deployment_extra_args = ["--wait", "--timeout 600s", "--history-max 1"]

  # The chart version comment line is part of the values hash, so version bumps
  # trigger a redeploy.
  helm_template_values_override = "# openldap-stack-ha chart ${var.slinky_openldap_chart_version}\n${local.slinky_openldap_values_yaml}"
  helm_user_values_override     = ""

  # Kueue's mutating webhook intercepts StatefulSet creates cluster-wide;
  # installing this chart while Kueue is still starting fails with "no
  # endpoints available for service kueue-webhook-service".
  depends_on = [
    null_resource.slinky_openldap_prereqs_via_operator,
    module.kueue,
    helm_release.kueue,
    kubectl_manifest.kueue_webhook_probe,
  ]
}

# LDAP settings that require exec into the OpenLDAP pods: TLS cn=config,
# syncprov overlay, base tree, and copying the CA into the Slurm namespace.
resource "null_resource" "slinky_openldap_config_via_operator" {
  count = alltrue([local.slinky_deploy_from_operator, var.slinky_identity_enabled]) ? 1 : 0

  triggers = {
    script_md5      = nonsensitive(md5(local.slinky_configure_openldap_script))
    lpk_schema_md5  = md5(file("${path.module}/files/slinky/openssh-lpk-schema.ldif"))
    tls_config_md5  = md5(file("${path.module}/files/slinky/openldap-tls-config.ldif"))
    syncprov_md5    = md5(file("${path.module}/files/slinky/openldap-primary-syncprov.ldif"))
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

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ${local.slinky_workdir}",
      "chmod 700 ${local.slinky_workdir}",
    ]
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
    content     = local.slinky_configure_openldap_script
    destination = "${local.slinky_workdir}/configure-openldap.sh"
  }

  provisioner "file" {
    source      = "${path.module}/files/slinky/openssh-lpk-schema.ldif"
    destination = "${local.slinky_workdir}/openssh-lpk-schema.ldif"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 700 ${local.slinky_workdir}/configure-openldap.sh",
      "${local.slinky_workdir}/configure-openldap.sh",
    ]
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

  depends_on = [module.slinky_openldap]
}

resource "null_resource" "slinky_home_pvc_via_operator" {
  count = alltrue([local.slinky_deploy_from_operator, var.slinky_install_slurm_cluster, var.slinky_home_enabled]) ? 1 : 0

  triggers = {
    manifest_md5    = md5(local.slinky_home_pvc_yaml)
    slurm_namespace = var.slinky_slurm_namespace
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

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ${local.slinky_workdir}",
      "chmod 700 ${local.slinky_workdir}",
    ]
  }

  provisioner "file" {
    content     = local.slinky_home_pvc_yaml
    destination = "${local.slinky_workdir}/slurm-home-pvc.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "export PATH=$PATH:/usr/local/bin:/home/${local.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "for i in $(seq 1 30); do if [ -f ~/.kube/config ] && timeout 10 kubectl cluster-info >/dev/null 2>&1; then echo 'Kubeconfig is ready'; break; else echo \"Waiting for kubeconfig... ($i/30)\"; sleep 10; fi; done",
      "if ! timeout 30 kubectl cluster-info >/dev/null 2>&1; then echo 'ERROR: kubeconfig is not available'; exit 1; fi",
      "kubectl create namespace ${var.slinky_slurm_namespace} --dry-run=client -o yaml | kubectl apply -f -",
      "kubectl apply -f ${local.slinky_workdir}/slurm-home-pvc.yaml",
      "kubectl -n ${var.slinky_slurm_namespace} get pvc slurm-home",
    ]
  }

  # Delete pods that still reference slurm-home before deleting the PVC. A
  # terminating pod can keep pvc-protection/pv-protection finalizers in place,
  # which blocks the FSS PV destroy until Terraform times out.
  provisioner "remote-exec" {
    when = destroy
    inline = [
      <<-EOT
      set -e
      export PATH=$PATH:/usr/local/bin:/home/${self.triggers.operator_user}/bin
      export OCI_CLI_AUTH=instance_principal
      export PYTHONWARNINGS="ignore:the 'strict' parameter::urllib3.poolmanager"
      export NS="${self.triggers.slurm_namespace}"
      export CLAIM="slurm-home"

      for i in $(seq 1 30); do
        if [ -f ~/.kube/config ] && timeout 10 kubectl cluster-info >/dev/null 2>&1; then
          echo 'Kubeconfig is ready'
          break
        fi
        echo "Waiting for kubeconfig... ($i/30)"
        sleep 10
      done
      if ! timeout 30 kubectl cluster-info >/dev/null 2>&1; then
        echo 'WARNING: kubeconfig is not available; skipping slurm-home PVC cleanup'
        exit 0
      fi

      find_pods_using_claim() {
        kubectl -n "$NS" get pods -o json 2>/dev/null | python3 -c '
import json
import os
import sys

claim = os.environ["CLAIM"]
data = json.load(sys.stdin)
names = []
for item in data.get("items", []):
    for volume in item.get("spec", {}).get("volumes", []):
        pvc = volume.get("persistentVolumeClaim")
        if pvc and pvc.get("claimName") == claim:
            names.append(item.get("metadata", {}).get("name", ""))
            break
print(" ".join(name for name in names if name))
'
      }

      echo "== Delete pods using PVC $NS/$CLAIM =="
      PODS="$(find_pods_using_claim || true)"
      if [ -n "$PODS" ]; then
        echo "Deleting pod(s): $PODS"
        kubectl -n "$NS" delete pod $PODS --ignore-not-found=true --wait=true --timeout=180s || true
      fi

      PODS="$(find_pods_using_claim || true)"
      if [ -n "$PODS" ]; then
        echo "Force deleting pod(s) still using $CLAIM: $PODS"
        kubectl -n "$NS" delete pod $PODS --force --grace-period=0 --ignore-not-found=true --wait=false || true
        for i in $(seq 1 36); do
          PODS="$(find_pods_using_claim || true)"
          if [ -z "$PODS" ]; then
            break
          fi
          echo "Waiting for pod(s) to disappear before PVC delete: $PODS ($i/36)"
          sleep 5
        done
      fi

      PODS="$(find_pods_using_claim || true)"
      if [ -n "$PODS" ]; then
        echo "WARNING: pod(s) still reference $CLAIM; attempting PVC delete anyway: $PODS"
      fi

      echo "== Delete PVC $NS/$CLAIM =="
      kubectl -n "$NS" delete pvc "$CLAIM" --ignore-not-found=true --timeout=180s || true
      EOT
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
    ]
  }

  depends_on = [
    module.oke,
    null_resource.fss_pv_via_operator,
    kubernetes_persistent_volume_v1.fss,
  ]
}

module "slinky_mariadb_operator_crds" {
  count  = alltrue([local.slinky_deploy_from_operator, var.slinky_accounting_enabled]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = local.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = local.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "mariadb-operator-crds"
  helm_chart_name     = "mariadb-operator-crds"
  namespace           = "mariadb"
  helm_repository_url = "https://helm.mariadb.com/mariadb-operator"
  helm_chart_version  = var.slinky_mariadb_operator_chart_version

  pre_deployment_commands = [
    "set -e",
    "export PATH=$PATH:/home/${local.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal",
  ]
  post_deployment_commands = []

  deployment_extra_args = ["--wait", "--timeout 300s", "--history-max 1"]

  helm_template_values_override = ""
  helm_user_values_override     = ""

  depends_on = [module.oke]
}

module "slinky_mariadb_operator" {
  count  = alltrue([local.slinky_deploy_from_operator, var.slinky_accounting_enabled]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = local.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = local.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "mariadb-operator"
  helm_chart_name     = "mariadb-operator"
  namespace           = "mariadb"
  helm_repository_url = "https://helm.mariadb.com/mariadb-operator"
  helm_chart_version  = var.slinky_mariadb_operator_chart_version

  pre_deployment_commands = [
    "set -e",
    "export PATH=$PATH:/home/${local.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal",
  ]
  post_deployment_commands = [
    "kubectl -n mariadb rollout status deploy/mariadb-operator-webhook --timeout=300s",
    "kubectl -n mariadb rollout status deploy/mariadb-operator-cert-controller --timeout=300s",
  ]

  deployment_extra_args = ["--wait", "--timeout 300s", "--history-max 1"]

  helm_template_values_override = ""
  helm_user_values_override     = ""

  # Kueue's mutating webhook intercepts all Deployment creates cluster-wide;
  # installing this chart while Kueue is still starting fails with "no
  # endpoints available for service kueue-webhook-service".
  depends_on = [
    module.slinky_mariadb_operator_crds,
    module.kueue,
    helm_release.kueue,
    kubectl_manifest.kueue_webhook_probe,
  ]
}

resource "null_resource" "slinky_mariadb_via_operator" {
  count = alltrue([local.slinky_deploy_from_operator, var.slinky_accounting_enabled]) ? 1 : 0

  triggers = {
    manifest_md5    = md5(local.slinky_mariadb_yaml)
    slurm_namespace = var.slinky_slurm_namespace
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

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ${local.slinky_workdir}",
      "chmod 700 ${local.slinky_workdir}",
    ]
  }

  provisioner "file" {
    content     = local.slinky_mariadb_yaml
    destination = "${local.slinky_workdir}/mariadb.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "export PATH=$PATH:/usr/local/bin:/home/${local.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "kubectl create namespace ${var.slinky_slurm_namespace} --dry-run=client -o yaml | kubectl apply -f -",
      "kubectl apply -f ${local.slinky_workdir}/mariadb.yaml",
      "kubectl -n ${var.slinky_slurm_namespace} wait --for=condition=Ready pod/mariadb-0 --timeout=600s",
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [
      "export PATH=$PATH:/usr/local/bin:/home/${self.triggers.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "kubectl delete mariadb mariadb --namespace ${self.triggers.slurm_namespace} --ignore-not-found=true || true",
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
    ]
  }

  depends_on = [module.slinky_mariadb_operator]
}

module "slinky_operator_crds" {
  count  = local.slinky_deploy_from_operator ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = local.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = local.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "slurm-operator-crds"
  helm_chart_name     = "slurm-operator-crds"
  namespace           = var.slinky_operator_namespace
  helm_repository_url = "oci://ghcr.io/slinkyproject/charts"
  helm_chart_version  = local.slinky_operator_chart_version

  pre_deployment_commands = [
    "set -e",
    "export PATH=$PATH:/home/${local.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal",
  ]
  post_deployment_commands = []

  deployment_extra_args = ["--wait", "--timeout 300s", "--history-max 1"]

  # The chart version comment line is part of the values hash, so version bumps
  # trigger a redeploy.
  helm_template_values_override = "# slurm-operator-crds chart ${local.slinky_operator_chart_version}\n"
  helm_user_values_override     = ""

  depends_on = [module.oke]
}

module "slinky_operator" {
  count  = local.slinky_deploy_from_operator ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = local.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = local.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "slurm-operator"
  helm_chart_name     = "slurm-operator"
  namespace           = var.slinky_operator_namespace
  helm_repository_url = "oci://ghcr.io/slinkyproject/charts"
  helm_chart_version  = local.slinky_operator_chart_version

  pre_deployment_commands = [
    "set -e",
    "export PATH=$PATH:/home/${local.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal",
  ]
  post_deployment_commands = [
    "kubectl -n ${var.slinky_operator_namespace} rollout status deployment/slurm-operator-webhook --timeout=300s",
  ]

  deployment_extra_args = ["--wait", "--timeout 300s", "--history-max 1"]

  # The chart version comment line is part of the values hash, so version bumps
  # trigger a redeploy.
  helm_template_values_override = "# slurm-operator chart ${local.slinky_operator_chart_version}\n${local.slinky_operator_generated_values}"
  helm_user_values_override     = var.slinky_operator_values_override

  # Kueue's mutating webhook intercepts all Deployment creates cluster-wide;
  # installing this chart while Kueue is still starting fails with "no
  # endpoints available for service kueue-webhook-service". The chart also
  # ships cert-manager Certificates and Issuers when cert-manager issuance is
  # enabled, whose admission needs the cert-manager webhook to have ready
  # endpoints.
  depends_on = [
    module.slinky_operator_crds,
    module.kueue,
    helm_release.kueue,
    kubectl_manifest.kueue_webhook_probe,
    module.certmanager,
  ]
}

module "slinky_slurm" {
  count  = alltrue([local.slinky_deploy_from_operator, var.slinky_install_slurm_cluster]) ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = local.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = local.operator_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deployment_name     = "slurm"
  helm_chart_name     = "slurm"
  namespace           = var.slinky_slurm_namespace
  helm_repository_url = "oci://ghcr.io/slinkyproject/charts"
  helm_chart_version  = local.slinky_slurm_chart_version

  pre_deployment_commands = [
    "set -e",
    "export PATH=$PATH:/home/${local.operator_user}/bin",
    "export OCI_CLI_AUTH=instance_principal",
  ]

  post_deployment_commands = concat(
    ["kubectl -n ${var.slinky_slurm_namespace} rollout status statefulset/slurm-controller --timeout=900s"],
    var.slinky_login_enabled ? ["kubectl -n ${var.slinky_slurm_namespace} rollout status deploy/slurm-login-slinky --timeout=600s"] : [],
    var.slinky_accounting_enabled ? ["kubectl -n ${var.slinky_slurm_namespace} rollout status statefulset/slurm-accounting --timeout=600s"] : [],
    # Worker nodes can arrive later or need separate image/capacity fixes. Do
    # not fail the Slurm control-plane install when a NodeSet is not ready yet.
    [
      for nodeset in concat(
        local.slinky_gpu_nodeset_enabled ? [var.slinky_nodeset_name] : [],
        local.slinky_cpu_nodeset_enabled ? [var.slinky_cpu_nodeset_name] : [],
        ) : join("\n", [
          "echo '== Slurm worker nodeset ${nodeset} status =='",
          "WORKER_NODESET=\"slurm-worker-${nodeset}\"",
          "kubectl -n ${var.slinky_slurm_namespace} get nodeset \"$WORKER_NODESET\" -o wide || true",
          "kubectl -n ${var.slinky_slurm_namespace} get pods -o wide | grep \"$WORKER_NODESET\" || true",
      ])
    ],
    [
      "echo '== Validation snapshot =='",
      "kubectl -n ${var.slinky_slurm_namespace} get pods -o wide",
      "kubectl -n ${var.slinky_slurm_namespace} exec slurm-controller-0 -c slurmctld -- sinfo -N -o '%N|%t|%C|%m|%G|%E'",
    ],
  )

  # No --wait: explicit control-plane waits above replace it, and helm --wait
  # can time out while worker nodes are still joining the cluster.
  deployment_extra_args = ["--history-max 1"]

  # The chart version comment line is part of the values hash, so version bumps
  # trigger a redeploy.
  helm_template_values_override = "# slurm chart ${local.slinky_slurm_chart_version}\n${local.slinky_slurm_values_yaml}"
  helm_user_values_override     = var.slinky_slurm_values_override

  depends_on = [
    module.slinky_operator,
    null_resource.slinky_auth_secrets_via_operator,
    null_resource.slinky_openldap_config_via_operator,
    null_resource.slinky_home_pvc_via_operator,
    null_resource.slinky_mariadb_via_operator,
  ]
}
