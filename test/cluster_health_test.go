package test

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/stretchr/testify/require"
)

// generateKubeconfig creates a kubeconfig for the given OKE cluster using OCI CLI.
func generateKubeconfig(t *testing.T, clusterID, region string) string {
	t.Helper()
	kubeconfigPath := filepath.Join(t.TempDir(), "kubeconfig")
	cmd := exec.Command("oci", "ce", "cluster", "create-kubeconfig",
		"--cluster-id", clusterID,
		"--file", kubeconfigPath,
		"--region", region,
		"--token-version", "2.0.0",
		"--kube-endpoint", "PUBLIC_ENDPOINT",
	)
	output, err := cmd.CombinedOutput()
	require.NoError(t, err, "Failed to generate kubeconfig: %s", string(output))
	return kubeconfigPath
}

// runClusterHealthChecks performs Tier 1 K8s health checks against a running cluster.
func runClusterHealthChecks(t *testing.T, kubeconfigPath string) {
	t.Helper()

	opts := k8s.NewKubectlOptions("", kubeconfigPath, "default")
	sysOpts := k8s.NewKubectlOptions("", kubeconfigPath, "kube-system")

	// API server reachable
	t.Log("Health check: API server connectivity")
	k8s.RunKubectl(t, opts, "cluster-info")

	// All nodes ready (wait up to 5 min)
	t.Log("Health check: waiting for nodes to be Ready")
	k8s.RunKubectl(t, opts, "wait", "--for=condition=Ready", "nodes", "--all", "--timeout=300s")

	// Verify at least 1 node exists
	output, err := k8s.RunKubectlAndGetOutputE(t, opts, "get", "nodes", "--no-headers")
	require.NoError(t, err)
	nodeLines := strings.Split(strings.TrimSpace(output), "\n")
	require.True(t, len(nodeLines) >= 1 && nodeLines[0] != "", "cluster should have at least one node")
	t.Logf("Health check: %d node(s) ready", len(nodeLines))

	// CoreDNS pods ready
	t.Log("Health check: CoreDNS pods")
	k8s.RunKubectl(t, sysOpts, "wait", "--for=condition=Ready", "pods", "-l", "k8s-app=kube-dns", "--timeout=120s")

	// kube-proxy pods running
	t.Log("Health check: kube-proxy pods")
	k8s.RunKubectl(t, sysOpts, "wait", "--for=condition=Ready", "pods", "-l", "k8s-app=kube-proxy", "--timeout=120s")

	t.Log("Health check: all cluster health checks passed")
}
