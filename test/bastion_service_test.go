package test

import (
	"path/filepath"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

// TestValidationBastionServiceSubnets plans the Bastion Service with custom subnet CIDRs.
// The name starts with TestValidation so the CI validation job runs it.
func TestValidationBastionServiceSubnets(t *testing.T) {
	t.Parallel()

	options := newTerraformOptions(t, map[string]interface{}{
		"create_oci_bastion_service":       true,
		"bastion_service_allow_worker_ssh": true,
		"bastion_service_sn_cidr":          "10.140.3.0/26",
		"workers_sn_cidr":                  "10.140.64.0/19",
	})
	options.TerraformDir = copyTerraformToTemp(t)
	options.PlanFilePath = filepath.Join(t.TempDir(), "plan.out")

	plan := terraform.InitAndPlanAndShowWithStructContext(t, t.Context(), options)

	subnet, ok := plan.ResourcePlannedValuesMap["oci_core_subnet.bastion_service[0]"]
	require.True(t, ok, "expected the Bastion Service subnet in the plan")
	require.Equal(t, "10.140.3.0/26", subnet.AttributeValues["cidr_block"])

	// The OKE module must not create a second subnet with the same CIDR.
	_, duplicate := plan.ResourcePlannedValuesMap[`module.oke.module.network.oci_core_subnet.oke["bastion_service"]`]
	require.False(t, duplicate, "the OKE module plans a duplicate Bastion Service subnet")
}
