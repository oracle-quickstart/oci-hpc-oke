# Copyright (c) 2025 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  nvidia_network_operator_sriov_policy_names = [
    for manifest in values(data.kubectl_file_documents.nvidia_network_operator_sriov_policies.manifests) : yamldecode(manifest).metadata.name
  ]
}

resource "null_resource" "nvidia_network_operator_manifests" {
  count = alltrue([local.deploy_nvidia_network_operator_manifests, local.deploy_from_operator]) ? 1 : 0

  triggers = {
    ip_pool_md5     = md5(local.nvidia_network_operator_ip_pool_manifest)
    policies_md5    = md5(file("${path.module}/files/nvidia-network-operator/sriov-network-node-policy.yaml"))
    pool_config_md5 = md5(local.nvidia_network_operator_sriov_pool_config_manifest)
    network_md5     = md5(file("${path.module}/files/nvidia-network-operator/sriov-network.yaml"))
    namespace       = local.nvidia_network_operator_namespace
    policy_names    = join(" ", local.nvidia_network_operator_sriov_policy_names)
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
    content     = local.nvidia_network_operator_ip_pool_manifest
    destination = "/tmp/nv-ipam-ip-pool.yaml"
  }

  provisioner "file" {
    source      = "${path.module}/files/nvidia-network-operator/sriov-network-node-policy.yaml"
    destination = "/tmp/sriov-network-node-policy.yaml"
  }

  provisioner "file" {
    content     = local.nvidia_network_operator_sriov_pool_config_manifest
    destination = "/tmp/sriov-network-pool-config.yaml"
  }

  provisioner "file" {
    source      = "${path.module}/files/nvidia-network-operator/sriov-network.yaml"
    destination = "/tmp/sriov-network.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "export PATH=$PATH:/usr/local/bin:/home/${local.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "export PYTHONWARNINGS=\"ignore:the 'strict' parameter::urllib3.poolmanager\"",
      "for i in $(seq 1 30); do if [ -f ~/.kube/config ] && timeout 10 kubectl cluster-info >/dev/null 2>&1; then echo 'Kubeconfig is ready!'; break; else echo \"Waiting for kubeconfig... ($i/30)\"; sleep 10; fi; done",
      "if ! timeout 30 kubectl cluster-info >/dev/null 2>&1; then echo 'ERROR: Kubeconfig not available after 5 minutes!'; exit 1; fi",
      "for i in $(seq 1 30); do if kubectl get crd ippools.nv-ipam.nvidia.com sriovnetworknodepolicies.sriovnetwork.openshift.io sriovnetworkpoolconfigs.sriovnetwork.openshift.io sriovnetworks.sriovnetwork.openshift.io >/dev/null 2>&1; then echo 'Network Operator CRDs are ready!'; break; else echo \"Waiting for Network Operator CRDs... ($i/30)\"; sleep 10; fi; done",
      "if ! kubectl get crd ippools.nv-ipam.nvidia.com sriovnetworknodepolicies.sriovnetwork.openshift.io sriovnetworkpoolconfigs.sriovnetwork.openshift.io sriovnetworks.sriovnetwork.openshift.io >/dev/null 2>&1; then echo 'ERROR: Network Operator CRDs not available after 5 minutes!'; exit 1; fi",
      "kubectl apply --server-side -f /tmp/nv-ipam-ip-pool.yaml",
      "kubectl apply --server-side -f /tmp/sriov-network-node-policy.yaml",
      "kubectl apply --server-side -f /tmp/sriov-network-pool-config.yaml",
      "kubectl apply --server-side -f /tmp/sriov-network.yaml",
      "rm -f /tmp/nv-ipam-ip-pool.yaml /tmp/sriov-network-node-policy.yaml /tmp/sriov-network-pool-config.yaml /tmp/sriov-network.yaml"
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [
      "export PATH=$PATH:/usr/local/bin:/home/${self.triggers.operator_user}/bin",
      "export OCI_CLI_AUTH=instance_principal",
      "export PYTHONWARNINGS=\"ignore:the 'strict' parameter::urllib3.poolmanager\"",
      "kubectl delete sriovnetworks.sriovnetwork.openshift.io rdma-vf --namespace ${self.triggers.namespace} --ignore-not-found",
      "kubectl delete sriovnetworkpoolconfigs.sriovnetwork.openshift.io rdma-vf --namespace ${self.triggers.namespace} --ignore-not-found",
      "kubectl delete sriovnetworknodepolicies.sriovnetwork.openshift.io ${self.triggers.policy_names} --namespace ${self.triggers.namespace} --ignore-not-found",
      "kubectl delete ippools.nv-ipam.nvidia.com sriov-pool --namespace ${self.triggers.namespace} --ignore-not-found"
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

  depends_on = [
    module.oke,
    oci_containerengine_addon.nvidia_network_operator,
  ]
}
