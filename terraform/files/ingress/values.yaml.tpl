envoy:
  defaultInitContainers:
    initConfig:
      resourcesPreset: "micro"
  shutdownManager:
    resourcesPreset: "micro"
  resourcesPreset: "none"
  resources:
    requests:
      cpu: "250m"
      memory: "256Mi"
      ephemeral-storage: "50Mi"
    limits:
      cpu: "1.0"
      memory: "2048Mi"
      ephemeral-storage: "2Gi"
  service:
    externalTrafficPolicy: Cluster
    networkPolicy:
      enabled: false
    annotations:
      oci.oraclecloud.com/load-balancer-type: "lb"
      service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
      service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "${min_bw}"
      service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "${max_bw}"
      service.beta.kubernetes.io/oci-load-balancer-security-list-management-mode: "None"
      oci.oraclecloud.com/initial-freeform-tags-override: '{"state_id": "${state_id}", "application": "contour", "role": "contour_ingress_lb"}'
      oci.oraclecloud.com/oci-network-security-groups: "${lb_nsg_id}"

contour:
  resourcesPreset: "none"
  resources:
    requests:
      cpu: "250m"
      memory: "256Mi"
      ephemeral-storage: "50Mi"
    limits:
      cpu: "1.0"
      memory: "2048Mi"
      ephemeral-storage: "2Gi"
  certgen:
    networkPolicy:
      enabled: false
  networkPolicy:
    enabled: false
  ingressClass:
    name: "contour"

useCertManager: false