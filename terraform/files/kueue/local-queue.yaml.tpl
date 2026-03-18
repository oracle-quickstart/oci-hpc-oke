apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: ${flavor_name}
  namespace: ${namespace}
  annotations:
    kueue.x-k8s.io/default-queue: "true"
spec:
  clusterQueue: ${flavor_name}
