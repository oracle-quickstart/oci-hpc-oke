package test

import (
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"testing"
	"time"

	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

// TestMonitoring validates the monitoring stack deployment via Helm.
func TestMonitoring(t *testing.T) {
	skipUnlessEnv(t, "RUN_MONITORING_TESTS")

	options := newTerraformOptions(t, map[string]interface{}{
		"install_monitoring": true,
		"install_node_problem_detector_kube_prometheus_stack": true,
		"install_grafana":               true,
		"install_grafana_dashboards":    true,
		"preferred_kubernetes_services": "internal",
		"setup_alerting":                false,
	})

	defer terraform.Destroy(t, options)
	terraform.InitAndApply(t, options)

	resources := terraformStateList(t, options)

	// Verify core monitoring components
	requireStateHasPrefix(t, resources, "helm_release.prometheus")
	requireStateHasPrefix(t, resources, "helm_release.node_problem_detector_nvidia")
	requireStateHasPrefix(t, resources, "random_password.grafana_admin_password")

	// Verify NVIDIA DCGM Exporter ServiceMonitor
	requireStateHasPrefix(t, resources, "kubectl_manifest.nvidia_dcgm_exporter_service_monitor")

	// Verify Grafana dashboards ConfigMaps
	requireStateHasPrefix(t, resources, "kubernetes_config_map_v1.grafana_common_dashboards")

	// Verify Grafana login if URL is available
	grafanaURL := terraform.Output(t, options, "grafana_url")
	if grafanaURL != "" {
		grafanaPassword := terraform.Output(t, options, "grafana_admin_password")
		require.NotEmpty(t, grafanaPassword, "grafana_admin_password should not be empty")
		verifyGrafanaLogin(t, grafanaURL, "admin", grafanaPassword)
	}
}

// TestMonitoringThanos validates the sharded Prometheus + Thanos deployment: the
// bucket and its policy exist, and Grafana's Prometheus datasource is answered
// by Thanos Query with every shard behind it.
func TestMonitoringThanos(t *testing.T) {
	skipUnlessEnv(t, "RUN_MONITORING_TESTS")

	const shards = 2
	options := newTerraformOptions(t, map[string]interface{}{
		"install_monitoring": true,
		"install_node_problem_detector_kube_prometheus_stack": true,
		"install_grafana":               true,
		"install_grafana_dashboards":    true,
		"preferred_kubernetes_services": "internal",
		"setup_alerting":                false,
		"install_thanos":                true,
		"prometheus_shards":             shards,
	})

	defer terraform.Destroy(t, options)
	terraform.InitAndApply(t, options)

	resources := terraformStateList(t, options)
	requireStateHasPrefix(t, resources, "helm_release.prometheus")
	requireStateHasPrefix(t, resources, "helm_release.thanos")
	requireStateHasPrefix(t, resources, "oci_objectstorage_bucket.thanos")
	requireStateHasPrefix(t, resources, "oci_identity_policy.thanos_objstore")

	grafanaURL := terraform.Output(t, options, "grafana_url")
	if grafanaURL == "" {
		return
	}
	grafanaPassword := terraform.Output(t, options, "grafana_admin_password")
	verifyGrafanaLogin(t, grafanaURL, "admin", grafanaPassword)

	// Only Thanos Query exposes the prometheus_replica external label; with
	// dedup=false every shard shows up as its own replica.
	retry.DoWithRetry(t, "every Prometheus shard is visible through Grafana", 30, 10*time.Second, func() (string, error) {
		series, err := grafanaDatasourceQuery(grafanaURL, "admin", grafanaPassword, "count by (prometheus_replica) (up)")
		if err != nil {
			return "", err
		}
		if len(series) != shards {
			return "", fmt.Errorf("got %d prometheus_replica series through Grafana, want %d", len(series), shards)
		}
		return "", nil
	})
}

// grafanaDatasourceQuery runs an instant query without deduplication through
// Grafana's proxy for the "prometheus" datasource and returns each result's labels.
func grafanaDatasourceQuery(baseURL, username, password, query string) ([]map[string]string, error) {
	params := url.Values{"query": {query}, "dedup": {"false"}}
	req, err := http.NewRequest(http.MethodGet, fmt.Sprintf("%s/api/datasources/proxy/uid/prometheus/api/v1/query?%s", baseURL, params.Encode()), nil)
	if err != nil {
		return nil, err
	}
	req.SetBasicAuth(username, password)
	client := &http.Client{
		Timeout:   30 * time.Second,
		Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}},
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("datasource query %q: HTTP %d", query, resp.StatusCode)
	}
	var body struct {
		Data struct {
			Result []struct {
				Metric map[string]string `json:"metric"`
			} `json:"result"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, err
	}
	labels := make([]map[string]string, 0, len(body.Data.Result))
	for _, r := range body.Data.Result {
		labels = append(labels, r.Metric)
	}
	return labels, nil
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
