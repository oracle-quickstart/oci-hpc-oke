package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestStorageFSS(t *testing.T) {
	skipUnlessEnv(t, "RUN_FSS_TESTS")

	vars := map[string]interface{}{
		"create_fss": true,
	}
	// Optional: override AD if FSS_AD is set, otherwise falls back to worker_ops_ad
	if fssAD := envOrDefault([]string{"FSS_AD", "OCI_FSS_AD", "TF_VAR_fss_ad"}, ""); fssAD != "" {
		vars["fss_ad"] = fssAD
	}
	options := newTerraformOptions(t, vars)

	defer terraform.Destroy(t, options)
	terraform.InitAndApply(t, options)

	resources := terraformStateList(t, options)
	requireStateHasPrefix(t, resources, "oci_file_storage_file_system.fss")
	requireStateHasPrefix(t, resources, "oci_file_storage_mount_target.fss_mt")
	requireStateHasPrefix(t, resources, "oci_file_storage_export.FSSExport")
	requireStateHasPrefix(t, resources, "kubernetes_persistent_volume_v1.fss")
}
