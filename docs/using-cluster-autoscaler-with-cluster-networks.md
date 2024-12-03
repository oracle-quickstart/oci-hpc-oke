Using Cluster Autoscaler with Cluster Networks
=========

You can configure the Cluster Autoscaler to work with Cluster Networks. The current implementation of the Cluster Autoscaler on OKE doesn't directly support [Cluster Networks](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/managingclusternetworks.htm), but it supports [Instance Pools](https://docs.oracle.com/en-us/iaas/Content/Compute/Concepts/instancemanagement.htm#Instance). Because each Cluster Network has an Instance Pool associated with it, we can use the Instance Pool to configure autoscaling.

1. Get the ID of the Instace Pool associated with your Cluster Network.

You can either use the OCI CLI or the web console to get the Instance Pool ID associated with your Cluster Network.

**Using OCI CLI**

```sh
CLUSTER_NETWORK_ID=<your cluster network ID>

oci compute-management cluster-network get --cluster-network-id $CLUSTER_NETWORK_ID | jq -r '.data["instance-pools"][0].id'
```

**Using the web console**

Go to Menu > Compute > Cluster Networks > "Your Cluster".

Under Instace Pools, click on the name of your Instance Pool. You can find the OCID of your Instance Pool in this page.


2. Configure Cluster Autoscaler to use the Instance Pool.

```yaml
...
      containers:
        - image: iad.ocir.io/oracle/oci-cluster-autoscaler:{{ image tag }}
          name: cluster-autoscaler
          command:
            - ./cluster-autoscaler
            - --cloud-provider=oci
            - --nodes=1:10:ocid1.instancepool.oc1.phx.aaaaaaaaqdxy35acq32zjfvk55qkwwctxhsprmz633k62q
```

Exmaple manifest using [Instance Principals](https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/callingservicesfrominstances.htm) for authentication. Make sure you have the correct image tag for your region and Kubernetes version. You can find the available regions/images in step 4b [here.](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengusingclusterautoscaler_topic-Working_with_the_Cluster_Autoscaler.htm#contengusingclusterautoscaler_topic-Working_with_the_Cluster_Autoscaler-step-copy-CA-config-file)


```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
  name: cluster-autoscaler
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
  - apiGroups: ["storage.k8s.io"]
    resources: ["csidrivers", "csistoragecapacities"]
    verbs: ["watch", "list"]
  - apiGroups: [""]
    resources: ["events", "endpoints"]
    verbs: ["create", "patch"]
  - apiGroups: [""]
    resources: ["pods/eviction"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["pods/status"]
    verbs: ["update"]
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["endpoints"]
    resourceNames: ["cluster-autoscaler"]
    verbs: ["get", "update"]
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["watch", "list", "get"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["watch", "list", "get", "patch", "update"]
  - apiGroups: [""]
    resources:
      - "pods"
      - "services"
      - "replicationcontrollers"
      - "persistentvolumeclaims"
      - "persistentvolumes"
    verbs: ["watch", "list", "get"]
  - apiGroups: ["extensions"]
    resources: ["replicasets", "daemonsets"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["policy"]
    resources: ["poddisruptionbudgets"]
    verbs: ["watch", "list"]
  - apiGroups: ["apps"]
    resources: ["statefulsets", "replicasets", "daemonsets"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses", "csinodes", "csistoragecapacities", "csidrivers"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["batch", "extensions"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "patch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["create"]
  - apiGroups: ["coordination.k8s.io"]
    resourceNames: ["cluster-autoscaler"]
    resources: ["leases"]
    verbs: ["get", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["create","list","watch"]
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames:
      - "cluster-autoscaler-status"
      - "cluster-autoscaler-priority-expander"
    verbs: ["delete", "get", "update", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: kube-system

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    app: cluster-autoscaler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
    spec:
      serviceAccountName: cluster-autoscaler
      containers:
        - image: iad.ocir.io/oracle/oci-cluster-autoscaler:{{ image tag }}
          name: cluster-autoscaler
          command:
            - ./cluster-autoscaler
            - --v=5
            - --logtostderr=true
            - --cloud-provider=oci
            - --nodes=0:10:ocid1.instancepool.oc1.phx.aaaaaaaaqdxy35acq32zjfvkybjmvlbdgj6q3m55qkwwctxhsprmz633k62q
            - --scale-down-delay-after-add=10m
            - --scale-down-unneeded-time=10m
            - --namespace=kube-system
          imagePullPolicy: "Always"
          env:
            - name: OCI_USE_INSTANCE_PRINCIPAL
              value: "true"
            - name: OCI_SDK_APPEND_USER_AGENT
              value: "oci-oke-cluster-autoscaler"
```
