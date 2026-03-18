apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata:
  name: ${flavor_name}
spec:
  nodeLabels:
    node.kubernetes.io/instance-type: "${shape}"
    ${gpu_label_key}: "true"
  topologyName: oci-rdma
