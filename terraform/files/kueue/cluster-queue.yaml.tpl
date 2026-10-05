apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata:
  name: ${flavor_name}
spec:
  namespaceSelector: {}
  resourceGroups:
  # dra.net/nic and nvidia.com/compute-domain-channel are the DRA deviceClassMappings in values.yaml.
  - coveredResources: ["cpu", "memory", "${gpu_resource}", "dra.net/nic", "nvidia.com/compute-domain-channel", %{ if rdma_vf }"nvidia.com/rdma-vf", %{ endif }"ephemeral-storage"]
    flavors:
    - name: ${flavor_name}
      resources:
      - name: cpu
        nominalQuota: "1000000"
      - name: memory
        nominalQuota: "1000000Ti"
      - name: "${gpu_resource}"
        nominalQuota: "1000000"
      - name: dra.net/nic
        nominalQuota: "1000000"
      - name: nvidia.com/compute-domain-channel
        nominalQuota: "1000000"
%{ if rdma_vf ~}
      - name: nvidia.com/rdma-vf
        nominalQuota: "1000000"
%{ endif ~}
      - name: ephemeral-storage
        nominalQuota: "1000000Ti"
