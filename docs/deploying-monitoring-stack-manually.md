# Manual Deployment Guide: Prometheus & Grafana Stack with Dashboards and Alerts

This guide provides step-by-step instructions to deploy the same Prometheus and Grafana monitoring stack outside of Terraform, including custom dashboards and alerts for GPU/RDMA workloads on Kubernetes.

> **Note:** If you deployed the monitoring stack using the Terraform stack, the monitoring stack is already installed and configured. You do not need to follow the instructions below.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Step 1: Prepare Your Environment](#step-1-prepare-your-environment)
- [Step 2: Deploy kube-prometheus-stack](#step-2-deploy-kube-prometheus-stack)
- [Step 3: Deploy NVIDIA DCGM Exporter ServiceMonitor](#step-3-deploy-nvidia-dcgm-exporter-servicemonitor)
- [Step 3b: Deploy AMD Device Metrics Exporter](#step-3b-deploy-amd-device-metrics-exporter)
- [Step 4: Deploy Node Problem Detector](#step-4-deploy-node-problem-detector)
- [Step 5: Deploy Custom Grafana Dashboards](#step-5-deploy-custom-grafana-dashboards)
- [Step 6: Deploy Grafana Alert Rules](#step-6-deploy-grafana-alert-rules)
- [Step 7: Deploy OKE ONS Webhook (Optional)](#step-7-deploy-oke-ons-webhook-optional)
- [Step 8: Deploy OCI Metrics Exporter (Optional)](#step-8-deploy-oci-metrics-exporter-optional)
- [Step 9: Access Grafana](#step-9-access-grafana)
- [Step 10: Verify the Deployment](#step-10-verify-the-deployment)
- [Updating an Existing Deployment](#updating-an-existing-deployment)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

## Overview

This deployment includes:

- **kube-prometheus-stack**: Complete monitoring solution with Prometheus, Grafana, and exporters
- **NVIDIA DCGM Exporter**: GPU metrics collection for NVIDIA GPUs
- **AMD Device Metrics Exporter**: GPU metrics collection for AMD GPUs (MI300X and MI355X)
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
cd oci-hpc-oke || exit
```

**Note**: All subsequent commands in this guide assume you're running them from the repository root directory unless otherwise specified.

### 1.2 Create Monitoring Namespace

```bash
kubectl create namespace monitoring
```

### 1.3 Set Environment Variables

```bash
export MONITORING_NAMESPACE="monitoring"

# Set amd, nvidia, or mixed to control vendor-specific NPD and alert deployment
export GPU_VENDOR="amd"

case "${GPU_VENDOR}" in
  amd|nvidia|mixed) ;;
  *) echo "GPU_VENDOR must be amd, nvidia, or mixed" >&2; exit 1 ;;
esac
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
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 16)
export GRAFANA_ADMIN_PASSWORD

# Display the password (save this in a secure location!)
echo "Grafana admin password: ${GRAFANA_ADMIN_PASSWORD}"
```

**Important**: Keep this password secure! You'll need it to log into Grafana.

### 2.2 Install kube-prometheus-stack

The repository stores the kube-prometheus values as a Terraform template. Render a manual values file by removing the Terraform conditional markers:

```bash
sed -e '/^%{ if /d' -e '/^%{ endif }/d' \
  terraform/files/kube-prometheus/values.yaml.tftpl \
  > /tmp/kube-prometheus-values.yaml
```

Validate the generated YAML:

```bash
helm template kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace ${MONITORING_NAMESPACE} \
  --values /tmp/kube-prometheus-values.yaml \
  --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}" \
  >/dev/null
```

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace ${MONITORING_NAMESPACE} \
  --values /tmp/kube-prometheus-values.yaml \
  --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}" \
  --create-namespace \
  --wait
```

The generated values enable the node-exporter textfile collector used by NPD freshness metrics.

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
kube-prometheus-stack-grafana-0                             4/4     Running   0          2m
kube-prometheus-stack-kube-state-metrics-557fd457c6-nqskx   1/1     Running   0          2m
kube-prometheus-stack-operator-57df9db49c-2h4nv             1/1     Running   0          2m
kube-prometheus-stack-prometheus-node-exporter-7lzms        1/1     Running   0          2m
prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   0          2m
```

Confirm node exporter has the NPD textfile collector argument:

```bash
kubectl get daemonset -n ${MONITORING_NAMESPACE} \
  kube-prometheus-stack-prometheus-node-exporter \
  -o json | jq -r '.spec.template.spec.containers[0].args[]' | \
  grep -- '--collector.textfile.directory=/host/root/var/lib/node_exporter/textfile_collector'
```

## Step 3: Deploy NVIDIA DCGM Exporter ServiceMonitor

**Note**: This step is only required if you have NVIDIA GPU nodes in your cluster with the NvidiaGpuOperator OKE addon enabled. The NVIDIA GPU Operator addon deploys the DCGM exporter DaemonSet automatically in the `gpu-operator` namespace. This step adds a ServiceMonitor so Prometheus can scrape its metrics.

### 3.1 Locate the ServiceMonitor Manifest

The ServiceMonitor manifest is available at `terraform/files/nvidia-dcgm-exporter-service-monitor/service-monitor.yaml`.

### 3.2 Apply the ServiceMonitor

```bash
kubectl apply -f terraform/files/nvidia-dcgm-exporter-service-monitor/service-monitor.yaml
```

### 3.3 Verify the ServiceMonitor

```bash
# Verify ServiceMonitor is created
kubectl get servicemonitor -n gpu-operator nvidia-dcgm-exporter

# Check DCGM exporter pods are running (deployed by NVIDIA GPU Operator)
kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter
```

## Step 3b: Deploy AMD Device Metrics Exporter

**Note**: This step is required for AMD MI300X and MI355X nodes. Skip it on NVIDIA-only clusters.

### 3b.1 Add AMD Device Metrics Exporter Helm Repository

```bash
# Add AMD Device Metrics Exporter Helm repository
helm repo add amd-device-metrics-exporter https://rocm.github.io/device-metrics-exporter

# Update repositories
helm repo update
```

### 3b.2 Review and Customize Values

The values file is located at `terraform/files/amd-device-metrics-exporter/values.yaml`. Key configurations:

- **ServiceMonitor**: Enabled with relabelings for OCI-specific labels
- **Node affinity**: Targets `BM.GPU.MI300X.8`, `BM.GPU.MI355X-v1.8`, and `BM.GPU.MI355X.8`
- **Tolerations**: Configured to run on GPU nodes with taints
- **Service**: Exposes metrics on port 5000
- **Image**: Uses `docker.io/rocm/device-metrics-exporter:v1.5.0`

### 3b.3 Install AMD Device Metrics Exporter

```bash
helm upgrade --install amd-device-metrics-exporter \
  amd-device-metrics-exporter/device-metrics-exporter-charts \
  --version v1.5.0 \
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

NPD uses separate AMD and NVIDIA releases. Run the AMD command when `GPU_VENDOR` is `amd` or `mixed`. Run the NVIDIA command when `GPU_VENDOR` is `nvidia` or `mixed`.

AMD:

```bash
helm upgrade --install gpu-rdma-node-problem-detector-amd \
  oci://ghcr.io/deliveryhero/helm-charts/node-problem-detector \
  --version 2.4.1 \
  --namespace ${MONITORING_NAMESPACE} \
  --values terraform/files/node-problem-detector/values.yaml \
  --values terraform/files/node-problem-detector/values-amd.yaml \
  --wait
```

NVIDIA:

```bash
helm upgrade --install gpu-rdma-node-problem-detector-nvidia \
  oci://ghcr.io/deliveryhero/helm-charts/node-problem-detector \
  --version 2.4.1 \
  --namespace ${MONITORING_NAMESPACE} \
  --values terraform/files/node-problem-detector/values.yaml \
  --values terraform/files/node-problem-detector/values-nvidia.yaml \
  --wait
```

The base values contain the protected wrapper, image, logs, and freshness metrics. The vendor values select the applicable checks, node shapes, intervals, concurrency, and timeouts.

### 4.2 Verify Node Problem Detector

```bash
# Check if node problem detector pods are running
kubectl get pods -n ${MONITORING_NAMESPACE} \
  -l 'app.kubernetes.io/name in (gpu-rdma-node-problem-detector-amd,gpu-rdma-node-problem-detector-nvidia)'

# Check metrics endpoint
kubectl get servicemonitor -n ${MONITORING_NAMESPACE} | grep node-problem-detector

# Confirm the pulled image and digest
kubectl get pods -n ${MONITORING_NAMESPACE} \
  -l 'app.kubernetes.io/name in (gpu-rdma-node-problem-detector-amd,gpu-rdma-node-problem-detector-nvidia)' \
  -o json | jq -r '.items[] |
    [.metadata.name, .spec.nodeName, .spec.containers[0].image,
     .status.containerStatuses[0].imageID] | @tsv'
```

## Step 5: Deploy Custom Grafana Dashboards

The repository includes pre-configured dashboards for:
- **Common**: Kubernetes API server, CoreDNS, Kubelet, Pods, PVs, Prometheus, Scheduling
- **GPU**: Cluster metrics, Command Center, GPU health, GPU metrics, and host metrics for AMD and NVIDIA clusters

### 5.1 Deploy Kubernetes Dashboards

```bash
# Set the path to the dashboards directory (adjust if needed)
DASHBOARD_PATH="terraform/files/grafana/dashboards"

# Deploy each common dashboard as a ConfigMap
for dashboard in "${DASHBOARD_PATH}"/common/*.json; do
  kubectl create configmap "dashboard-$(basename "$dashboard" .json)" \
    --from-file="$(basename "$dashboard")=${dashboard}" \
    --namespace ${MONITORING_NAMESPACE} \
    --dry-run=client -o yaml | \
  kubectl label -f - --dry-run=client -o yaml --local grafana_dashboard=1 | \
  kubectl annotate -f - --dry-run=client -o yaml --local grafana_dashboard_folder="Kubernetes" | \
  kubectl apply -f -
done
```

### 5.2 Deploy GPU Dashboards (if applicable)

The source GPU Health dashboard contains both vendor-specific panels. Render it for the `GPU_VENDOR` selected in Step 1.3 before creating its ConfigMap. This uses the same panel filtering and stat-panel layout as Terraform.

```bash
# Render the vendor-specific GPU Health dashboard
RENDERED_DASHBOARD_DIR=$(mktemp -d)
cleanup_rendered_dashboards() {
  rm -rf "${RENDERED_DASHBOARD_DIR}"
}
trap cleanup_rendered_dashboards EXIT

if ! jq -e --arg vendor "${GPU_VENDOR}" '
  .panels |= map(
    select(
      (.id != 7 or $vendor != "amd") and
      (.id != 23 or $vendor != "nvidia")
    )
  )
  | .panels = (
      .panels
      | to_entries
      | map(
          if .value.type == "stat" then
            .value.gridPos.x = ((.key % 8) * 3)
            | .value.gridPos.y = (((.key / 8) | floor) * 3)
          else
            .
          end
          | .value
        )
    )
' "${DASHBOARD_PATH}/gpu/gpu-health-status.json" \
  > "${RENDERED_DASHBOARD_DIR}/gpu-health-status.json"; then
  cleanup_rendered_dashboards
  trap - EXIT
  exit 1
fi

# Deploy each GPU dashboard as a ConfigMap
for dashboard in "${DASHBOARD_PATH}"/gpu/*.json; do
  dashboard_file="${dashboard}"
  if [ "$(basename "${dashboard}")" = "gpu-health-status.json" ]; then
    dashboard_file="${RENDERED_DASHBOARD_DIR}/gpu-health-status.json"
  fi

  kubectl create configmap "dashboard-$(basename "$dashboard" .json)" \
    --from-file="$(basename "$dashboard")=${dashboard_file}" \
    --namespace "${MONITORING_NAMESPACE}" \
    --dry-run=client -o yaml | \
  kubectl label -f - --dry-run=client -o yaml --local grafana_dashboard=1 | \
  kubectl annotate -f - --dry-run=client -o yaml --local grafana_dashboard_folder="GPU Nodes" | \
  kubectl apply -f -
done

cleanup_rendered_dashboards
trap - EXIT
```

### 5.3 Verify Dashboards

```bash
# List all dashboard ConfigMaps
kubectl get configmaps -n ${MONITORING_NAMESPACE} -l grafana_dashboard=1

# Show the vendor-specific GPU Health panels that were deployed
kubectl get configmap dashboard-gpu-health-status \
  -n "${MONITORING_NAMESPACE}" -o json | \
jq '.data["gpu-health-status.json"] | fromjson |
  [.panels[] | select(.id == 7 or .id == 23) | {id, title}]'
```

The result must contain only panel 23 for AMD, only panel 7 for NVIDIA, or both panels for a mixed-vendor cluster.

## Step 6: Deploy Grafana Alert Rules

The repository includes alert rules for:
- GPU ECC errors
- GPU bad pages
- GPU row remapping
- GPU bus issues
- GPU PCIe issues
- GPU count mismatches
- GPU fabric manager issues
- GPU Xid errors
- NVLink speed issues
- DCGM health issues
- NVIDIA IMEX issues
- RDMA link issues
- RDMA link flapping
- RDMA VF route issues
- RDMA VF counter issues
- RDMA RTTCC issues
- RDMA WPA authentication
- Node PCIe errors
- OCA version issues
- CPU profile issues
- NPD checks that return Unknown
- NPD checks that stop updating

### 6.1 Deploy Alert Rules

```bash
# Set the path to the alerts directory (adjust if needed)
ALERTS_PATH="terraform/files/grafana/alerts"

# Deploy only the common and vendor-applicable alert files
case "${GPU_VENDOR}" in
  amd)
    kubectl delete configmap -n ${MONITORING_NAMESPACE} \
      alert-dcgm-health alert-gpu-fabric-manager alert-gpu-imex \
      alert-gpu-row-remap alert-gpu-xid alert-nvlink-speed \
      alert-rdma-vf-counters alert-rdma-vf-routes \
      alert-npd-delete-amd-alerts --ignore-not-found
    ;;
  nvidia)
    kubectl delete configmap -n ${MONITORING_NAMESPACE} \
      alert-gpu-bad-pages alert-npd-delete-nvidia-alerts \
      --ignore-not-found
    ;;
  mixed)
    kubectl delete configmap -n ${MONITORING_NAMESPACE} \
      alert-npd-delete-amd-alerts alert-npd-delete-nvidia-alerts \
      --ignore-not-found
    ;;
esac

for alert in "${ALERTS_PATH}"/*.yaml; do
  alert_name=$(basename "${alert}")

  case "${GPU_VENDOR}:${alert_name}" in
    amd:dcgm-health.yaml|amd:gpu-fabric-manager.yaml|amd:gpu-imex.yaml|amd:gpu-row-remap.yaml|amd:gpu-xid.yaml|amd:nvlink-speed.yaml|amd:rdma-vf-counters.yaml|amd:rdma-vf-routes.yaml|amd:npd-delete-amd-alerts.yaml)
      continue
      ;;
    nvidia:gpu-bad-pages.yaml|nvidia:npd-delete-nvidia-alerts.yaml)
      continue
      ;;
    mixed:npd-delete-amd-alerts.yaml|mixed:npd-delete-nvidia-alerts.yaml)
      continue
      ;;
  esac

  kubectl create configmap "alert-${alert_name%.yaml}" \
    --from-file="${alert_name}=${alert}" \
    --namespace ${MONITORING_NAMESPACE} \
    --dry-run=client -o yaml | \
  kubectl label -f - --dry-run=client -o yaml --local grafana_alert=1 | \
  kubectl apply -f -
done
```

The single-vendor cleanup files remove stale file-provisioned rules left by an older generic deployment. Mixed-vendor clusters skip both cleanup files and retain both vendors' rules.

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
GRAFANA_PASSWORD_B64=$(kubectl get secret -n ${MONITORING_NAMESPACE} kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}")
export GRAFANA_PASSWORD_B64

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

## Step 8: Deploy OCI Metrics Exporter (Optional)

The OCI Metrics Exporter enables ingestion of OCI Metrics into Grafana.

Prerequisites:
- [OCI Stream](https://docs.oracle.com/en-us/iaas/Content/Streaming/Concepts/streamingoverview.htm)
- [Service Connector Hub connection](https://docs.oracle.com/en-us/iaas/Content/connector-hub/managingconnectors.htm) configured to export OCI Metrics for the namespaces (`oci_blockstore`, `oci_fastconnect`, `oci_filestorage`, `oci_internet_gateway`, `oci_lustrefilesystem`, `oci_nat_gateway`, `oci_service_gateway`, `oci_vcn`, `oci_dynamic_routing_gateway`) to the created OCI Stream.
- IAM permissions:
  - to allow the OKE instances to use OCI Streaming in the compartment
  - to allow the OKE instances to read all the resources in the compartment
  - to allow the OCI Service Connector Hub to read from OCI Metrics
  - to allow the OCI Service Connector Hub to push to OCI Streaming

**Note**: This step is optional and only applicable if you're running on Oracle Cloud Infrastructure and want to configure Prometheus to scrape the OCI Metrics.

### 8.1 Prerequisites for OCI Metrics Exporter

1. **OCI Stream**: Create an OCI Stream
   - Navigate to **Analytics & AI → Messaging** → **Streaming** in OCI Console
   - Create a new stream (e.g., `oci-metrics-stream`)
   - Configure the stream to use the existing stream pool (`DefaultPool`)
   - Set appropiate retention period (1h) and number of partitions (1)
   - Note the `Stream OCID`

2. **Required Permissions**: 

  The dynamic group containing your OKE nodes needs permissions to read all the resources from the compartment:
    
    ```
    Allow dynamic-group <your-dynamic-group> to use stream-family in compartment <compartment-name>
    Allow dynamic-group <your-dynamic-group> to read all-resources in compartment <compartment-name>
    ```

  The permissions required for OCI Service Connector Hub connection to push OCI Metrics to OCI Streaming:

    ```
    Allow any-user to read metrics in tenancy where all {request.principal.type = 'serviceconnector', request.principal.compartment.id = '<compartment_OCID>'}
    Allow any-user to use stream-push in compartment id <target_stream_compartment_OCID> where all {request.principal.type='serviceconnector', request.principal.compartment.id='<compartment_OCID>'}
    ```

3. **Service Connector Hub Connection**: Ensure SCH Connection is configured to pull metrics from OCI metrics and push them to OCI Streaming
   - Navigate to **Analytics & AI → Messaging** → **Connectors** in OCI Console.
   - Create a new connector (e.g., `oci-metrics-connector`).
   - Set the connector source as `Monitoring`.
   - Configure the Monitoring source compartment and namespaces: `oci_blockstore`, `oci_fastconnect`, `oci_filestorage`, `oci_internet_gateway`, `oci_lustrefilesystem`, `oci_nat_gateway`, `oci_service_gateway`, `oci_vcn`, `oci_dynamic_routing_gateway`.
   - Set the connector target as `Streaming`. 
   - Configure the created Stream as the target stream.
   - Click `Create`.
   - Ensure the connector is active and there is no error at source.

### 8.2 Install the OCI Metrics Exporter

The OCI Metrics Exporter chart is available at `terraform/files/oci-metrics-exporter/`.

**Set required environment variables:**

```bash
# Set your OCI Streaming OCID
export STREAM_OCID="ocid1.stream.oc1.region.xxxxx"  # Replace with your actual OCI Streaming OCID
```

**Install the OCI Metrics Exporter:**

```bash
helm upgrade --install oci-metrics-exporter terraform/files/oci-metrics-exporter \
  --namespace ${MONITORING_NAMESPACE} \
  --set telegraf.streamOcid="${STREAM_OCID}" \
  --wait
```

### 8.3 Verify OCI Metrics Exporter

```bash
# Check if the oci metrics exporter pod is running
kubectl get pods -n ${MONITORING_NAMESPACE} -l  app.kubernetes.io/name=oci-metrics-exporter

# Check exporter logs
kubectl logs -n ${MONITORING_NAMESPACE} -l  app.kubernetes.io/name=oci-metrics-exporter

# Check the metrics
kubectl port-forward -n ${MONITORING_NAMESPACE} deploy/oci-metrics-exporter 9273:9273
curl localhost:9273/metrics
```

### 8.4 Create the Grafana Dashboards for the OCI Metrics

```bash
# Deploy each OCI metrics dashboards as a ConfigMap
for dashboard in "${DASHBOARD_PATH}"/oci/*.json; do
  kubectl create configmap "dashboard-$(basename "$dashboard" .json)" \
    --from-file="$(basename "$dashboard")=${dashboard}" \
    --namespace ${MONITORING_NAMESPACE} \
    --dry-run=client -o yaml | \
  kubectl label -f - --dry-run=client -o yaml --local grafana_dashboard=1 | \
  kubectl annotate -f - --dry-run=client -o yaml --local grafana_dashboard_folder="OCI Metrics" | \
  kubectl apply -f -
done
```

### 8.5 How OCI Metrics Exporter Works

The `oci-metrics-exporter` chart deploys a Telegraf-based pod that converts OCI-native metrics into Prometheus metrics for Prometheus and Grafana.

The end-to-end flow is:

1. **OCI services publish metrics into OCI Monitoring**
   OCI services such as Block Volume, File Storage, VCN, DRG, and FastConnect first publish their native metrics to the OCI Monitoring service.

2. **Service Connector Hub forwards selected namespaces to OCI Streaming**
   The Service Connector Hub (SCH) connector is configured with `Monitoring` as the source and `Streaming` as the target. It continuously copies the OCI Monitoring metrics for the selected namespaces into the OCI Stream you created earlier.

3. **The exporter consumes the OCI Stream**
   Inside the pod, Telegraf runs a custom `streaming` input that reads from the configured `STREAM_OCID` using instance principal authentication. The input script decodes the streamed payloads, groups samples into short time windows, and applies the appropriate aggregation for each metric before passing the results to Telegraf.

4. **The exporter also polls OCI Monitoring directly**
   A second custom Telegraf input queries the OCI Monitoring API directly for metrics that are collected as API queries instead of being supplied through SCH streaming (for the metrics with a high sampling frequency). In this chart, that includes the configured Object Storage metrics such as request rates, latency, object count, and stored bytes.

5. **Telegraf filters and enriches the metrics**
   The collected metrics are filtered down to the metric names supported by this chart, then enriched with OCI resource metadata and freeform tags. This enrichment step can add useful labels such as OCI display names, cluster/controller tags, and resolved hostnames for attached compute resources.

6. **Prometheus scrapes the exporter**
   Telegraf exposes the final metrics through its Prometheus endpoint on port `9273`. The chart creates a Kubernetes `Service` and `ServiceMonitor`, so Prometheus scrapes `/metrics` and stores the OCI metrics together with the rest of the cluster telemetry.

In short: OCI Monitoring is the source of truth for the cloud-service metrics, Service Connector Hub moves selected metrics into OCI Streaming, and `oci-metrics-exporter` consumes, normalizes, enriches, and exposes them in Prometheus format.


## Step 9: Access Grafana

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
   --set grafana.ingress.hosts[0]=grafana.${INGRESS_IP}.endpoint.oci-hpc.ai \
   --set grafana.ingress.tls[0].hosts[0]=grafana.${INGRESS_IP}.endpoint.oci-hpc.ai \
   --set grafana.ingress.tls[0].secretName=grafana-tls \
   --wait
   ```

6. Confirm the ingress resource was created.

   ```bash
   kubectl get ingress -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/instance=kube-prometheus-stack

   # Sample output
   # NAME                            CLASS     HOSTS                              ADDRESS           PORTS     AGE
   # kube-prometheus-stack-grafana   contour   grafana.${INGRESS_IP}.endpoint.oci-hpc.ai     ${INGRESS_IP}     80, 443   5m28s
   ```

7. Access Grafana at `https://grafana.${INGRESS_IP}.endpoint.oci-hpc.ai`

## Step 10: Verify the Deployment

### 10.1 Check Prometheus Targets

1. Port-forward Prometheus:
   ```bash
   kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-prometheus 9090:9090
   ```

2. Open http://localhost:9090/targets and verify all targets are UP:
   - node-exporter
   - nvidia-dcgm-exporter (if NVIDIA GPUs, in gpu-operator namespace)
   - device-metrics-exporter (if AMD GPUs)
   - node-problem-detector
   - kubelet
   - kube-state-metrics

### 10.2 Verify Dashboards in Grafana

1. Log into Grafana
2. Navigate to **Dashboards**
3. Verify folders exist:
   - **Kubernetes** (with common dashboards)
   - **GPU Nodes** (with GPU-specific dashboards)
4. Open a dashboard and verify data is displayed

### 10.3 Verify Alerts in Grafana

1. In Grafana, go to **Alerting** → **Alert rules**
2. Verify alert rules are loaded from the ConfigMaps
3. Check that alerts are in the **Alerts** folder

### 10.4 Test Metrics Collection

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

# Query NPD wrapper status and freshness metrics
kubectl exec -n ${MONITORING_NAMESPACE} prometheus-kube-prometheus-stack-prometheus-0 \
  -- promtool query instant http://localhost:9090 'oke_npd_check_status_code'

kubectl exec -n ${MONITORING_NAMESPACE} prometheus-kube-prometheus-stack-prometheus-0 \
  -- promtool query instant http://localhost:9090 'oke_npd_check_last_run_timestamp_seconds'
```

## Updating an Existing Deployment

If the monitoring stack is already deployed (either via Terraform or a previous manual installation), you can update individual components by re-running the `helm upgrade` commands with updated values files or chart versions.

### Important: Terraform-Managed Deployments

If the stack was originally deployed via Terraform, be aware that manually upgrading Helm releases will cause **Terraform state drift**. On the next `terraform apply`, Terraform may attempt to revert your manual changes.

You have two options:

1. **Update via Terraform (recommended)**: Modify Terraform variables (e.g., `prometheus_stack_chart_version`) and re-run `terraform apply`.

2. **Switch to manual management**: Remove the Helm releases from Terraform state before managing them manually:
   ```bash
   # Remove monitoring resources from Terraform state
   terraform state rm 'helm_release.prometheus[0]'
   terraform state rm 'helm_release.amd_device_metrics_exporter[0]'
   terraform state rm 'helm_release.node_problem_detector_amd[0]'
   terraform state rm 'helm_release.node_problem_detector_nvidia[0]'
   terraform state rm 'helm_release.oke-ons-webhook[0]'

   # Remove dashboard and alert ConfigMaps from state
   terraform state rm 'kubernetes_config_map_v1.grafana_common_dashboards'
   terraform state rm 'kubernetes_config_map_v1.grafana_gpu_dashboards'
   terraform state rm 'kubernetes_config_map_v1.grafana_alerts'
   ```

   **Note**: Only remove resources that exist in your state. Run `terraform state list | grep -E 'helm_release|grafana'` first to see what's managed.

### Check Current State

Before updating, inspect the currently deployed releases:

```bash
# List all monitoring Helm releases
helm list -n monitoring

# View the current values for a specific release
helm get values kube-prometheus-stack -n monitoring

# Compare with the values file in the repository
diff <(helm get values kube-prometheus-stack -n monitoring) /tmp/kube-prometheus-values.yaml
```

### Update kube-prometheus-stack

Use `--reuse-values` to preserve existing settings (e.g., Grafana password, ingress configuration) while applying changes from the values file:

```bash
helm repo update

helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace ${MONITORING_NAMESPACE} \
  --values /tmp/kube-prometheus-values.yaml \
  --reuse-values \
  --wait
```

To pin a chart version, list the versions available from the configured repository, set `PROMETHEUS_STACK_CHART_VERSION`, and add `--version "${PROMETHEUS_STACK_CHART_VERSION}"` to the upgrade command:

```bash
helm search repo prometheus-community/kube-prometheus-stack --versions
export PROMETHEUS_STACK_CHART_VERSION="replace-with-selected-version"
```

### Update NVIDIA DCGM Exporter ServiceMonitor

The DCGM exporter DaemonSet is managed by the NvidiaGpuOperator OKE addon. To update the ServiceMonitor:

```bash
kubectl apply -f terraform/files/nvidia-dcgm-exporter-service-monitor/service-monitor.yaml
```

### Update AMD Device Metrics Exporter

```bash
helm repo update

helm upgrade amd-device-metrics-exporter \
  amd-device-metrics-exporter/device-metrics-exporter-charts \
  --version v1.5.0 \
  --namespace ${MONITORING_NAMESPACE} \
  --values terraform/files/amd-device-metrics-exporter/values.yaml \
  --wait
```

### Update Node Problem Detector

Upgrade each release present in the cluster.

AMD:

```bash
helm upgrade --install gpu-rdma-node-problem-detector-amd \
  oci://ghcr.io/deliveryhero/helm-charts/node-problem-detector \
  --version 2.4.1 \
  --namespace ${MONITORING_NAMESPACE} \
  --values terraform/files/node-problem-detector/values.yaml \
  --values terraform/files/node-problem-detector/values-amd.yaml \
  --wait
```

NVIDIA:

```bash
helm upgrade --install gpu-rdma-node-problem-detector-nvidia \
  oci://ghcr.io/deliveryhero/helm-charts/node-problem-detector \
  --version 2.4.1 \
  --namespace ${MONITORING_NAMESPACE} \
  --values terraform/files/node-problem-detector/values.yaml \
  --values terraform/files/node-problem-detector/values-nvidia.yaml \
  --wait
```

If this is an older installation with the generic `gpu-rdma-node-problem-detector` release, install and verify the appropriate vendor release before uninstalling the generic release:

```bash
helm uninstall gpu-rdma-node-problem-detector -n ${MONITORING_NAMESPACE}
```

### Update OKE ONS Webhook

```bash
helm upgrade oke-ons-webhook terraform/files/oke-ons-webhook \
  --namespace ${MONITORING_NAMESPACE} \
  --reuse-values \
  --wait
```

### Update Dashboards and Alerts

Dashboards and alerts are deployed as ConfigMaps, not Helm releases. Re-running the `kubectl apply` loops will update them in place:

```bash
# Update common dashboards
DASHBOARD_PATH="terraform/files/grafana/dashboards"

for dashboard in "${DASHBOARD_PATH}"/common/*.json; do
  kubectl create configmap "dashboard-$(basename "$dashboard" .json)" \
    --from-file="$(basename "$dashboard")=${dashboard}" \
    --namespace ${MONITORING_NAMESPACE} \
    --dry-run=client -o yaml | \
  kubectl label -f - --dry-run=client -o yaml --local grafana_dashboard=1 | \
  kubectl annotate -f - --dry-run=client -o yaml --local grafana_dashboard_folder="Kubernetes" | \
  kubectl apply -f -
done

# Update AMD/NVIDIA GPU dashboards (if applicable)
for dashboard in "${DASHBOARD_PATH}"/gpu/*.json; do
  kubectl create configmap "dashboard-$(basename "$dashboard" .json)" \
    --from-file="$(basename "$dashboard")=${dashboard}" \
    --namespace ${MONITORING_NAMESPACE} \
    --dry-run=client -o yaml | \
  kubectl label -f - --dry-run=client -o yaml --local grafana_dashboard=1 | \
  kubectl annotate -f - --dry-run=client -o yaml --local grafana_dashboard_folder="GPU Nodes" | \
  kubectl apply -f -
done
```

Update alert rules by rerunning the vendor-aware loop from Step 6.1.

The Grafana sidecar will automatically detect ConfigMap changes and reload the updated dashboards and alerts.

### Rolling Back

If an upgrade causes issues, roll back to the previous Helm release revision:

```bash
# View release history
helm history kube-prometheus-stack -n monitoring

# Roll back to the previous revision
helm rollback kube-prometheus-stack -n monitoring

# Or roll back to a specific revision number
helm rollback kube-prometheus-stack 1 -n monitoring
```

The same `helm history` and `helm rollback` commands work for all Helm-managed components, including `gpu-rdma-node-problem-detector-amd`, `gpu-rdma-node-problem-detector-nvidia`, `oke-ons-webhook`, and `amd-device-metrics-exporter`.

### Verify the Update

After updating, verify the deployment is healthy:

```bash
# Check all pods are running
kubectl get pods -n ${MONITORING_NAMESPACE}

# Check the updated release versions
helm list -n monitoring

# Verify Prometheus targets are UP (port-forward first)
kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-prometheus 9090:9090
# Then open http://localhost:9090/targets

# Verify dashboards are loaded in Grafana
kubectl get configmaps -n ${MONITORING_NAMESPACE} -l grafana_dashboard=1

# Verify alert rules are loaded
kubectl get configmaps -n ${MONITORING_NAMESPACE} -l grafana_alert=1
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
1. Verify DCGM exporter pods are running (deployed by NVIDIA GPU Operator):
   ```bash
   kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter -o wide
   ```

2. Check if ServiceMonitor exists:
   ```bash
   kubectl get servicemonitor -n gpu-operator nvidia-dcgm-exporter
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
   kubectl get nodes -L node.kubernetes.io/instance-type | \
     grep -E 'BM.GPU.MI300X.8|BM.GPU.MI355X-v1.8|BM.GPU.MI355X.8'
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
     repository: iad.ocir.io/idxzjcdglx2s/oke-npd
     tag: v1.35.2-5
   ```

3. Check the vendor-specific release and DaemonSet:
   ```bash
   helm list -n ${MONITORING_NAMESPACE} | grep node-problem-detector
   kubectl get daemonset -n ${MONITORING_NAMESPACE} | grep node-problem-detector
   ```

4. Inspect a failed check's protected host log on the affected node:
   ```bash
   sudo sed -n '1,160p' /var/log/oke-npd/latest-gpu-count.log
   ```

5. Treat `Unknown` separately from a confirmed failure. `Unknown` means the check could not produce a reliable result. A stale-check alert means the wrapper heartbeat stopped updating.

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

# Uninstall Node Problem Detector releases that exist in the cluster
helm uninstall gpu-rdma-node-problem-detector-amd -n ${MONITORING_NAMESPACE}
helm uninstall gpu-rdma-node-problem-detector-nvidia -n ${MONITORING_NAMESPACE}

# Delete DCGM Exporter ServiceMonitor (if deployed)
kubectl delete servicemonitor nvidia-dcgm-exporter -n gpu-operator --ignore-not-found

# Uninstall AMD Device Metrics Exporter (if deployed)
helm uninstall amd-device-metrics-exporter -n ${MONITORING_NAMESPACE}

# Uninstall OKE ONS Webhook (if deployed)
helm uninstall oke-ons-webhook -n ${MONITORING_NAMESPACE}

# Uninstall the OKE Metrics Exporter (if deployed)
helm uninstall oci-metrics-exporter -n ${MONITORING_NAMESPACE}

# Uninstall kube-prometheus-stack
helm uninstall kube-prometheus-stack -n ${MONITORING_NAMESPACE}

# Delete contour Ingress Controller (if deployed)
helm uninstall contour -n projectcontour

# Delete the Cluster Issuer
kubectl delete -f terraform/files/cert-manager/cluster-issuer.yaml

# Delete cert-manager (OCI CLI is required)
oci ce cluster disable-addon --addon-name CertManager --cluster-id "<oke-cluster-ocid>" --is-remove-existing-add-on true --force

# Delete PVCs (optional, this will delete all stored metrics and dashboards)
kubectl delete pvc -n ${MONITORING_NAMESPACE} --all

# Delete namespace
kubectl delete namespace ${MONITORING_NAMESPACE}

```
