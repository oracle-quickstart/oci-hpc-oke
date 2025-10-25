# Using Cluster Autoscaler with Cluster Networks

This guide explains how to configure Cluster Autoscaler to automatically scale nodes in an OKE Cluster Network. While Cluster Autoscaler does not directly support [Cluster Networks](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/managingclusternetworks.htm), it can manage [Instance Pools](https://docs.oracle.com/en-us/iaas/Content/Compute/Concepts/instancemanagement.htm#Instance). Since each Cluster Network has an associated Instance Pool, you can configure autoscaling by targeting the Instance Pool.

## Overview

Cluster Autoscaler automatically adjusts the number of nodes in your cluster based on workload demands. When configured with a Cluster Network's Instance Pool, it provides:
- Automatic scale-up when pods cannot be scheduled due to insufficient resources
- Automatic scale-down when nodes are underutilized
- Cost optimization by running only the required number of nodes
- Seamless integration with RDMA-enabled GPU workloads

## Prerequisites

- OKE cluster with a Cluster Network deployed
- kubectl configured with cluster-admin access
- OCI CLI installed (for retrieving Instance Pool ID)
- Understanding of Instance Principals or OCI API authentication
- Appropriate IAM policies for Cluster Autoscaler

## Procedure

### Step 1: Get the Instance Pool ID

Retrieve the Instance Pool ID associated with your Cluster Network.

You can retrieve the Instance Pool ID using either the OCI CLI or the OCI Console.

#### Option A: Using OCI CLI

```bash
CLUSTER_NETWORK_ID=<your-cluster-network-id>

oci compute-management cluster-network get --cluster-network-id $CLUSTER_NETWORK_ID | jq -r '.data["instance-pools"][0].id'
```

This command returns the OCID of the Instance Pool associated with your Cluster Network.

**Example output:**

```
ocid1.instancepool.oc1.phx.aaaaaaaxxxxxx
```

#### Option B: Using the OCI Console

1. Navigate to **Menu > Compute > Cluster Networks**
2. Click on your Cluster Network name
3. Under **Instance Pools**, click on the Instance Pool name
4. Copy the OCID displayed on the Instance Pool details page

### Step 2: Configure Cluster Autoscaler

Configure Cluster Autoscaler to use the Instance Pool ID from Step 1. In the deployment manifest, update the `--nodes` parameter with your Instance Pool OCID.

The `--nodes` parameter format is: `--nodes=<min>:<max>:<instance-pool-ocid>`

- **min**: Minimum number of nodes (e.g., 0 or 1)
- **max**: Maximum number of nodes (e.g., 10)
- **instance-pool-ocid**: The OCID from Step 1

Example configuration snippet:

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

### Step 3: Deploy Cluster Autoscaler

Deploy Cluster Autoscaler using the complete manifest below. This example uses [Instance Principals](https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/callingservicesfrominstances.htm) for authentication.

> [!IMPORTANT]
> - Replace `{{ image tag }}` with the correct image tag for your region and Kubernetes version
> - Replace the Instance Pool OCID in the `--nodes` parameter
> - Find available images in [Step 4b of the OCI documentation](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengusingclusterautoscaler_topic-Working_with_the_Cluster_Autoscaler.htm#contengusingclusterautoscaler_topic-Working_with_the_Cluster_Autoscaler-step-copy-CA-config-file)


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

Save the manifest to a file (e.g., `cluster-autoscaler.yaml`) and apply it:

```bash
kubectl apply -f cluster-autoscaler.yaml
```

### Step 4: Verify Deployment

Check that Cluster Autoscaler is running:

```bash
kubectl get deployment cluster-autoscaler -n kube-system
```

**Example output:**

```
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
cluster-autoscaler   1/1     1            1           2m
```

View the Cluster Autoscaler logs to confirm it's configured correctly:

```bash
kubectl logs -n kube-system deployment/cluster-autoscaler --tail=50
```

## Disabling or Removing Cluster Autoscaler

To temporarily disable Cluster Autoscaler, scale the deployment to zero replicas:

```bash
kubectl scale deployment cluster-autoscaler -n kube-system --replicas=0
```

To completely remove Cluster Autoscaler:

```bash
kubectl delete -f cluster-autoscaler.yaml
```

> [!WARNING]
> Removing Cluster Autoscaler will stop automatic scaling. Manual intervention will be required to adjust node count.
