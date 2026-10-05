apiVersion: kueue.x-k8s.io/v1beta2
kind: LocalQueue
metadata:
  name: ${flavor_name}
  namespace: ${namespace}
spec:
  clusterQueue: ${flavor_name}
