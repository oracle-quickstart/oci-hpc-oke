package test

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestLabelerAddsRdmaFabricLabels(t *testing.T) {
	labeler := readRepositoryFile(t, "terraform", "files", "oci-hpc-oke-utils", "templates", "labeler-configmap.yaml")

	require.Contains(t, labeler, `fabric = resp.json().get("rdmaFabricData") or {}`)
	require.Contains(t, labeler, `"oci.oraclecloud.com/rdma.ipv6": str(ipv6).lower() if ipv6 is not None else NO_IMDS`)
	require.Contains(t, labeler, `"oci.oraclecloud.com/rdma.planes": str(planes) if planes is not None else NO_IMDS`)
	require.Equal(t, 1, strings.Count(labeler, "desired.update(rdma_fabric_labels())"))
}
