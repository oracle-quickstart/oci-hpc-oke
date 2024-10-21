# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  node_exporter_helm = {
    enabled = true
    operatingSystems = {
      linux  = { enabled = true }
      darwin = { enabled = false }
    }
  }

  node_exporter_extra_args = [
    "--no-collector.cgroups",
    "--collector.ethtool",
    #"--collector.ethtool-include=^(received_pcs_symbol_err_phy|link_down_events_phy|rx_err_lane_.*_phy|rx_corrected_bits_phy|.*err.*)$",
    "--collector.mountstats",
    "--no-collector.qdisc",
    "--no-collector.processes",
    "--no-collector.sysctl",
    # "--collector.sysctl.include=^net.ipv4.conf.(.+).(arp_ignore|arp_announce|rp_filter)$",
    "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+)($|/)",
    "--collector.filesystem.fs-types-exclude=^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs|tmpfs|ramfs|vfat)$"
  ]

  node_exporter_values = {
    podMonitor = {
      enabled = true, attachMetadata = { node = true }
    }
    releaseLabel = true
    prometheus = {
      monitor = {
        attachMetadata   = { node = true }
        selectorOverride = {}
        interval         = "30s"
        scrapeTimeout    = "25s"
        relabelings = [
          {
            sourceLabels = ["__meta_kubernetes_node_label_oke_oraclecloud_com_pool_name"]
            targetLabel  = "worker_pool"
          },
          {
            sourceLabels = ["__meta_kubernetes_node_label_topology_kubernetes_io_zone"]
            targetLabel  = "zone"
          },
          {
            sourceLabels = ["__meta_kubernetes_node_label_oci_oraclecloud_com_fault_domain"]
            targetLabel  = "fault_domain"
          },
          {
            sourceLabels = ["__meta_kubernetes_node_label_node_kubernetes_io_instance_type"]
            targetLabel  = "instance_shape"
          },
          {
            sourceLabels = ["__meta_kubernetes_node_label_oci_oraclecloud_com_host_serial_number"]
            targetLabel  = "host_serial_number"
          }
        ]
      }
    }
    extraArgs = local.node_exporter_extra_args
  }
}