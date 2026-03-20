apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: ${flavor_name}
spec:
  namespaceSelector: {}
  resourceGroups:
  - coveredResources: ["cpu", "memory", "${gpu_resource}", "ephemeral-storage"]
    flavors:
    - name: ${flavor_name}
      resources:
      - name: cpu
        nominalQuota: "20000"
      - name: memory
        nominalQuota: "102400Gi"
      - name: "${gpu_resource}"
        nominalQuota: "10000"
      - name: ephemeral-storage
        nominalQuota: "12800Gi"
