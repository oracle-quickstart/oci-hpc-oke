package test

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

const (
	// Default retry configuration
	defaultMaxRetries         = 3
	defaultTimeBetweenRetries = 15 * time.Second
)

type baseVarsOptions struct {
	includeDefaults      bool
	allowMissingRequired bool
}

func terraformDir() string {
	return filepath.Join("..", "terraform")
}

func baseVars(t *testing.T, opts baseVarsOptions) map[string]interface{} {
	t.Helper()

	auth := strings.ToLower(envOrDefault([]string{"OCI_AUTH", "TF_VAR_oci_auth"}, "api_key"))

	required := func(keys ...string) string {
		if opts.allowMissingRequired {
			return envOrDefault(keys, "")
		}
		return requireAnyEnv(t, keys...)
	}

	tenancyOCID := required("OCI_TENANCY_OCID", "TF_VAR_tenancy_ocid")
	region := required("OCI_REGION", "TF_VAR_region")
	compartmentOCID := required("OCI_COMPARTMENT_OCID", "TF_VAR_compartment_ocid")
	workerOpsAD := required("WORKER_OPS_AD", "OCI_WORKER_OPS_AD", "TF_VAR_worker_ops_ad")
	workerOpsImageID := required("WORKER_OPS_IMAGE_ID", "WORKER_OPS_IMAGE_CUSTOM_ID", "OCI_WORKER_OPS_IMAGE_ID", "TF_VAR_worker_ops_image_custom_id")
	sshPublicKey := loadSSHPublicKey(t, !opts.includeDefaults)

	// var userOCID string
	var profile string
	switch auth {
	case "api_key":
		profile = envOrDefault([]string{"OCI_CONFIG_FILE_PROFILE", "OCI_CLI_PROFILE", "TF_VAR_oci_profile"}, "DEFAULT")
	case "security_token":
		profile = requireAnyEnv(t, "OCI_CONFIG_FILE_PROFILE", "OCI_CLI_PROFILE", "TF_VAR_oci_profile")
	default:
		profile = envOrDefault([]string{"OCI_CONFIG_FILE_PROFILE", "OCI_CLI_PROFILE", "TF_VAR_oci_profile"}, "")
	}

	vars := map[string]interface{}{}
	setIfNotEmpty(vars, "oci_auth", auth)
	setIfNotEmpty(vars, "tenancy_ocid", tenancyOCID)
	setIfNotEmpty(vars, "region", region)
	setIfNotEmpty(vars, "compartment_ocid", compartmentOCID)
	// setIfNotEmpty(vars, "current_user_ocid", userOCID)
	setIfNotEmpty(vars, "oci_profile", profile)
	setIfNotEmpty(vars, "ssh_public_key", sshPublicKey)
	setIfNotEmpty(vars, "worker_ops_ad", workerOpsAD)
	setIfNotEmpty(vars, "worker_ops_image_custom_id", workerOpsImageID)

	if opts.includeDefaults {
		vars["create_bastion"] = false
		vars["create_bv_high"] = false
		vars["create_fss"] = false
		vars["create_lustre"] = false
		vars["create_operator"] = false
		vars["create_policies"] = false
		vars["deploy_to_oke_from_orm"] = false
		vars["install_amd_device_metrics_exporter"] = false
		vars["install_grafana"] = false
		vars["install_grafana_dashboards"] = false
		vars["install_monitoring"] = false
		vars["install_node_problem_detector_kube_prometheus_stack"] = false
		vars["install_nvidia_dcgm_exporter"] = false
		vars["setup_alerting"] = false
		vars["worker_cpu_enabled"] = false
		vars["worker_gpu_enabled"] = false
		vars["worker_ops_pool_size"] = 1
		vars["worker_rdma_enabled"] = false
	}

	return vars
}

func newTerraformOptions(t *testing.T, overrides map[string]interface{}) *terraform.Options {
	t.Helper()

	varFiles := varFilesFromEnv()
	baseOptions := baseVarsOptions{
		includeDefaults:      len(varFiles) == 0,
		allowMissingRequired: len(varFiles) > 0,
	}
	vars := mergeVars(baseVars(t, baseOptions), overrides)

	options := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: terraformDir(),
		Vars:         vars,
		NoColor:      true,
	})
	options.MaxRetries = getMaxRetries()
	options.TimeBetweenRetries = getTimeBetweenRetries()
	if len(varFiles) > 0 {
		options.VarFiles = varFiles
	}

	return options
}

// getMaxRetries returns the maximum number of retries for Terraform operations.
// Configurable via TERRATEST_MAX_RETRIES environment variable.
func getMaxRetries() int {
	if val := os.Getenv("TERRATEST_MAX_RETRIES"); val != "" {
		if retries, err := strconv.Atoi(val); err == nil && retries >= 0 {
			return retries
		}
	}
	return defaultMaxRetries
}

// getTimeBetweenRetries returns the duration to wait between retries.
// Configurable via TERRATEST_RETRY_SLEEP_SECONDS environment variable.
func getTimeBetweenRetries() time.Duration {
	if val := os.Getenv("TERRATEST_RETRY_SLEEP_SECONDS"); val != "" {
		if seconds, err := strconv.Atoi(val); err == nil && seconds >= 0 {
			return time.Duration(seconds) * time.Second
		}
	}
	return defaultTimeBetweenRetries
}

func mergeVars(base map[string]interface{}, overrides map[string]interface{}) map[string]interface{} {
	merged := map[string]interface{}{}
	for key, value := range base {
		merged[key] = value
	}
	for key, value := range overrides {
		merged[key] = value
	}
	return merged
}

func envOrDefault(keys []string, fallback string) string {
	for _, key := range keys {
		if value, ok := os.LookupEnv(key); ok && strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return fallback
}

func requireAnyEnv(t *testing.T, keys ...string) string {
	t.Helper()
	for _, key := range keys {
		if value, ok := os.LookupEnv(key); ok && strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	t.Fatalf("missing required environment variable (one of: %s)", strings.Join(keys, ", "))
	return ""
}

func loadSSHPublicKey(t *testing.T, required bool) string {
	t.Helper()

	if key := envOrDefault([]string{"SSH_PUBLIC_KEY", "TF_VAR_ssh_public_key"}, ""); key != "" {
		return key
	}

	if path := envOrDefault([]string{"SSH_PUBLIC_KEY_PATH", "TF_VAR_ssh_public_key_path"}, ""); path != "" {
		content, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("failed to read SSH public key file: %v", err)
		}
		return strings.TrimSpace(string(content))
	}

	if required {
		t.Fatalf("missing SSH public key; set SSH_PUBLIC_KEY, SSH_PUBLIC_KEY_PATH, TF_VAR_ssh_public_key or TF_VAR_ssh_public_key_path")
	}
	return ""
}

func requireStateHasPrefix(t *testing.T, resources []string, prefix string) {
	t.Helper()
	for _, resource := range resources {
		if strings.HasPrefix(resource, prefix) {
			return
		}
	}
	t.Fatalf("expected state to include resource with prefix %q, got: %v", prefix, resources)
}

func skipUnlessEnv(t *testing.T, key string) {
	t.Helper()
	value := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	if value != "1" && value != "true" && value != "yes" {
		t.Fatalf("missing required flag %s=1 to run this test", key)
	}
}

func uniqueName(base string) string {
	return fmt.Sprintf("%s-%s", base, strings.ToLower(random.UniqueId()))
}

func terraformStateList(t *testing.T, options *terraform.Options) []string {
	t.Helper()

	out, err := terraform.RunTerraformCommandAndGetStdoutE(t, options, "state", "list")
	if err != nil {
		t.Fatalf("failed to list terraform state: %v", err)
	}

	lines := strings.Split(strings.TrimSpace(out), "\n")
	var resources []string
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" {
			resources = append(resources, trimmed)
		}
	}
	return resources
}

func varFilesFromEnv() []string {
	raw := strings.TrimSpace(os.Getenv("TFVARS_FILE"))
	if raw == "" {
		raw = strings.TrimSpace(os.Getenv("TFVARS_FILES"))
	}
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	var files []string
	for _, part := range parts {
		trimmed := strings.TrimSpace(part)
		if trimmed != "" {
			files = append(files, resolveVarFilePath(trimmed))
		}
	}
	return files
}

func resolveVarFilePath(path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	absPath, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return absPath
}

func setIfNotEmpty(vars map[string]interface{}, key, value string) {
	trimmed := strings.TrimSpace(value)
	if trimmed != "" {
		vars[key] = trimmed
	}
}

// isValidOCID checks if a string matches the OCI OCID format.
// Format: ocid1.<resource-type>.<realm>.[region][.future-use].<unique-id>
func isValidOCID(s string) bool {
	return strings.HasPrefix(s, "ocid1.") && strings.Count(s, ".") >= 4
}
