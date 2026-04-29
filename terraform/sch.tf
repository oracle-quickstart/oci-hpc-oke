# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

resource "oci_streaming_stream" "oci_metrics_exporter" {
  count = alltrue([var.install_monitoring, var.setup_oci_metrics_exporter, var.install_node_problem_detector_kube_prometheus_stack]) ? 1 : 0

  name = "oci-metrics-exporter-stream-${local.state_id}"

  compartment_id = var.compartment_ocid

  partitions         = 1
  retention_in_hours = 24

  lifecycle {
    ignore_changes = [defined_tags]
  }
}


resource "oci_sch_service_connector" "oci_metrics_exporter" {
  count = alltrue([var.install_monitoring, var.setup_oci_metrics_exporter, var.install_node_problem_detector_kube_prometheus_stack]) ? 1 : 0

  compartment_id = var.compartment_ocid
  display_name   = "oci-metrics-exporter-${local.state_id}"

  source {
    kind = "monitoring"

    monitoring_sources {
      compartment_id = var.compartment_ocid

      namespace_details {
        kind = "selected"
        dynamic "namespaces" {
          for_each = ["oci_blockstore", "oci_fastconnect", "oci_filestorage", "oci_internet_gateway", "oci_lustrefilesystem", "oci_nat_gateway", "oci_service_gateway", "oci_vcn", "oci_dynamic_routing_gateway"] # "gpu_infrastructure_health", "rdma_infrastructure_health"
          content {
            metrics {
              kind = "all"
            }
            namespace = namespaces.value
          }
        }
      }
    }
  }

  target {
    kind      = "streaming"
    stream_id = oci_streaming_stream.oci_metrics_exporter[0].id
  }

  description = "Service connector hub used to export OCI metrics to OCI Streaming"

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

