package test

import (
	"crypto/tls"
	"encoding/base64"
	"fmt"
	"testing"
	"time"

	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

// TestMonitoring validates the monitoring stack deployment via Helm.
func TestMonitoring(t *testing.T) {
	skipUnlessEnv(t, "RUN_MONITORING_TESTS")

	options := newTerraformOptions(t, map[string]interface{}{
		"install_monitoring":                                  true,
		"install_node_problem_detector_kube_prometheus_stack": true,
		"install_grafana":                                     true,
		"install_grafana_dashboards":                          true,
		"install_nvidia_dcgm_exporter":                        false,
		"install_amd_device_metrics_exporter":                 false,
		"preferred_kubernetes_services":                       "internal",
		"setup_alerting":                                      false,
	})

	defer terraform.Destroy(t, options)
	terraform.InitAndApply(t, options)

	resources := terraformStateList(t, options)

	// Verify core monitoring components
	requireStateHasPrefix(t, resources, "helm_release.prometheus")
	requireStateHasPrefix(t, resources, "helm_release.node-problem_detector")
	requireStateHasPrefix(t, resources, "helm_release.grafana")

	// Verify Grafana dashboards ConfigMaps
	requireStateHasPrefix(t, resources, "kubernetes_config_map_v1.grafana_dashboard")

	// Verify Grafana login if URL is available
	grafanaURL := terraform.Output(t, options, "grafana_url")
	if grafanaURL != "" {
		grafanaPassword := terraform.Output(t, options, "grafana_admin_password")
		require.NotEmpty(t, grafanaPassword, "grafana_admin_password should not be empty")
		verifyGrafanaLogin(t, grafanaURL, "admin", grafanaPassword)
	}
}

// verifyGrafanaLogin checks that Grafana API is accessible with the given credentials.
func verifyGrafanaLogin(t *testing.T, baseURL, username, password string) {
	t.Helper()

	tlsConfig := &tls.Config{InsecureSkipVerify: true}
	loginURL := fmt.Sprintf("%s/login", baseURL)
	apiURL := fmt.Sprintf("%s/api/org", baseURL)

	// Retry up to 30 times with 10 second intervals (5 minutes total)
	maxRetries := 30
	sleepBetweenRetries := 10 * time.Second

	// First check that Grafana login page is responding
	http_helper.HttpGetWithRetryWithCustomValidation(
		t,
		loginURL,
		tlsConfig,
		maxRetries,
		sleepBetweenRetries,
		func(statusCode int, body string) bool {
			return statusCode == 200
		},
	)

	// Now verify authentication works
	authHeader := "Basic " + base64.StdEncoding.EncodeToString([]byte(username+":"+password))
	http_helper.HTTPDoWithRetryWithOptions(
		t,
		http_helper.HttpDoOptions{
			Method:    "GET",
			Url:       apiURL,
			TlsConfig: tlsConfig,
			Headers: map[string]string{
				"Authorization": authHeader,
			},
		},
		200, // expected status code
		maxRetries,
		sleepBetweenRetries,
	)

	t.Logf("Grafana login successful at %s", baseURL)
}
