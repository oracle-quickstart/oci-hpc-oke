package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestStorageLustre(t *testing.T) {
	skipUnlessEnv(t, "RUN_LUSTRE_TESTS")

	options := newTerraformOptions(t, map[string]interface{}{
		"create_lustre":         true,
		"install_lustre_client": true,
		"create_lustre_pv":      true,
	})

	defer terraform.Destroy(t, options)
	terraform.InitAndApply(t, options)

	resources := terraformStateList(t, options)
	requireStateHasPrefix(t, resources, "oci_lustre_file_storage_lustre_file_system.lustre")
	requireStateHasPrefix(t, resources, "oci_core_network_security_group.lustre")
	requireStateHasPrefix(t, resources, "oci_core_subnet.lustre_subnet")
}
