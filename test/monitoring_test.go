package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestMonitoringProviderPath(t *testing.T) {
	skipUnlessEnv(t, "RUN_MONITORING_TESTS")

	options := newTerraformOptions(t, map[string]interface{}{
		"install_monitoring": true,
		"install_node_problem_detector_kube_prometheus_stack": true,
		"install_grafana":                     true,
		"install_grafana_dashboards":          true,
		"install_nvidia_dcgm_exporter":        false,
		"install_amd_device_metrics_exporter": false,
		"preferred_kubernetes_services":       "internal",
		"setup_alerting":                      false,
	})

	defer terraform.Destroy(t, options)
	terraform.InitAndApply(t, options)

	resources := terraformStateList(t, options)
	requireStateHasPrefix(t, resources, "helm_release.prometheus")
	requireStateHasPrefix(t, resources, "helm_release.node-problem_detector")
}
