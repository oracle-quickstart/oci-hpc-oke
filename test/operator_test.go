package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestOperatorPath(t *testing.T) {
	skipUnlessEnv(t, "RUN_OPERATOR_TESTS")

	options := newTerraformOptions(t, map[string]interface{}{
		"create_bastion":          true,
		"create_operator":         true,
		"control_plane_is_public": false,
		"install_monitoring":      true,
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
	requireStateHasPrefix(t, resources, "module.kube_prometheus_stack.null_resource.helm_deployment_via_operator")
	requireStateHasPrefix(t, resources, "module.node_problem_detector.null_resource.helm_deployment_via_operator")
}
