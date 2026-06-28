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
	slinky := readRepositoryFile(t, "terraform", "slinky.tf")

	require.Contains(t, prereqs, "ldap_default_bind_dn = ${openldap_sssd_bind_dn}")
	require.Contains(t, prereqs, "ldap_default_authtok = ${openldap_sssd_bind_password}")
	require.NotContains(t, prereqs, "ldap_default_bind_dn = cn=admin")
	require.NotContains(t, prereqs, "ldap_default_authtok = ${openldap_admin_password}")

	require.Contains(t, slinky, `resource "random_password" "slinky_openldap_sssd_bind"`)
	require.Contains(t, configure, `by dn.exact="$OPENLDAP_SSSD_BIND_DN" none`)
	require.Contains(t, configure, `by dn.exact="$OPENLDAP_SSSD_BIND_DN" read`)
	require.Contains(t, configure, "assert_sssd_write_denied openldap-0")
	require.GreaterOrEqual(t, strings.Count(slurmValues, "oci-hpc-oke.oracle.com/sssd-config-hash"), 4)
}

func TestSlinkyLoginDisablesRootSSH(t *testing.T) {
	slurmValues := readRepositoryFile(t, "terraform", "files", "slinky", "slurm-values.yaml.tftpl")

	require.NotContains(t, slurmValues, "rootSshAuthorizedKeys")
	require.Contains(t, slurmValues, "PermitRootLogin no")
	require.Contains(t, slurmValues, "AuthorizedKeysCommand /usr/bin/sss_ssh_authorizedkeys")
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
