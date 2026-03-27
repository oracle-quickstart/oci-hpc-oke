package test

import (
	"fmt"
	"os"
	"regexp"
	"testing"

	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
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

	// State assertions
	resources := terraformStateList(t, options)
	requireStateHasPrefix(t, resources, "oci_file_storage_file_system.fss")
	requireStateHasPrefix(t, resources, "oci_file_storage_mount_target.fss_mt")
	requireStateHasPrefix(t, resources, "oci_file_storage_export.FSSExport")
	requireStateHasPrefix(t, resources, "kubernetes_persistent_volume_v1.fss")

	// Attribute validation
	stateID := terraform.Output(t, options, "state_id")
	require.NotEmpty(t, stateID)

	fsID := terraform.Output(t, options, "fss_file_system_id")
	require.True(t, isValidOCID(fsID), "fss_file_system_id should be a valid OCID: %s", fsID)

	mtIP := terraform.Output(t, options, "fss_mount_target_ip")
	require.Regexp(t, regexp.MustCompile(`^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$`), mtIP,
		"fss_mount_target_ip should be a valid IPv4: %s", mtIP)

	exportPath := terraform.Output(t, options, "fss_export_path")
	require.Equal(t, fmt.Sprintf("/oke-gpu-%s", stateID), exportPath,
		"fss_export_path format mismatch")

	nsgID := terraform.Output(t, options, "fss_nsg_id")
	require.True(t, isValidOCID(nsgID), "fss_nsg_id should be a valid OCID: %s", nsgID)

	subnetID := terraform.Output(t, options, "fss_subnet_id")
	require.True(t, isValidOCID(subnetID), "fss_subnet_id should be a valid OCID: %s", subnetID)

	// Kubernetes tests — gated on public endpoint (same pattern as core_provisioning_test.go)
	publicEndpoint := optionalOutput(t, options, "cluster_public_endpoint")
	if publicEndpoint == "" {
		t.Log("Skipping Kubernetes FSS tests: no public endpoint")
		return
	}
	clusterID := terraform.Output(t, options, "cluster_id")
	region := os.Getenv("OCI_REGION")
	kubeconfigPath := generateKubeconfig(t, clusterID, region)
	testFSSKubernetes(t, kubeconfigPath)
}

// testFSSKubernetes verifies PVC binding and shared filesystem write/read.
// Both tests share one PVC because fss-pv uses the Retain reclaim policy —
// after a PVC is deleted the PV enters Released state and cannot be rebound.
func testFSSKubernetes(t *testing.T, kubeconfigPath string) {
	t.Helper()
	opts := k8s.NewKubectlOptions("", kubeconfigPath, "default")

	pvcYAML := `
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fss-test-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 50Gi
  volumeName: fss-pv
`
	k8s.KubectlApplyFromString(t, opts, pvcYAML)
	defer k8s.RunKubectl(t, opts, "delete", "pvc", "fss-test-pvc", "--ignore-not-found=true")

	t.Log("Waiting for FSS PVC to bind")
	k8s.RunKubectl(t, opts, "wait",
		"--for=jsonpath={.status.phase}=Bound",
		"pvc/fss-test-pvc",
		"--timeout=120s",
	)

	writerYAML := `
apiVersion: v1
kind: Pod
metadata:
  name: fss-writer
spec:
  restartPolicy: Never
  containers:
  - name: writer
    image: busybox
    command: ["sh", "-c", "echo 'fss-test-content' > /mnt/fss/testfile.txt"]
    volumeMounts:
    - name: fss
      mountPath: /mnt/fss
  volumes:
  - name: fss
    persistentVolumeClaim:
      claimName: fss-test-pvc
`
	k8s.KubectlApplyFromString(t, opts, writerYAML)
	defer k8s.RunKubectl(t, opts, "delete", "pod", "fss-writer", "--ignore-not-found=true")

	t.Log("Waiting for FSS writer pod to complete")
	k8s.RunKubectl(t, opts, "wait",
		"--for=jsonpath={.status.phase}=Succeeded",
		"pod/fss-writer",
		"--timeout=120s",
	)

	readerYAML := `
apiVersion: v1
kind: Pod
metadata:
  name: fss-reader
spec:
  restartPolicy: Never
  containers:
  - name: reader
    image: busybox
    command: ["sh", "-c", "cat /mnt/fss/testfile.txt"]
    volumeMounts:
    - name: fss
      mountPath: /mnt/fss
  volumes:
  - name: fss
    persistentVolumeClaim:
      claimName: fss-test-pvc
`
	k8s.KubectlApplyFromString(t, opts, readerYAML)
	defer k8s.RunKubectl(t, opts, "delete", "pod", "fss-reader", "--ignore-not-found=true")

	t.Log("Waiting for FSS reader pod to complete")
	k8s.RunKubectl(t, opts, "wait",
		"--for=jsonpath={.status.phase}=Succeeded",
		"pod/fss-reader",
		"--timeout=120s",
	)

	output, err := k8s.RunKubectlAndGetOutputE(t, opts, "logs", "fss-reader")
	require.NoError(t, err)
	require.Contains(t, output, "fss-test-content",
		"reader pod output should contain written content")
	t.Log("FSS write/read test passed")
}
