package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestStorageLustre(t *testing.T) {
	skipUnlessEnv(t, "RUN_LUSTRE_TESTS")

	options := newTerraformOptions(t, map[string]interface{}{
		"create_lustre":         true,
		"install_lustre_client": false,
		"create_lustre_pv":      false,
	})

	defer terraform.Destroy(t, options)
	terraform.InitAndApply(t, options)

	resources := terraformStateList(t, options)
	requireStateHasPrefix(t, resources, "oci_lustre_file_storage_lustre_file_system.lustre")
	requireStateHasPrefix(t, resources, "oci_core_security_list.lustre_sl")
	requireStateHasPrefix(t, resources, "oci_core_subnet.lustre_subnet")
}
