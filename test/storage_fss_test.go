package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestStorageFSS(t *testing.T) {
	skipUnlessEnv(t, "RUN_FSS_TESTS")

	fssAD := requireAnyEnv(t, "FSS_AD", "OCI_FSS_AD", "TF_VAR_fss_ad")
	options := newTerraformOptions(t, map[string]interface{}{
		"create_fss": true,
		"fss_ad":     fssAD,
	})

	defer terraform.Destroy(t, options)
	terraform.InitAndApply(t, options)

	resources := terraformStateList(t, options)
	requireStateHasPrefix(t, resources, "oci_file_storage_file_system.fss")
	requireStateHasPrefix(t, resources, "oci_file_storage_mount_target.fss_mt")
	requireStateHasPrefix(t, resources, "oci_file_storage_export.FSSExport")
	requireStateHasPrefix(t, resources, "kubernetes_persistent_volume_v1.fss")
}
