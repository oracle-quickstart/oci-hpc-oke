package test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func readRepositoryFile(t *testing.T, path ...string) string {
	t.Helper()

	contents, err := os.ReadFile(filepath.Join(append([]string{".."}, path...)...))
	require.NoError(t, err)
	return string(contents)
}

func TestSlinkySSSDUsesReadOnlyBindAccount(t *testing.T) {
	prereqs := readRepositoryFile(t, "terraform", "files", "slinky", "openldap-prereqs.yaml.tftpl")
	configure := readRepositoryFile(t, "terraform", "files", "slinky", "configure-openldap.sh.tftpl")
	slurmValues := readRepositoryFile(t, "terraform", "files", "slinky", "slurm-values.yaml.tftpl")
	workerValues := readRepositoryFile(t, "terraform", "files", "slinky", "worker-nodeset-values.yaml.tftpl")
	slinky := readRepositoryFile(t, "terraform", "slinky.tf")

	require.Contains(t, prereqs, "ldap_default_bind_dn = ${openldap_sssd_bind_dn}")
	require.Contains(t, prereqs, "ldap_default_authtok = ${openldap_sssd_bind_password}")
	require.NotContains(t, prereqs, "ldap_default_bind_dn = cn=admin")
	require.NotContains(t, prereqs, "ldap_default_authtok = ${openldap_admin_password}")

	require.Contains(t, slinky, `resource "random_password" "slinky_openldap_sssd_bind"`)
	require.Contains(t, configure, `by dn.exact="$OPENLDAP_SSSD_BIND_DN" none`)
	require.Contains(t, configure, `by dn.exact="$OPENLDAP_SSSD_BIND_DN" read`)
	require.Contains(t, configure, "assert_sssd_write_denied openldap-0")
	require.GreaterOrEqual(t, strings.Count(slurmValues, "oci-hpc-oke.oracle.com/sssd-config-hash")+strings.Count(workerValues, "oci-hpc-oke.oracle.com/sssd-config-hash"), 4)
}

func TestSlinkyUsesIndependentAcceleratorNodeSets(t *testing.T) {
	slinky := readRepositoryFile(t, "terraform", "slinky.tf")
	viaOperator := readRepositoryFile(t, "terraform", "via-operator-slinky.tf")
	workerValues := readRepositoryFile(t, "terraform", "files", "slinky", "worker-nodeset-values.yaml.tftpl")
	slurmValues := readRepositoryFile(t, "terraform", "files", "slinky", "slurm-values.yaml.tftpl")
	okeCluster := readRepositoryFile(t, "terraform", "oke-cluster.tf")

	require.Contains(t, slinky, `slinky_gpu_worker_nodesets`)
	require.Contains(t, slinky, `pool_name           = "oke-gpu"`)
	require.Contains(t, slinky, `slinky_rdma_worker_nodesets`)
	require.Contains(t, slinky, `pool_name           = "oke-rdma"`)
	require.Contains(t, slinky, `slinky_gmc_worker_nodesets`)
	require.Contains(t, slinky, `pool_name           = "oke-gmc"`)
	require.Contains(t, slinky, `slinky_worker_nodesets = merge(`)
	require.Contains(t, workerValues, `oke.oraclecloud.com/pool.name: ${pool_name}`)
	require.Contains(t, slurmValues, `${worker_nodesets_yaml}`)
	require.Contains(t, viaOperator, `sort(keys(local.slinky_worker_nodesets))`)
	require.Contains(t, okeCluster, `var.worker_gmc_enabled ? length(local.worker_gmc_gpu_memory_fabric_ids) * var.worker_gmc_scale_target_size : 0`)
}

func TestSlinkyGMCUsesPerFabricIMEXComputeDomains(t *testing.T) {
	slinky := readRepositoryFile(t, "terraform", "slinky.tf")
	viaOperator := readRepositoryFile(t, "terraform", "via-operator-slinky.tf")
	workerValues := readRepositoryFile(t, "terraform", "files", "slinky", "worker-nodeset-values.yaml.tftpl")
	slurmValues := readRepositoryFile(t, "terraform", "files", "slinky", "slurm-values.yaml.tftpl")

	require.Contains(t, slinky, `slinky_gmc_nodeset_fabrics`)
	require.Contains(t, workerValues, `oci.oraclecloud.com/host.gpu_memory_fabric_id: ${fabric_label}`)
	require.Contains(t, slinky, `apiVersion = "resource.nvidia.com/v1beta1"`)
	require.Contains(t, slinky, `kind       = "ComputeDomain"`)
	require.Contains(t, slinky, `allocationMode = "All"`)
	require.Contains(t, workerValues, `resourceClaimTemplateName: ${imex_claim_template}`)
	require.Contains(t, workerValues, `claims:`)
	require.Contains(t, slurmValues, `SwitchType: switch/nvidia_imex`)
	require.Contains(t, slurmValues, `${gmc_partition_name}:`)
	require.Contains(t, slurmValues, `${gmc_partition_nodesets_yaml}`)
	require.Contains(t, slinky, `slinky_gmc_aggregate_partition_name`)
	require.Contains(t, viaOperator, `resource "null_resource" "slinky_gmc_compute_domains_via_operator"`)
}

func TestSlinkyLoginDisablesRootSSH(t *testing.T) {
	slurmValues := readRepositoryFile(t, "terraform", "files", "slinky", "slurm-values.yaml.tftpl")

	require.NotContains(t, slurmValues, "rootSshAuthorizedKeys")
	require.Contains(t, slurmValues, "PermitRootLogin no")
	require.Contains(t, slurmValues, "AuthorizedKeysCommand /usr/bin/sss_ssh_authorizedkeys")
}

func TestSlinkyLoginRequiresManagedIdentity(t *testing.T) {
	validation := readRepositoryFile(t, "terraform", "validation.tf")
	variables := readRepositoryFile(t, "terraform", "variables.tf")
	schema := readRepositoryFile(t, "terraform", "schema.yaml")

	require.Contains(t, validation, `invalid_slinky_login_without_identity = alltrue([`)
	require.Contains(t, validation, `var.slinky_install_slurm_cluster,`)
	require.Contains(t, validation, `var.slinky_login_enabled,`)
	require.Contains(t, validation, `!var.slinky_identity_enabled,`)
	require.Contains(t, validation, `resource "null_resource" "validate_slinky_login_identity"`)
	require.Contains(t, validation, `slinky_login_enabled=true requires slinky_identity_enabled=true`)
	require.Contains(t, validation, `ldap://ldap.example.com`)
	require.Contains(t, variables, `Requires slinky_identity_enabled=true`)
	require.Contains(t, schema, `Requires HA OpenLDAP and SSSD to be enabled.`)
}

func TestSlinkyLoginHonorsPreferredKubernetesServices(t *testing.T) {
	slurmValues := readRepositoryFile(t, "terraform", "files", "slinky", "slurm-values.yaml.tftpl")
	viaOperator := readRepositoryFile(t, "terraform", "via-operator-slinky.tf")
	okeCluster := readRepositoryFile(t, "terraform", "oke-cluster.tf")

	require.Contains(t, viaOperator, `login_load_balancer_internal = var.preferred_kubernetes_services == "internal"`)
	require.Contains(t, viaOperator, `login_load_balancer_nsg_id   = var.preferred_kubernetes_services == "public" ? module.oke.pub_lb_nsg_id : module.oke.int_lb_nsg_id`)
	require.Contains(t, slurmValues, `%{ if login_load_balancer_internal ~}`)
	require.Contains(t, slurmValues, `service.beta.kubernetes.io/oci-load-balancer-internal: "true"`)
	require.Contains(t, slurmValues, `oci.oraclecloud.com/oci-network-security-groups: ${jsonencode(login_load_balancer_nsg_id)}`)
	require.Contains(t, slurmValues, `service.beta.kubernetes.io/oci-load-balancer-security-list-management-mode: "None"`)
	require.Contains(t, okeCluster, `"Allow TCP ingress from anywhere to Slurm login SSH port"`)
	require.Contains(t, okeCluster, `protocol = local.tcp_protocol, port = 22, source = local.anywhere`)
}

func TestSlinkyControlPlaneUsesSystemPool(t *testing.T) {
	slurmValues := readRepositoryFile(t, "terraform", "files", "slinky", "slurm-values.yaml.tftpl")
	openldapValues := readRepositoryFile(t, "terraform", "files", "slinky", "openldap-values.yaml.tftpl")
	viaOperator := readRepositoryFile(t, "terraform", "via-operator-slinky.tf")
	slinky := readRepositoryFile(t, "terraform", "slinky.tf")

	require.Contains(t, slinky, `slinky_system_pool_name = "oke-system"`)
	require.Contains(t, viaOperator, `system_node_pool_name`)
	require.Equal(t, 4, strings.Count(slurmValues, `oke.oraclecloud.com/pool.name: ${system_node_pool_name}`))
	require.Contains(t, openldapValues, `oke.oraclecloud.com/pool.name: ${system_node_pool_name}`)
	require.NotContains(t, slurmValues, `node.kubernetes.io/instance-type: ${system_node_shape}`)
	require.NotContains(t, openldapValues, `node.kubernetes.io/instance-type: ${system_node_shape}`)
}
