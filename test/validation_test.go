package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

// validationTestCase defines a single validation test scenario
type validationTestCase struct {
	name          string
	vars          map[string]interface{}
	expectedError string
}

// validationTestCases contains all validation scenarios to test
var validationTestCases = []validationTestCase{
	{
		name: "PublicServicesRequirePublicSubnets",
		vars: map[string]interface{}{
			"create_public_subnets":         false,
			"preferred_kubernetes_services": "public",
		},
		expectedError: "Public Kubernetes services require public subnets",
	},
	{
		name: "PublicEndpointRequiresPublicSubnets",
		vars: map[string]interface{}{
			"create_public_subnets":   false,
			"control_plane_is_public": true,
		},
		expectedError: "public cluster endpoint requires public subnets",
	},
	{
		name: "BastionRequiresPublicSubnets",
		vars: map[string]interface{}{
			"create_public_subnets": false,
			"create_bastion":        true,
		},
		expectedError: "Creating a bastion requires public subnets",
	},
	{
		name: "InvalidImageURI",
		vars: map[string]interface{}{
			"worker_ops_image_use_uri":    true,
			"worker_ops_image_custom_uri": "not-a-url",
		},
		expectedError: "Invalid image URI detected",
	},
	{
		name: "InvalidCpuImageURI",
		vars: map[string]interface{}{
			"worker_cpu_image_use_uri":    true,
			"worker_cpu_image_custom_uri": "not-a-url",
		},
		expectedError: "Invalid image URI detected",
	},
	{
		name: "InvalidGpuImageURI",
		vars: map[string]interface{}{
			"worker_gpu_image_use_uri":    true,
			"worker_gpu_image_custom_uri": "not-a-url",
		},
		expectedError: "Invalid image URI detected",
	},
	{
		name: "InvalidRdmaImageURI",
		vars: map[string]interface{}{
			"worker_rdma_image_use_uri":    true,
			"worker_rdma_image_custom_uri": "not-a-url",
		},
		expectedError: "Invalid image URI detected",
	},
	{
		name: "GB200ShapeBlocked",
		vars: map[string]interface{}{
			"worker_rdma_shape": "BM.GPU.GB200.4",
		},
		expectedError: "GB200 shapes",
	},
	{
		name: "GB200v2ShapeBlocked",
		vars: map[string]interface{}{
			"worker_rdma_shape": "BM.GPU.GB200-v2.4",
		},
		expectedError: "GB200 shapes",
	},
	{
		name: "GB200v3ShapeBlocked",
		vars: map[string]interface{}{
			"worker_rdma_shape": "BM.GPU.GB200-v3.4",
		},
		expectedError: "GB200 shapes",
	},
	{
		name: "PodCapacityExceeded",
		vars: map[string]interface{}{
			// /30 subnet = 4 IPs - 3 reserved = 1 usable
			// default ops pool: 1 node × 31 pods = 31 required > 1 capacity
			"pods_sn_cidr": "10.240.0.0/30",
		},
		expectedError: "Total required pod IPs",
	},
}

// TestValidation runs all validation test cases in parallel using table-driven tests
func TestValidation(t *testing.T) {
	t.Parallel()

	for _, tc := range validationTestCases {
		tc := tc // capture range variable for parallel execution
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			// Each parallel subtest gets its own copy of the terraform directory
			// to prevent concurrent terraform init calls from racing on lock files.
			tmpDir := copyTerraformToTemp(t)
			options := newTerraformOptions(t, tc.vars)
			options.TerraformDir = tmpDir
			assertPlanFailsWithError(t, options, tc.expectedError)
		})
	}
}

func assertPlanFailsWithError(t *testing.T, options *terraform.Options, expected string) {
	t.Helper()
	_, err := terraform.InitAndPlanE(t, options)
	require.Error(t, err)
	require.Contains(t, err.Error(), expected)
}
