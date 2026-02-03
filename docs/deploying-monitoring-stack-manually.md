# Manual Deployment Guide: Prometheus & Grafana Stack with Dashboards and Alerts

This guide provides step-by-step instructions to deploy the same Prometheus and Grafana monitoring stack outside of Terraform, including custom dashboards and alerts for GPU/RDMA workloads on Kubernetes.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Step 1: Prepare Your Environment](#step-1-prepare-your-environment)
- [Step 2: Deploy kube-prometheus-stack](#step-2-deploy-kube-prometheus-stack)
- [Step 3: Deploy NVIDIA DCGM Exporter](#step-3-deploy-nvidia-dcgm-exporter)
- [Step 3b: Deploy AMD Device Metrics Exporter (Alternative for AMD GPUs)](#step-3b-deploy-amd-device-metrics-exporter-alternative-for-amd-gpus)
- [Step 4: Deploy Node Problem Detector](#step-4-deploy-node-problem-detector)
- [Step 5: Deploy Custom Grafana Dashboards](#step-5-deploy-custom-grafana-dashboards)
- [Step 6: Deploy Grafana Alert Rules](#step-6-deploy-grafana-alert-rules)
- [Step 7: Deploy OKE ONS Webhook (Optional)](#step-7-deploy-oke-ons-webhook-optional)
- [Step 8: Access Grafana](#step-8-access-grafana)
- [Step 9: Verify the Deployment](#step-9-verify-the-deployment)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

## Overview

This deployment includes:

- **kube-prometheus-stack**: Complete monitoring solution with Prometheus, Grafana, and exporters
- **NVIDIA DCGM Exporter**: GPU metrics collection for NVIDIA GPUs
- **AMD Device Metrics Exporter**: GPU metrics collection for AMD GPUs (MI300X)
- **Node Problem Detector**: Custom health checks for GPU, RDMA, and PCIe issues
- **Custom Dashboards**: Pre-configured dashboards for Kubernetes, GPU nodes (NVIDIA/AMD), and cluster metrics
- **Alert Rules**: Grafana alert rules for GPU health, RDMA issues, and node problems
- **OKE ONS Webhook** (Optional): Integration with Oracle Cloud Infrastructure Notifications Service for alert delivery

## Prerequisites

Before starting, ensure you have:

1. **Kubernetes cluster** (v1.24+) with kubectl access
2. **Helm 3** installed (v3.8.0+)
3. **kubectl** configured to access your cluster
4. **Sufficient cluster resources**:
   - CPU nodes to run the monitoring pods. GPU nodes are configured with a taint by default which will prevent monitoring pods from launching.
   - At least 4 CPU cores available
   - At least 8GB RAM available
   - Storage class for persistent volumes (e.g., `oci-bv`)
5. **Namespace**: The monitoring namespace (default: `monitoring`)

Optional:
- Contour Ingress Controller (for public access)
- Cert-Manager (for TLS certificates)
- Load balancer capability (for external access)
- OCI Notifications Service (ONS) Topic OCID (for alert notifications via OKE ONS Webhook)
- Instance Principal authentication configured for OKE nodes (for OKE ONS Webhook)


## Step 1: Prepare Your Environment

### 1.1 Clone the Repository

First, clone the [oci-hpc-oke](https://github.com/oracle-quickstart/oci-hpc-oke.git) repository to access the configuration files referenced throughout this guide:

```bash
# Clone the repository
git clone https://github.com/oracle-quickstart/oci-hpc-oke.git

# Change to the repository directory
cd oci-hpc-oke
```

**Note**: All subsequent commands in this guide assume you're running them from the repository root directory unless otherwise specified.

### 1.2 Create Monitoring Namespace

```bash
kubectl create namespace monitoring
```

### 1.3 Set Environment Variables

```bash
export MONITORING_NAMESPACE="monitoring"
```

### 1.4 Add Helm Repositories

```bash
# Add Prometheus Community Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

# Update repositories
helm repo update
```

## Step 2: Deploy kube-prometheus-stack

### 2.1 Generate Grafana Admin Password

Before installing, generate a strong random password for Grafana instead of using the default `prom-operator`:

```bash
# Generate a strong random password (16 characters)
export GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 16)

# Display the password (save this in a secure location!)
echo "Grafana admin password: ${GRAFANA_ADMIN_PASSWORD}"
```

**Important**: Keep this password secure! You'll need it to log into Grafana.

### 2.2 Install kube-prometheus-stack

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace ${MONITORING_NAMESPACE} \
  --values terraform/files/kube-prometheus/values.yaml \
  --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}" \
  --create-namespace \
  --wait
```

**Note**: The repository contains both `values.yaml` (for manual deployments) and `values.yaml.tftpl` (Terraform template for automated deployments). Use the `values.yaml` file for manual installations as shown above.

**Note**: The password is also stored in a Kubernetes secret and can be retrieved later with:
```bash
kubectl get secret -n ${MONITORING_NAMESPACE} kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

### 2.3 Verify Installation

```bash
# Check if all pods are running
kubectl get pods -n ${MONITORING_NAMESPACE}

# Example output
NAME                                                        READY   STATUS    RESTARTS   AGE
dcgm-exporter-bsdgd                                         1/1     Running   0          125m
gpu-rdma-node-problem-detector-8hxcv                        1/1     Running   0          121m
kube-prometheus-stack-grafana-0                             4/4     Running   0          128m
kube-prometheus-stack-kube-state-metrics-557fd457c6-nqskx   1/1     Running   0          128m
kube-prometheus-stack-operator-57df9db49c-2h4nv             1/1     Running   0          128m
kube-prometheus-stack-prometheus-node-exporter-7lzms        1/1     Running   0          128m
kube-prometheus-stack-prometheus-node-exporter-gbkcm        1/1     Running   0          128m
kube-prometheus-stack-prometheus-node-exporter-rlndc        1/1     Running   0          128m
oke-ons-webhook-789cb49d9f-jjr8q                            1/1     Running   0          51m
prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   0          128m
```

## Step 3: Deploy NVIDIA DCGM Exporter

**Note**: This step is only required if you have NVIDIA GPU nodes in your cluster.

### 3.1 Locate DCGM Exporter Chart

The DCGM exporter chart is available in the repository at `terraform/files/nvidia-dcgm-exporter/`.

### 3.2 Review and Customize Values

The values file is located at `terraform/files/nvidia-dcgm-exporter/oke-values.yaml`. Key configurations:

- **ServiceMonitor**: Enabled with relabelings for OCI-specific labels
- **NodeSelector**: Targets nodes with `nvidia.com/gpu: "true"`
- **Tolerations**: Configured to run on GPU nodes with taints
- **Custom Metrics**: Configured to collect GPU health metrics

### 3.3 Install DCGM Exporter

```bash
helm upgrade --install dcgm-exporter terraform/files/nvidia-dcgm-exporter \
  --namespace ${MONITORING_NAMESPACE} \
  --values terraform/files/nvidia-dcgm-exporter/oke-values.yaml \
  --wait
```

### 3.4 Verify DCGM Exporter

```bash
# Check if DCGM exporter pods are running on GPU nodes
kubectl get pods -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=dcgm-exporter

# Verify ServiceMonitor is created
kubectl get servicemonitor -n ${MONITORING_NAMESPACE} dcgm-exporter
```

## Step 3b: Deploy AMD Device Metrics Exporter (Alternative for AMD GPUs)

**Note**: This step is only required if you have AMD GPU nodes (e.g., MI300X) in your cluster. Skip this if you deployed NVIDIA DCGM Exporter in Step 3.

### 3b.1 Add AMD Device Metrics Exporter Helm Repository

```bash
# Add AMD GPU Operator Helm repository
helm repo add amd-gpu-operator https://amdgpu-helm-charts.github.io/amd-gpu-operator/

# Update repositories
helm repo update
```

### 3b.2 Review and Customize Values

The values file is located at `terraform/files/amd-device-metrics-exporter/values.yaml`. Key configurations:

- **ServiceMonitor**: Enabled with relabelings for OCI-specific labels
- **NodeSelector**: Targets nodes with `node.kubernetes.io/instance-type: BM.GPU.MI300X.8`
- **Tolerations**: Configured to run on GPU nodes with taints
- **Service**: Exposes metrics on port 5000
- **Image**: Uses `docker.io/rocm/device-metrics-exporter:v1.2.1`

### 3b.3 Install AMD Device Metrics Exporter

```bash
helm upgrade --install amd-device-metrics-exporter amd-gpu-operator/device-metrics-exporter \
  --namespace ${MONITORING_NAMESPACE} \
  --values terraform/files/amd-device-metrics-exporter/values.yaml \
  --wait
```

### 3b.4 Verify AMD Device Metrics Exporter

```bash
# Check if AMD device metrics exporter pods are running on GPU nodes
kubectl get pods -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=device-metrics-exporter

# Verify ServiceMonitor is created
kubectl get servicemonitor -n ${MONITORING_NAMESPACE} device-metrics-exporter
```

## Step 4: Deploy Node Problem Detector

**Note**: This is required for custom GPU/RDMA health checks.

### 4.1 Install Node Problem Detector

```bash
helm upgrade --install gpu-rdma-node-problem-detector oci://ghcr.io/deliveryhero/helm-charts/node-problem-detector --version 2.3.22 \
  --namespace ${MONITORING_NAMESPACE} \
  --values terraform/files/node-problem-detector/values.yaml \
  --wait
```

**Note**: The values file at `terraform/files/node-problem-detector/values.yaml` contains:
- Custom health check scripts for GPU ECC errors, RDMA link issues, PCIe problems
- Node affinity to run only on GPU node types
- ServiceMonitor configuration for Prometheus integration
- `fullnameOverride: "gpu-rdma-node-problem-detector"` to ensure correct naming

### 4.2 Verify Node Problem Detector

```bash
# Check if node problem detector pods are running
kubectl get pods -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=node-problem-detector

# Check metrics endpoint
kubectl get servicemonitor -n ${MONITORING_NAMESPACE} | grep node-problem-detector
```

## Step 5: Deploy Custom Grafana Dashboards

The repository includes pre-configured dashboards for:
- **Common**: Kubernetes API server, CoreDNS, Kubelet, Pods, PVs, Prometheus, Scheduling
- **NVIDIA GPU**: Cluster metrics, Command Center, GPU health, GPU metrics, Host metrics, Node Problem Detector
- **AMD GPU**: Job metrics, GPU metrics, Node metrics, Overview

### 5.1 Deploy Kubernetes Dashboards

```bash
# Set the path to the dashboards directory (adjust if needed)
DASHBOARD_PATH="terraform/files/grafana/dashboards"

# Deploy each common dashboard as a ConfigMap
for dashboard in ${DASHBOARD_PATH}/common/*.json; do
  kubectl create configmap "dashboard-$(basename $dashboard .json)" \
    --from-file="$(basename $dashboard)=${dashboard}" \
    --namespace ${MONITORING_NAMESPACE} \
    --dry-run=client -o yaml | \
  kubectl label -f - --dry-run=client -o yaml --local grafana_dashboard=1 | \
  kubectl annotate -f - --dry-run=client -o yaml --local grafana_dashboard_folder="Kubernetes" | \
  kubectl apply -f -
done
```

### 5.2 Deploy NVIDIA GPU Dashboards (if applicable)

```bash
# Deploy each NVIDIA GPU dashboard as a ConfigMap
for dashboard in ${DASHBOARD_PATH}/nvidia/*.json; do
  kubectl create configmap "dashboard-$(basename $dashboard .json)" \
    --from-file="$(basename $dashboard)=${dashboard}" \
    --namespace ${MONITORING_NAMESPACE} \
    --dry-run=client -o yaml | \
  kubectl label -f - --dry-run=client -o yaml --local grafana_dashboard=1 | \
  kubectl annotate -f - --dry-run=client -o yaml --local grafana_dashboard_folder="GPU Nodes" | \
  kubectl apply -f -
done
```

### 5.3 Deploy AMD GPU Dashboards (if applicable)

```bash
# Deploy each AMD GPU dashboard as a ConfigMap
for dashboard in ${DASHBOARD_PATH}/amd/*.json; do
  kubectl create configmap "dashboard-$(basename $dashboard .json)" \
    --from-file="$(basename $dashboard)=${dashboard}" \
    --namespace ${MONITORING_NAMESPACE} \
    --dry-run=client -o yaml | \
  kubectl label -f - --dry-run=client -o yaml --local grafana_dashboard=1 | \
  kubectl annotate -f - --dry-run=client -o yaml --local grafana_dashboard_folder="GPU Nodes" | \
  kubectl apply -f -
done
```

### 5.4 Verify Dashboards

```bash
# List all dashboard ConfigMaps
kubectl get configmaps -n ${MONITORING_NAMESPACE} -l grafana_dashboard=1
```

## Step 6: Deploy Grafana Alert Rules

The repository includes alert rules for:
- GPU ECC errors
- GPU bad pages
- GPU row remapping
- GPU bus issues
- GPU PCIe issues
- GPU count mismatches
- GPU fabric manager issues
- RDMA link issues
- RDMA link flapping
- RDMA RTTCC issues
- RDMA WPA authentication
- Node PCIe errors
- OCA version issues
- CPU profile issues

### 6.1 Deploy Alert Rules

```bash
# Set the path to the alerts directory (adjust if needed)
ALERTS_PATH="terraform/files/grafana/alerts"

# Deploy each alert rule as a ConfigMap
for alert in ${ALERTS_PATH}/*.yaml; do
  kubectl create configmap "alert-$(basename $alert .yaml)" \
    --from-file="$(basename $alert)=${alert}" \
    --namespace ${MONITORING_NAMESPACE} \
    --dry-run=client -o yaml | \
  kubectl label -f - --dry-run=client -o yaml --local grafana_alert=1 | \
  kubectl apply -f -
done
```

### 6.2 Verify Alert Rules

```bash
# List all alert ConfigMaps
kubectl get configmaps -n ${MONITORING_NAMESPACE} -l grafana_alert=1
```

**Important**: The alerts reference a contact point called `ons-webhook`. You'll need to either:
1. Deploy the OKE ONS webhook service (see Step 7 below)
2. Modify the alert rules to use your own alerting endpoint
3. Configure contact points manually in Grafana UI

## Step 7: Deploy OKE ONS Webhook (Optional)

The OKE ONS Webhook service integrates Grafana alerts with Oracle Cloud Infrastructure (OCI) Notifications Service. It receives alerts from Grafana, processes them, and forwards them to an OCI Notifications Topic for delivery via email, SMS, or other channels.

**Note**: This step is optional and only applicable if you're running on Oracle Cloud Infrastructure and want to send alerts to OCI Notifications Service.

### 7.1 Prerequisites for OKE ONS Webhook

1. **OCI Notifications Topic**: Create an ONS topic in your OCI tenancy
   - Navigate to **Developer Services → Application Integration** → **Notifications** in OCI Console
   - Create a new topic (e.g., `oke-grafana-alerts`)
   - Note the Topic OCID

2. **Instance Principal Authentication**: Ensure your OKE worker nodes have instance principal authentication configured
   - This allows the webhook service to authenticate to OCI services
   - See [OCI documentation](https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/callingservicesfrominstances.htm) for setup

3. **Required Permissions**: The dynamic group containing your OKE nodes needs permissions to publish to the ONS topic:
   ```
   Allow dynamic-group <your-dynamic-group> to use ons-topics in compartment <compartment-name>
   ```

### 7.2 Install OKE ONS Webhook

The webhook chart is available at `terraform/files/oke-ons-webhook/`.

**Set required environment variables:**

```bash
# Get the base64-encoded Grafana admin password
export GRAFANA_PASSWORD_B64=$(kubectl get secret -n ${MONITORING_NAMESPACE} kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}")

# Set your OCI Notifications Topic OCID
export ONS_TOPIC_OCID="ocid1.onstopic.oc1.region.xxxxx"  # Replace with your actual ONS Topic OCID
```

**Install the webhook:**

```bash
helm upgrade --install oke-ons-webhook terraform/files/oke-ons-webhook \
  --namespace ${MONITORING_NAMESPACE} \
  --set deploy.env.ONS_TOPIC_OCID="${ONS_TOPIC_OCID}" \
  --set deploy.env.GRAFANA_INITIAL_PASSWORD="${GRAFANA_PASSWORD_B64}" \
  --set deploy.env.GRAFANA_SERVICE_URL="http://kube-prometheus-stack-grafana" \
  --wait
```

### 7.3 Verify OKE ONS Webhook

```bash
# Check if webhook pod is running
kubectl get pods -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=oke-ons-webhook

# Check webhook logs
kubectl logs -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=oke-ons-webhook

# Verify service is created
kubectl get svc -n ${MONITORING_NAMESPACE} oke-ons-webhook
```

### 7.4 How OKE ONS Webhook Works

The webhook service:

1. **Receives alerts** from Grafana via HTTP POST to `/grafana-webhook`
2. **Processes alerts**:
   - Tracks alert state (firing, resolved) in a local SQLite database
   - Deduplicates alerts and tracks fire counts
   - Aggregates multiple alerts into single notifications
   - Sends daily reminders for long-running alerts
   - Cleans up old alerts automatically
3. **Shortens URLs** using Grafana API for better readability in notifications
4. **Publishes to ONS** topic using Instance Principal authentication
5. **Alert lifecycle management**:
   - New alerts: Immediately notified
   - Ongoing alerts: Counted and tracked
   - Resolved alerts: Final notification sent
   - Old alerts: Automatically cleaned up after 3 days (configurable)

### 7.5 Update Grafana Alert Contact Point

The alert rules deployed in Step 6 already reference the `ons-webhook` contact point. However, you need to verify it's configured correctly in Grafana:

1. Log into Grafana
2. Navigate to **Alerting** → **Contact points**
3. Verify the `ons-webhook` contact point exists with:
   - **Type**: Webhook
   - **URL**: `http://oke-ons-webhook/grafana-webhook`
   - **HTTP Method**: POST

If it doesn't exist, it should be created automatically from the alert rules ConfigMap (`alert-rules.yaml`).

### 7.6 Configure ONS Subscriptions

To receive notifications, create subscriptions on your ONS topic:

1. In OCI Console, navigate to your ONS topic
2. Click **Create Subscription**
3. Choose protocol:
   - **Email**: Enter email addresses
   - **SMS**: Enter phone numbers
   - **Slack**: Use webhook URL
   - **PagerDuty**: Use integration endpoint
4. Confirm subscriptions (email/SMS require confirmation)

### 7.7 Test the Integration

Navigate to https://webhook.site/ and get your unique URL.

Create an **HTTPS** subscription using the unique URL.

Confirm the subscription by opening the URL in the received webhook (e.g., `https://cell1.notification...`). 

Create a test alert in Grafana:

```bash
# Port-forward to Grafana
kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-grafana 3000:80

# Use Grafana UI to create a test alert or trigger an existing alert condition
```

Check if notification is received:
- Check webhook logs for processing
- Verify message appears in OCI Notifications topic
- Confirm notification delivery to subscribed endpoints

## Step 8: Access Grafana

### Option 1: Port Forward (Quick Access)

```bash
# Forward Grafana port to localhost
kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-grafana 3000:80

# Access Grafana at: http://localhost:3000
```

**Login credentials:**
- **Username**: `admin`
- **Password**: Use the password you generated in Step 2.1 (stored in `$GRAFANA_ADMIN_PASSWORD`)

If you forgot the password or need to retrieve it:
```bash
kubectl get secret -n ${MONITORING_NAMESPACE} kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

### Option 2: Ingress with TLS

1. Enable the cert-manager OKE Cluster Add-on

   Follow the instructions [here](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/install-add-on.htm) to enable the cert-manager add-on on an existing cluster.

   Wait until the add-on status is `Ready`.

2. Install the Contour Ingress Controller
   
   ```bash
   helm upgrade --install contour contour --repo https://projectcontour.github.io/helm-charts/ --namespace projectcontour --create-namespace
   ```

   **Note**: 
   - If you want to customize the Ingress Controller LoadBalancer attributes, please refer to the file `terraform/files/ingress/values.yaml.tpl`.

   - All supported annotations can be found in [our documentation](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcreatingloadbalancer_topic-Summaryofannotations.htm).

3. Create a ClusterIssuer for Let's Encrypt.

   ```bash
   kubectl apply -f terraform/files/cert-manager/cluster-issuer.yaml
   ```

4. Get the public IP address of the LoadBalancer associated with the Contour Ingress Controller.

   ```bash
   export INGRESS_IP=$(kubectl get svc -A -l app.kubernetes.io/name=contour  -o json | jq -r '.items[] | select(.spec.type == "LoadBalancer") | .status.loadBalancer.ingress[].ip')
   ```

5. Upgrade the Grafana Deployment to use Ingress.

   ```bash
   helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
   --namespace ${MONITORING_NAMESPACE} \
   --reuse-values \
   --set grafana.ingress.enabled=true \
   --set grafana.ingress.ingressClassName=contour \
   --set grafana.ingress.annotations.'cert-manager\.io\/cluster-issuer'=le-clusterissuer \
   --set grafana.ingress.hosts[0]=grafana.${INGRESS_IP}.sslip.io \
   --set grafana.ingress.tls[0].hosts[0]=grafana.${INGRESS_IP}.sslip.io \
   --set grafana.ingress.tls[0].secretName=grafana-tls \
   --wait
   ```

6. Confirm the ingress resource was created.

   ```bash
   kubectl get ingress -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/instance=kube-prometheus-stack

   # Sample output
   # NAME                            CLASS     HOSTS                              ADDRESS           PORTS     AGE
   # kube-prometheus-stack-grafana   contour   grafana.${INGRESS_IP}.sslip.io     ${INGRESS_IP}     80, 443   5m28s
   ```

7. Access Grafana at `https://grafana.${INGRESS_IP}.sslip.io`

## Step 9: Verify the Deployment

### 9.1 Check Prometheus Targets

1. Port-forward Prometheus:
   ```bash
   kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-prometheus 9090:9090
   ```

2. Open http://localhost:9090/targets and verify all targets are UP:
   - node-exporter
   - dcgm-exporter (if NVIDIA GPUs)
   - device-metrics-exporter (if AMD GPUs)
   - node-problem-detector
   - kubelet
   - kube-state-metrics

### 9.2 Verify Dashboards in Grafana

1. Log into Grafana
2. Navigate to **Dashboards**
3. Verify folders exist:
   - **Kubernetes** (with common dashboards)
   - **GPU Nodes** (with GPU-specific dashboards)
4. Open a dashboard and verify data is displayed

### 9.3 Verify Alerts in Grafana

1. In Grafana, go to **Alerting** → **Alert rules**
2. Verify alert rules are loaded from the ConfigMaps
3. Check that alerts are in the **Alerts** folder

### 9.4 Test Metrics Collection

```bash
# Query Prometheus for NVIDIA GPU metrics (if DCGM is deployed)
kubectl exec -n ${MONITORING_NAMESPACE} prometheus-kube-prometheus-stack-prometheus-0 \
  -- promtool query instant http://localhost:9090 'DCGM_FI_DEV_GPU_TEMP'

# Query Prometheus for AMD GPU metrics (if AMD device metrics exporter is deployed)
kubectl exec -n ${MONITORING_NAMESPACE} prometheus-kube-prometheus-stack-prometheus-0 \
  -- promtool query instant http://localhost:9090 'amd_gpu_temperature'

# Query for node problem detector metrics
kubectl exec -n ${MONITORING_NAMESPACE} prometheus-kube-prometheus-stack-prometheus-0 \
  -- promtool query instant http://localhost:9090 'problem_gauge'
```

## Troubleshooting

### Dashboards Not Appearing

**Issue**: Dashboards don't show up in Grafana

**Solution**:
1. Check if ConfigMaps are created with correct labels:
   ```bash
   kubectl get configmaps -n ${MONITORING_NAMESPACE} -l grafana_dashboard=1
   ```

2. Check Grafana sidecar logs:
   ```bash
   kubectl logs -n ${MONITORING_NAMESPACE} \
     statefulset/kube-prometheus-stack-grafana -c grafana-sc-dashboard
   ```

3. Verify sidecar is enabled in values:
   ```yaml
   grafana:
     sidecar:
       dashboards:
         enabled: true
   ```

### No GPU Metrics (NVIDIA)

**Issue**: NVIDIA GPU metrics are not showing in Prometheus

**Solution**:
1. Verify DCGM exporter pods are running on GPU nodes:
   ```bash
   kubectl get pods -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=dcgm-exporter -o wide
   ```

2. Check if ServiceMonitor exists:
   ```bash
   kubectl get servicemonitor -n ${MONITORING_NAMESPACE} dcgm-exporter
   ```

3. Verify GPU nodes have the label:
   ```bash
   kubectl get nodes -l nvidia.com/gpu=true
   ```

### No GPU Metrics (AMD)

**Issue**: AMD GPU metrics are not showing in Prometheus

**Solution**:
1. Verify AMD device metrics exporter pods are running on GPU nodes:
   ```bash
   kubectl get pods -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=device-metrics-exporter -o wide
   ```

2. Check if ServiceMonitor exists:
   ```bash
   kubectl get servicemonitor -n ${MONITORING_NAMESPACE} device-metrics-exporter
   ```

3. Verify GPU nodes have the correct instance type label:
   ```bash
   kubectl get nodes -l node.kubernetes.io/instance-type=BM.GPU.MI300X.8
   ```

4. Check pod logs for any errors:
   ```bash
   kubectl logs -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=device-metrics-exporter
   ```

### Alerts Not Firing

**Issue**: Alert rules exist but don't fire

**Solution**:
1. Check if ConfigMaps are created with correct labels:
   ```bash
   kubectl get configmaps -n ${MONITORING_NAMESPACE} -l grafana_alert=1
   ```

2. Check Grafana sidecar logs for alerts:
   ```bash
   kubectl logs -n ${MONITORING_NAMESPACE} \
     statefulset/kube-prometheus-stack-grafana -c grafana-sc-alerts
   ```

3. Verify contact point exists in Grafana:
   - Go to **Alerting** → **Contact points**
   - Ensure `ons-webhook` contact point is configured

### Storage Issues

**Issue**: PVCs are pending

**Solution**:
1. Verify storage class exists:
   ```bash
   kubectl get storageclass
   ```

2. Check PVC status:
   ```bash
   kubectl get pvc -n ${MONITORING_NAMESPACE}
   ```

3. Update storage class in values file if needed

### Node Problem Detector Not Running

**Issue**: NPD pods are not starting

**Solution**:
1. Check node affinity matches your GPU node types:
   ```yaml
   affinity:
     nodeAffinity:
       requiredDuringSchedulingIgnoredDuringExecution:
         nodeSelectorTerms:
           - matchExpressions:
               - key: node.kubernetes.io/instance-type
                 operator: In
                 values:
                 - BM.GPU.A100-v2.8
                 # Add your node types here
   ```

2. Verify the custom image is accessible:
   ```yaml
   image:
     repository: iad.ocir.io/hpc_limited_availability/oke-npd
     tag: v0.8.21-1
   ```

### OKE ONS Webhook Issues

**Webhook pod not starting**:
```bash
# Check events
kubectl describe pod -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=oke-ons-webhook

# Check logs
kubectl logs -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=oke-ons-webhook
```

**Instance Principal authentication failing**:
- Verify dynamic group includes your OKE worker nodes
- Check IAM policies allow ONS topic access
- Ensure nodes have correct instance principal configuration

**Alerts not reaching ONS**:
```bash
# Check webhook received the alert
kubectl logs -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=oke-ons-webhook | grep "Received data"

# Check if publishing to ONS succeeded
kubectl logs -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=oke-ons-webhook | grep "Message published"
```

**Grafana token creation failed**:
- The webhook automatically creates a service account token in Grafana
- Check logs for any authentication errors
- Verify `GRAFANA_INITIAL_PASSWORD` is correct and base64-encoded

## Cleanup

To remove the entire monitoring stack:

```bash
# Delete dashboards
kubectl delete configmaps -n ${MONITORING_NAMESPACE} -l grafana_dashboard=1

# Delete alerts
kubectl delete configmaps -n ${MONITORING_NAMESPACE} -l grafana_alert=1

# Uninstall Node Problem Detector
helm uninstall gpu-rdma-node-problem-detector -n ${MONITORING_NAMESPACE}

# Uninstall DCGM Exporter (if deployed)
helm uninstall dcgm-exporter -n ${MONITORING_NAMESPACE}

# Uninstall AMD Device Metrics Exporter (if deployed)
helm uninstall amd-device-metrics-exporter -n ${MONITORING_NAMESPACE}

# Uninstall OKE ONS Webhook (if deployed)
helm uninstall oke-ons-webhook -n ${MONITORING_NAMESPACE}

# Uninstall kube-prometheus-stack
helm uninstall kube-prometheus-stack -n ${MONITORING_NAMESPACE}

# Delete contour Ingress Controller (if deployed)
helm uninstall contour -n projectcontour

# Delete the Cluster Issuer
kubectl delete -f terraform/files/cert-manager/cluster-issuer.yaml

# Delete cert-manager (OCI CLI is required)
oci ce cluster disable-addon --addon-name CertManager --cluster-id {oke-cluster-ocid} --is-remove-existing-add-on true --force

# Delete PVCs (optional, this will delete all stored metrics and dashboards)
kubectl delete pvc -n ${MONITORING_NAMESPACE} --all

# Delete namespace
kubectl delete namespace ${MONITORING_NAMESPACE}

```