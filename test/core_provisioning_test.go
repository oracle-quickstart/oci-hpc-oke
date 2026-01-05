package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

func TestCoreProvisioning(t *testing.T) {
	options := newTerraformOptions(t, nil)

	defer terraform.Destroy(t, options)
	terraform.InitAndApply(t, options)

	require.NotEmpty(t, terraform.Output(t, options, "state_id"))
	require.NotEmpty(t, terraform.Output(t, options, "cluster_id"))
	require.NotEmpty(t, terraform.Output(t, options, "cluster_private_endpoint"))
	require.NotEmpty(t, terraform.Output(t, options, "control_plane_subnet_id"))
	require.NotEmpty(t, terraform.Output(t, options, "control_plane_nsg_id"))
	require.NotEmpty(t, terraform.Output(t, options, "pod_subnet_id"))
	require.NotEmpty(t, terraform.Output(t, options, "pod_nsg_id"))
	require.NotEmpty(t, terraform.Output(t, options, "vcn_id"))
	require.NotEmpty(t, terraform.Output(t, options, "worker_subnet_id"))
	require.NotEmpty(t, terraform.Output(t, options, "worker_nsg_id"))
}
