apiVersion: kueue.x-k8s.io/v1beta2
kind: ResourceFlavor
metadata:
  name: ${flavor_name}
spec:
  nodeLabels:
    node.kubernetes.io/instance-type: "${shape}"
    ${gpu_label_key}: "true"
  topologyName: oci-rdma
  # GPU nodes are tainted <gpu>=present:NoSchedule. TAS needs this toleration to
  # place pods, and Kueue adds it to the pods it admits.
  tolerations:
  - key: ${gpu_label_key}
    operator: Exists
    effect: NoSchedule
