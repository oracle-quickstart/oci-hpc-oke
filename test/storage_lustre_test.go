package test

import (
	"fmt"
	"os"
	"regexp"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

func TestStorageLustre(t *testing.T) {
	skipUnlessEnv(t, "RUN_LUSTRE_TESTS")

	vars := map[string]interface{}{
		"create_lustre": true,
	}
	// Optional: override AD if LUSTRE_AD is set, otherwise falls back to worker_ops_ad
	if lustreAD := envOrDefault([]string{"LUSTRE_AD", "OCI_LUSTRE_AD", "TF_VAR_lustre_ad"}, ""); lustreAD != "" {
		vars["lustre_ad"] = lustreAD
	}
	options := newTerraformOptions(t, vars)

	defer terraform.Destroy(t, options)
	terraform.InitAndApply(t, options)

	// State assertions
	resources := terraformStateList(t, options)
	requireStateHasPrefix(t, resources, "oci_lustre_file_storage_lustre_file_system.lustre")
	requireStateHasPrefix(t, resources, "oci_core_network_security_group.lustre")
	requireStateHasPrefix(t, resources, "oci_core_subnet.lustre_subnet")
	requireStateHasPrefix(t, resources, "kubectl_manifest.lustre_pv")

	// Attribute validation
	fsID := terraform.Output(t, options, "lustre_file_system_id")
	require.True(t, isValidOCID(fsID), "lustre_file_system_id should be a valid OCID: %s", fsID)

	mgsAddr := terraform.Output(t, options, "lustre_management_service_address")
	require.Regexp(t, regexp.MustCompile(`^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$`), mgsAddr,
		"lustre_management_service_address should be a valid IPv4: %s", mgsAddr)

	nsgID := terraform.Output(t, options, "lustre_nsg_id")
	require.True(t, isValidOCID(nsgID), "lustre_nsg_id should be a valid OCID: %s", nsgID)

	subnetID := terraform.Output(t, options, "lustre_subnet_id")
	require.True(t, isValidOCID(subnetID), "lustre_subnet_id should be a valid OCID: %s", subnetID)

	// Kubernetes tests — gated on public endpoint (same pattern as storage_fss_test.go)
	publicEndpoint := optionalOutput(t, options, "cluster_public_endpoint")
	if publicEndpoint == "" {
		t.Log("Skipping Kubernetes Lustre tests: no public endpoint")
		return
	}
	clusterID := terraform.Output(t, options, "cluster_id")
	region := os.Getenv("OCI_REGION")
	kubeconfigPath := generateKubeconfig(t, clusterID, region)
	testLustreKubernetes(t, kubeconfigPath, options)
}

// testLustreKubernetes verifies PVC binding and shared filesystem write/read.
// Both tests share one PVC because lustre-pv uses the Retain reclaim policy —
// after a PVC is deleted the PV enters Released state and cannot be rebound.
func testLustreKubernetes(t *testing.T, kubeconfigPath string, options *terraform.Options) {
	t.Helper()
	opts := k8s.NewKubectlOptions("", kubeconfigPath, "default")

	pvcYAML := `
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: lustre-test-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 1Ti
  volumeName: lustre-pv
`
	k8s.KubectlApplyFromString(t, opts, pvcYAML)
	defer k8s.RunKubectl(t, opts, "delete", "pvc", "lustre-test-pvc", "--ignore-not-found=true")

	t.Log("Waiting for Lustre PVC to bind")
	k8s.RunKubectl(t, opts, "wait",
		"--for=jsonpath={.status.phase}=Bound",
		"pvc/lustre-test-pvc",
		"--timeout=120s",
	)

	writerYAML := `
apiVersion: v1
kind: Pod
metadata:
  name: lustre-writer
spec:
  restartPolicy: Never
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
  - key: amd.com/gpu
    operator: Exists
  containers:
  - name: writer
    image: busybox
    command: ["sh", "-c", "echo 'lustre-test-content' > /mnt/lustre/testfile.txt"]
    volumeMounts:
    - name: lustre
      mountPath: /mnt/lustre
  volumes:
  - name: lustre
    persistentVolumeClaim:
      claimName: lustre-test-pvc
`
	k8s.KubectlApplyFromString(t, opts, writerYAML)
	defer k8s.RunKubectl(t, opts, "delete", "pod", "lustre-writer", "--ignore-not-found=true")

	t.Log("Waiting for Lustre writer pod to complete")
	k8s.RunKubectl(t, opts, "wait",
		"--for=jsonpath={.status.phase}=Succeeded",
		"pod/lustre-writer",
		"--timeout=120s",
	)

	writerNodeRaw, err := k8s.RunKubectlAndGetOutputE(t, opts,
		"get", "pod", "lustre-writer",
		"-o", "jsonpath={.spec.nodeName}",
	)
	require.NoError(t, err)
	writerNode := strings.TrimSpace(writerNodeRaw)
	require.NotEmpty(t, writerNode, "lustre-writer pod should have a nodeName")
	t.Logf("Lustre writer ran on node: %s", writerNode)

	readerYAML := fmt.Sprintf(`
apiVersion: v1
kind: Pod
metadata:
  name: lustre-reader
spec:
  restartPolicy: Never
  nodeName: %s
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
  - key: amd.com/gpu
    operator: Exists
  containers:
  - name: reader
    image: busybox
    command: ["sh", "-c", "cat /mnt/lustre/testfile.txt"]
    volumeMounts:
    - name: lustre
      mountPath: /mnt/lustre
  volumes:
  - name: lustre
    persistentVolumeClaim:
      claimName: lustre-test-pvc
`, writerNode)
	k8s.KubectlApplyFromString(t, opts, readerYAML)
	defer k8s.RunKubectl(t, opts, "delete", "pod", "lustre-reader", "--ignore-not-found=true")

	t.Log("Waiting for Lustre reader pod to complete")
	k8s.RunKubectl(t, opts, "wait",
		"--for=jsonpath={.status.phase}=Succeeded",
		"pod/lustre-reader",
		"--timeout=120s",
	)

	output, err := k8s.RunKubectlAndGetOutputE(t, opts, "logs", "lustre-reader")
	require.NoError(t, err)
	require.Contains(t, output, "lustre-test-content",
		"reader pod output should contain written content")
	t.Log("Lustre write/read test passed")

	// OS-level mount check: read the file written via CSI using a hostPath pod on the same node
	lustreMountPath := terraform.Output(t, options, "lustre_mount_path")
	require.NotEmpty(t, lustreMountPath)

	hostpathReaderYAML := fmt.Sprintf(`
apiVersion: v1
kind: Pod
metadata:
  name: lustre-hostpath-reader
spec:
  restartPolicy: Never
  nodeName: %s
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
  - key: amd.com/gpu
    operator: Exists
  containers:
  - name: reader
    image: busybox
    command: ["sh", "-c", "for i in $(seq 1 20); do content=$(cat /mnt/lustre-host/testfile.txt 2>/dev/null); if [ -n \"$content\" ]; then echo \"$content\"; exit 0; fi; sleep 3; done; echo 'file not found after 60s'; exit 1"]
    volumeMounts:
    - name: lustre-host
      mountPath: /mnt/lustre-host
  volumes:
  - name: lustre-host
    hostPath:
      path: %s
      type: Directory
`, writerNode, lustreMountPath)

	k8s.KubectlApplyFromString(t, opts, hostpathReaderYAML)
	defer k8s.RunKubectl(t, opts, "delete", "pod", "lustre-hostpath-reader", "--ignore-not-found=true")

	t.Log("Waiting for Lustre hostPath reader pod to complete")
	k8s.RunKubectl(t, opts, "wait",
		"--for=jsonpath={.status.phase}=Succeeded",
		"pod/lustre-hostpath-reader",
		"--timeout=120s",
	)

	hostOutput, err := k8s.RunKubectlAndGetOutputE(t, opts, "logs", "lustre-hostpath-reader")
	require.NoError(t, err)
	require.Contains(t, hostOutput, "lustre-test-content",
		"Lustre hostPath reader should see the file written via CSI path")
	t.Log("Lustre OS-level mount (hostPath) test passed")
}
