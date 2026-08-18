package test

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestGvaPodLimitsDeriveFromPoolMaxPods(t *testing.T) {
	workers := readRepositoryFile(t, "terraform", "oke-workers.tf")
	variables := readRepositoryFile(t, "terraform", "variables.tf")
	schema := readRepositoryFile(t, "terraform", "schema.yaml")

	require.Contains(t, variables, `variable "force_use_gva"`)
	require.Contains(t, schema, "force_use_gva:")

	for _, pool := range []string{"ops", "cpu", "gpu", "rdma", "gmc"} {
		maxPodsVariable := fmt.Sprintf("worker_%s_max_pods_per_node", pool)
		gvaLocal := fmt.Sprintf("worker_%s_gva_ip_count", pool)

		require.Contains(t, variables, fmt.Sprintf(`variable "%s"`, maxPodsVariable))
		require.NotContains(t, variables, fmt.Sprintf(`variable "%s"`, gvaLocal))
		require.Contains(t, workers, gvaLocal)
		require.Contains(t, workers, fmt.Sprintf(
			`pow(2, floor(log(max(var.%s, 1), 2)))`,
			maxPodsVariable,
		))
	}
}

func TestGvaPodLimitRoundingIsDocumented(t *testing.T) {
	variables := readRepositoryFile(t, "terraform", "variables.tf")
	workers := readRepositoryFile(t, "terraform", "oke-workers.tf")

	require.Contains(t, variables, "rounded down to the closest power of two")
	require.Contains(t, workers, "a requested value such as 110 becomes 64 with GVA")
	require.Contains(t, workers, "remains 110 with flannel/legacy networking")
}
