envoy:
  service:
    annotations:
      oci.oraclecloud.com/load-balancer-type: "lb"
      service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
      service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "${min_bw}"
      service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "${max_bw}"
      service.beta.kubernetes.io/oci-load-balancer-security-list-management-mode: "None"
      oci.oraclecloud.com/initial-freeform-tags-override: '{"state_id": "${state_id}", "application": "contour", "role": "contour_ingress_lb"}'
      oci.oraclecloud.com/oci-network-security-groups: "${lb_nsg_id}"