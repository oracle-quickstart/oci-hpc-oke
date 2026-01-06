package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

// TestPlanSmoke runs terraform plan without applying to validate configuration.
// This is a fast smoke test for CI pipelines.
func TestPlanSmoke(t *testing.T) {
	options := newTerraformOptions(t, nil)
	terraform.InitAndPlan(t, options)
}

func TestCoreProvisioning(t *testing.T) {
	options := newTerraformOptions(t, nil)

	defer terraform.Destroy(t, options)
	terraform.InitAndApply(t, options)

	// Validate state_id is present
	require.NotEmpty(t, terraform.Output(t, options, "state_id"))

	// Validate OCIDs have correct format
	clusterID := terraform.Output(t, options, "cluster_id")
	require.True(t, isValidOCID(clusterID), "cluster_id should be a valid OCID: %s", clusterID)

	vcnID := terraform.Output(t, options, "vcn_id")
	require.True(t, isValidOCID(vcnID), "vcn_id should be a valid OCID: %s", vcnID)

	controlPlaneSubnetID := terraform.Output(t, options, "control_plane_subnet_id")
	require.True(t, isValidOCID(controlPlaneSubnetID), "control_plane_subnet_id should be a valid OCID: %s", controlPlaneSubnetID)

	controlPlaneNsgID := terraform.Output(t, options, "control_plane_nsg_id")
	require.True(t, isValidOCID(controlPlaneNsgID), "control_plane_nsg_id should be a valid OCID: %s", controlPlaneNsgID)

	// Pod subnet/NSG only exist for VCN-Native Pod Networking (not Flannel)
	if podSubnetID := terraform.Output(t, options, "pod_subnet_id"); podSubnetID != "" {
		require.True(t, isValidOCID(podSubnetID), "pod_subnet_id should be a valid OCID: %s", podSubnetID)
	}
	if podNsgID := terraform.Output(t, options, "pod_nsg_id"); podNsgID != "" {
		require.True(t, isValidOCID(podNsgID), "pod_nsg_id should be a valid OCID: %s", podNsgID)
	}

	workerSubnetID := terraform.Output(t, options, "worker_subnet_id")
	require.True(t, isValidOCID(workerSubnetID), "worker_subnet_id should be a valid OCID: %s", workerSubnetID)

	workerNsgID := terraform.Output(t, options, "worker_nsg_id")
	require.True(t, isValidOCID(workerNsgID), "worker_nsg_id should be a valid OCID: %s", workerNsgID)

	// Validate endpoint is present (not an OCID)
	require.NotEmpty(t, terraform.Output(t, options, "cluster_private_endpoint"))
}
