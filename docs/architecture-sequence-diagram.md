# OCI HPC OKE - Architecture and Sequence Diagrams

Here's how the OKE stack fits together, from creating the cluster and booting workers to running GPU jobs and viewing their metrics. The diagrams follow the Terraform configuration, scripts, and Kubernetes manifests at revision `2548a59da6d3059aeffc1137bf86f8a026d3998a`.

Which pieces run depends on the options you enable. Terraform handles the dependencies between them, so some provisioning steps can run alongside each other. Source links below each diagram point to the files behind the flow.

## Deployment paths and worker pools

The stack has three ways to reach the Kubernetes API. [oke-cluster.tf](../terraform/oke-cluster.tf) selects the path, and [provider.tf](../terraform/provider.tf) sets up the connection.

| Path | Source condition | Kubernetes access |
| --- | --- | --- |
| Operator | `create_bastion && create_operator && !control_plane_is_public && !deploy_to_oke_from_orm` | SSH through the bastion to the operator; remote Helm and kubectl |
| Local providers | `!deploy_from_operator && control_plane_is_public && !deploy_to_oke_from_orm` | Terraform Helm, Kubernetes, and kubectl providers |
| Resource Manager (ORM) | `current_user_ocid != null && deploy_to_oke_from_orm` | Providers use the ORM private endpoint reachable IP |

Each optional component also has its own install settings. Slinky's operator path works a little differently; diagram 10 covers that setup.

The [worker pool definitions](../terraform/oke-workers.tf) pass these modes to `oracle-terraform-modules/oke/oci` version `5.5.1`:

| Pool | Mode and condition |
| --- | --- |
| `oke-system` | Managed `node-pool`; creation enabled, size from `worker_ops_pool_size` |
| `oke-cpu` | Managed `node-pool` when `worker_cpu_enabled` |
| `oke-gpu` | Managed `node-pool` when `worker_gpu_enabled` |
| `oke-rdma` | When enabled and the image is valid: `cluster-network` if `worker_rdma_use_cluster_network`, otherwise `node-pool` with `use_compute_cluster = true` |
| `oke-gmc` | Self-managed `gpu-memory-cluster` when `worker_gmc_enabled`; fabric IDs and scale configuration are passed to the module |

## Sequence Diagrams

### 1. Terraform Apply - Provisioning Overview

An apply brings together the network, cluster, worker pools, storage, and enabled add-ons. You can create a new VCN or use an existing network. Terraform uses the outputs from each resource to connect the pieces as they become available.

```mermaid
sequenceDiagram
    autonumber
    participant User as User / Resource Manager
    participant TF as Terraform
    participant Module as OKE module 5.5.1
    participant OCI as OCI APIs
    participant Storage as OCI File Storage / Lustre
    participant Deploy as Selected Kubernetes deployment path
    participant API as OKE Kubernetes API

    User->>TF: Apply configured stack
    rect rgb(230, 240, 255)
        Note over TF,OCI: Infrastructure configuration
        TF->>Module: VCN, subnets, NSGs, enhanced cluster, bastion and operator settings
        Module->>OCI: Provision resources through the external module
        Module-->>TF: Cluster ID, endpoints, CA and network outputs
    end
    opt FSS or Lustre creation enabled
        TF->>Storage: Create configured file system and access resources
        Storage-->>TF: Mount address and export / file-system information
    end
    rect rgb(230, 255, 240)
        Note over TF,Module: Worker configuration
        TF->>Module: Enabled pools, images, metadata and cloud-init
        Module->>OCI: Provision configured worker capacity
    end
    opt Managed add-ons enabled
        TF->>OCI: Configure selected OKE add-ons
        Note over TF,OCI: Individual add-on readiness gates apply
    end
    opt Kubernetes component conditions satisfied
        TF->>Deploy: Deploy selected charts and manifests
        Deploy->>API: Storage PVs, utilities, scheduling and monitoring resources
    end
    TF-->>User: Apply result
```

Sources: [cluster and module configuration](../terraform/oke-cluster.tf), [workers and cloud-init](../terraform/oke-workers.tf), [managed add-ons and readiness gates](../terraform/oke-addons.tf), [FSS](../terraform/fss.tf), [Lustre](../terraform/lustre.tf).

### 2. Kubernetes Deployment - Operator, Local and ORM Paths

For a private cluster, Terraform connects through the bastion and runs Helm and kubectl on the operator host. Local and ORM deployments use Terraform providers to reach the API directly through their configured endpoint. Each component adds the checks it needs before installation.

```mermaid
sequenceDiagram
    autonumber
    participant TF as Terraform
    participant Bastion as Bastion host
    participant Operator as Operator host
    participant CLI as OCI CLI on Terraform runner
    participant ORM as ORM private endpoint
    participant API as OKE Kubernetes API

    alt deploy_from_operator
        TF->>Bastion: Establish SSH jump connection
        Bastion->>Operator: Forward SSH to operator private IP
        TF->>Operator: Copy local chart if supplied and generated / user values
        Operator->>Operator: Set instance-principal authentication
        loop Up to 30 checks for each prerequisite
            Operator->>API: Check kubeconfig with kubectl cluster-info
            Operator->>Operator: Check Helm installation
        end
        Note over Operator,API: Helper exits if prerequisites remain unavailable
        Operator->>Operator: Run caller pre-deployment commands
        Operator->>API: helm upgrade --install with namespace and values
        Operator->>Operator: Run caller post-deployment commands
    else deploy_from_local or deploy_from_orm
        opt deploy_from_orm
            TF->>ORM: Create private endpoint in control-plane subnet
            TF->>ORM: Resolve reachable IP for private API address
            ORM-->>TF: Reachable IP for provider endpoint
        end
        TF->>CLI: ce cluster generate-token with region and cluster ID
        CLI-->>TF: Kubernetes exec credential
        TF->>API: Providers apply charts and manifests using selected endpoint and CA
        Note over TF,API: ORM uses reachable IP, provider TLS server name uses private endpoint host
    end
```

The Helm helper loads generated values first, then your overrides if you've supplied any. It checks kubeconfig and Helm separately, waiting ten seconds between retries. Each component chooses its own Helm flags, including whether to use `--wait`.

Sources: [deployment selectors](../terraform/oke-cluster.tf), [Helm helper](../terraform/helm-module/helm-deployment.tf), [providers](../terraform/provider.tf), [ORM endpoint](../terraform/orm-private-endpoint.tf).

### 3. Worker Node Boot Sequence

Every worker pool gets the stack's generated cloud-config in place of the module default. It sets up the node, runs the OKE bootstrap, and mounts any enabled storage. Despite its name, `oke-ubuntu-cloud-init.sh` handles both Ubuntu and Oracle Linux.

```mermaid
sequenceDiagram
    autonumber
    participant Node as Worker cloud-init
    participant Repo as Public script source
    participant Script as oke-ubuntu-cloud-init.sh
    participant IMDS as Instance Metadata Service
    participant Boot as OKE bootstrap command
    participant Storage as FSS / Lustre

    Node->>Node: Write API address, CA, networkd settings and SSH keys
    opt nvme_raid_enabled
        Node->>Repo: Download oke-nvme-raid.sh
        Node->>Node: Run RAID setup with configured level
    end
    Node->>Repo: Download oke-ubuntu-cloud-init.sh
    Node->>Script: Pass Kubernetes version, OCIR provider and hostname options
    loop Until instance-principal certificate is available
        Script->>IMDS: Read identity/cert.pem
    end
    Script->>IMDS: Read instance shape
    Script->>Script: Apply shape-specific runtime settings
    opt OCIR credential provider or hostname override requested
        Script->>Script: Prepare bootstrap kubelet arguments
    end
    Script->>IMDS: Read metadata/pre_oke
    opt Decodable pre-bootstrap hook supplied
        Script->>Script: Execute hook
    end
    alt Ubuntu
        Script->>Script: Reuse oke binary or install OKE package with local-repo fallback
        Script->>Boot: Run oke bootstrap with configured arguments
    else Oracle Linux
        alt oke binary available
            Script->>Boot: Run oke bootstrap
        else Binary absent
            Script->>IMDS: Read metadata/oke_init_script
            Script->>Boot: Decode and execute oke-init.sh
        end
    end
    Note over Script,Boot: Bootstrap command retries up to 20 attempts, 15 seconds between failures
    Boot-->>Script: Bootstrap result
    Script->>IMDS: Read metadata/post_oke after successful bootstrap
    opt Decodable post-bootstrap hook supplied
        Script->>Script: Execute hook
    end
    Script-->>Node: Script result
    opt Configured storage address is available
        Node->>Repo: Download enabled FSS / Lustre mount scripts
        Node->>Storage: Run mount scripts, FSS before Lustre
    end
    opt Ubuntu
        Node->>Node: Restart systemd-networkd
    end
```

Workers download these scripts from `refs/heads/main` when they boot. The scripts give GPU shapes unlimited CRI-O memlock and disable an existing host `nvidia-imex` service on GB200/GB300 shapes for DRA compatibility. Bootstrap and mount failures are logged by the command wrappers, which allow cloud-init to continue.

Sources: [cloud-config and command order](../terraform/oke-workers.tf), [bootstrap script](../files/oke-ubuntu-cloud-init.sh), [default cloud-init override](../terraform/oke-cluster.tf).

### 4. Shared Storage - Infrastructure, Host Mounts and Kubernetes PVs

The same file system can be mounted on the worker host and exposed to Kubernetes through a PersistentVolume (PV). The stack sets up both paths from the storage address and export details. Workloads use their own PersistentVolumeClaims (PVCs) to request the Kubernetes volume.

```mermaid
sequenceDiagram
    autonumber
    participant TF as Terraform
    participant FSS as OCI File Storage
    participant Lustre as OCI Lustre
    participant Node as Worker node
    participant Deploy as Provider / operator kubectl
    participant API as Kubernetes API

    opt create_fss_effective
        TF->>FSS: Create file system, mount target and export
        FSS-->>TF: File-system ID, mount IP and /oke-gpu-state export
        par Worker cloud-init mount
            Node->>Node: Install NFS client and create mount directory
            Node->>FSS: Mount NFS v3 with nconnect=16
            Node->>Node: Add fstab entry after successful mount
        and Kubernetes volume declaration
            TF->>Deploy: Build FSS CSI volume handle from ID, IP and export
            Deploy->>API: Create fss-pv, ReadWriteMany, Retain
        end
    end
    opt create_lustre
        TF->>Lustre: Create configured managed Lustre file system
        Lustre-->>TF: Management service address
        Node->>Lustre: Invoke configured host mount script
        opt create_lustre_pv
            TF->>Deploy: Render Lustre PV template
            Deploy->>API: Apply Lustre PV
        end
    end
```

FSS is created when you enable `create_fss`, or when Slinky needs its default `fss-pv` home volume. The PV uses the `Retain` reclaim policy, while the OCI file system itself stays under Terraform's lifecycle management.

Sources: [FSS resources and PV](../terraform/fss.tf), [operator FSS PV](../terraform/via-operator-fss.tf), [NFS mount script](../files/oke-fss-mount.sh), [Lustre resources](../terraform/lustre.tf), [Lustre host mount](../files/oke-lustre-mount.sh), [provider Lustre PV](../terraform/via-provider-lustre-client.tf), [operator Lustre PV](../terraform/via-operator-lustre.tf).

### 5. Node Topology Labeling - Runtime Reconciliation

When enabled, the `oci-hpc-oke-utils` labeler reads each node's metadata and keeps its Kubernetes topology labels up to date. A separate controller adds host and maintenance information from the OCI API.

```mermaid
sequenceDiagram
    autonumber
    participant Labeler as Labeler DaemonSet process
    participant IMDS as Node IMDS
    participant API as Kubernetes API

    Labeler->>Labeler: Load in-cluster credentials and NODE_NAME
    Labeler->>Labeler: Read available static GPU information and mark ready
    loop Each configured interval
        Labeler->>IMDS: Read instance shape and host/rdmaTopologyData
        opt Topology projection unavailable or empty
            Labeler->>IMDS: Fall back to host document
        end
        Labeler->>IMDS: Read host fabric data
        opt GPU memory fabric shape
            Labeler->>IMDS: Read instance tags for GPU memory cluster ID
        end
        Labeler->>API: Read current node labels
        Labeler->>Labeler: Derive topology, fabric and mapping labels
        Note over Labeler,API: Preserve valid existing values when IMDS is unavailable
        opt Labels changed or managed mapping keys became stale
            Labeler->>API: Patch changed labels and remove stale mapping labels
        end
        Labeler->>Labeler: Update health marker and sleep
    end
```

Topology labels use the last 11 characters of the IDs returned by IMDS. If metadata is temporarily unavailable, the labeler keeps any valid labels it already has and uses `no-imds-data` for missing values. Label updates run in the background after the labeler marks itself ready.

Sources: [labeler implementation](../terraform/files/oci-hpc-oke-utils/templates/labeler-configmap.yaml), [DaemonSet](../terraform/files/oci-hpc-oke-utils/templates/labeler.yaml), [chart values](../terraform/files/oci-hpc-oke-utils/values.yaml), [separate controller implementation](../terraform/files/oci-hpc-oke-utils/templates/controller-configmap.yaml).

### 6. Kueue Installation and RDMA Queue Configuration

The stack installs Kueue and checks its webhook before creating queues. If you've enabled an RDMA or GMC pool, it also sets up the topology and resource flavor used by the RDMA queues.

```mermaid
sequenceDiagram
    autonumber
    participant TF as Terraform
    participant Deploy as Provider / operator Helm and kubectl
    participant API as Kubernetes API
    participant Webhook as Kueue admission webhook

    TF->>Deploy: Complete applicable cert-manager dependencies
    TF->>Deploy: Install Kueue in kueue-system
    Deploy->>API: Apply Kueue chart
    alt Operator path
        loop Up to 60 attempts, two-second retry sleep
            Deploy->>API: Server-side dry-run of readiness probe
            API->>Webhook: Exercise admission
            Webhook-->>API: Admission result
        end
        Note over Deploy,Webhook: Exit on exhausted probe failures
    else Local / ORM provider path
        Deploy->>API: Apply webhook probe with provider retries
        API->>Webhook: Exercise admission
        Webhook-->>API: Admission result
    end
    opt worker_rdma_enabled or worker_gmc_enabled
        TF->>TF: Choose GMC shape if enabled, otherwise RDMA shape
        TF->>TF: Select amd.com/gpu or nvidia.com/gpu
        Deploy->>API: Apply oci-rdma Topology
        Deploy->>API: Apply ResourceFlavor for shape and GPU label
        Deploy->>API: Apply ClusterQueue with configured template quotas
        Deploy->>API: Apply default LocalQueue in selected namespace
    end
```

The topology groups nodes by HPC island, network block, local block, and hostname. The ResourceFlavor connects that topology to the selected instance shape and GPU label. Queue quotas come from fixed values in the template. On the provider path, the chart uses `wait = false`, and the webhook probe checks that admission is ready before setup continues.

Sources: [provider Kueue resources](../terraform/via-provider-kueue.tf), [operator Kueue resources](../terraform/via-operator-kueue.tf), [Topology](../terraform/files/kueue/topology.yaml), [ResourceFlavor](../terraform/files/kueue/resource-flavor.yaml.tpl), [ClusterQueue](../terraform/files/kueue/cluster-queue.yaml.tpl), [LocalQueue](../terraform/files/kueue/local-queue.yaml.tpl).

### 7. NCCL MPIJob - Manifest and Launcher Execution

Once Kueue and MPI Operator are installed, you can submit the H100 NCCL example. It includes its own resource flavor and queues alongside the MPIJob. The launcher waits for the workers, then starts the benchmark across them.

```mermaid
sequenceDiagram
    autonumber
    participant User as User
    participant API as Kubernetes API
    participant Controllers as External Kueue / MPI controllers
    participant Launcher as MPI launcher container
    participant Workers as MPI worker containers

    User->>API: Apply H100 NCCL example manifest
    Note over API,Controllers: Manifest declares ResourceFlavor, ClusterQueue, LocalQueue and MPIJob
    API-->>Controllers: Declarative resources available for reconciliation
    Note over Launcher,Workers: Manifest requests one launcher, two workers and eight slots per worker
    Launcher->>Launcher: Read /etc/mpi/hostfile and calculate hosts times eight ranks
    loop Until every host accepts SSH
        Launcher->>Workers: Probe SSH port 2222
        Workers-->>Launcher: SSH result
        Launcher->>Launcher: Sleep five seconds on failed readiness check
    end
    Launcher->>Workers: mpirun with hostfile, ranks and NCCL environment
    Workers->>Workers: Execute all_reduce_perf benchmark
```

The manifest brings together host networking, shape selection, GPU requests, and RDMA settings for the benchmark. For AMD nodes, the RCCL examples provide their own images and parameters.

Sources: [H100 NCCL manifest](../manifests/nccl-tests/kueue/BM.GPU.H100.8.yaml), [MI300X RCCL manifest](../manifests/rccl-tests/kueue/BM.GPU.MI300X.8.yaml), [provider MPI Operator installation](../terraform/via-provider-mpi-operator.tf), [operator MPI Operator installation](../terraform/via-operator-mpi-operator.tf).

### 8. Monitoring and Grafana Alert Delivery

Prometheus collects metrics from the enabled exporters, and Grafana uses them for dashboards and alerts. When alerting is enabled, Grafana sends notifications through the ONS webhook to an OCI Notifications topic. This setup uses Grafana alerting, with Alertmanager and the default Prometheus rules disabled.

```mermaid
sequenceDiagram
    autonumber
    participant TF as Terraform deployment path
    participant Render as Grafonnet renderer on Terraform runner
    participant API as Kubernetes API
    participant Exporters as Enabled metrics exporters
    participant Prom as Prometheus
    participant Grafana as Grafana
    participant Hook as ONS webhook and background workers
    participant DB as Webhook SQLite database
    participant ONS as OCI Notifications topic

    TF->>API: Install selected monitoring charts and ServiceMonitors
    TF->>Render: Compile dashboard Jsonnet and shared Grafonnet helpers
    Render-->>TF: Generated dashboard JSON by category
    TF->>TF: Select dashboard categories and filter GPU health panels
    TF->>API: Provision generated dashboard JSON in labeled ConfigMaps
    TF->>API: Provision separately maintained YAML alert ConfigMaps
    Note over API,Grafana: Chart values enable sidecars for supplied dashboard / alert configuration
    Prom->>Exporters: Scrape configured metric endpoints
    Exporters-->>Prom: Metrics
    Grafana->>Prom: Query metrics for dashboards and configured alert rules
    opt Alerting configured and alert notification emitted
        Grafana->>Hook: POST /grafana-webhook
        alt Invalid or empty JSON payload
            Hook-->>Grafana: HTTP 400
        else Accepted payload
            Hook->>Hook: Queue each alert in process memory
            Hook-->>Grafana: HTTP 200, Alert queued
            Hook->>DB: Track alert state, timestamps and notification history
            Note over Hook,DB: Apply filtering, debounce and reminder logic
            Hook->>Hook: Queue eligible notifications and optionally aggregate
            Hook->>ONS: publish_message using instance-principal authentication
            ONS-->>Hook: Publish result
        end
    end
```

The webhook queues incoming alerts in memory and returns HTTP 200 once they're queued. Background workers track alert state in SQLite, apply debounce and reminder rules, and send eligible notifications to ONS. They skip `DatasourceNoData` alerts and log any publishing errors.

Sources: [operator monitoring deployments](../terraform/via-operator-helm-deployments.tf), [provider Prometheus deployment](../terraform/via-provider-kube-prometheus-stack.tf), [monitoring chart values](../terraform/files/kube-prometheus/values.yaml.tftpl), [provider Grafana ConfigMaps](../terraform/via-provider-grafana.tf), [operator Grafana ConfigMaps](../terraform/via-operator-grafana.tf), [Grafana notification policy](../terraform/files/grafana/alerts/alert-rules.yaml), [webhook implementation](../terraform/files/oke-ons-webhook/templates/configmap.yaml), [ONS topic](../terraform/topic.tf).

#### 8a. Grafonnet Dashboards - Source, Compilation and Deployment

Grafonnet lets us build dashboards from reusable pieces of Jsonnet code. A dashboard combines shared panel and variable helpers with its own queries, titles, units, thresholds, and layout. The renderer turns those definitions into the JSON Grafana loads from ConfigMaps. There are 21 dashboards here: seven for Kubernetes, five for GPUs, and nine for OCI metrics.

```mermaid
sequenceDiagram
    autonumber
    participant Source as Dashboard Jsonnet and shared helpers
    participant TF as Terraform runner, local or ORM
    participant Render as render_dashboards.py
    participant Deps as Pinned tools and locked dependencies
    participant Operator as Operator host
    participant API as Kubernetes ConfigMaps

    TF->>Render: Evaluate external data source with --external
    opt Tools or matching dependency cache absent
        Render->>Deps: Fetch checksum-verified Jsonnet 0.21.0 and jb 0.6.0
        Render->>Deps: Install dependencies from manifest and lock file
    end
    loop Each dashboard source in common, gpu and oci
        Render->>Source: Evaluate Jsonnet with shared helpers and Grafonnet imports
        Source-->>Render: Dashboard JSON
        Render->>Render: Parse JSON and reject duplicate output names
    end
    Render->>Render: Replace rendered output directory after successful compilation
    Render-->>TF: Return JSON strings by category and source hash
    TF->>TF: Select enabled dashboard categories
    TF->>TF: Filter and reflow GPU Health Status panels for configured GPU vendors
    alt Local or ORM provider path
        TF->>API: Create or update dashboard-name ConfigMaps from generated strings
    else Operator path through bastion SSH
        TF->>Operator: Copy rendered JSON directories
        TF->>Operator: Overwrite GPU Health Status JSON with filtered version
        TF->>Operator: Copy generated kustomization.yaml
        Operator->>API: kubectl apply -k . with stable ConfigMap names
    end
    Note over TF,API: Dashboard ConfigMaps depend on the applicable Prometheus stack deployment
```

Terraform calls `render_dashboards.py` through an external data source, often during planning. Compilation happens on the Terraform runner, including when the dashboards will be deployed through the operator host. The renderer caches tools and dependencies under `.terraform/grafana-jsonnet` and rebuilds the dashboard JSON each time it runs.

Once all dashboards compile successfully, the renderer replaces the `rendered` directory and returns the JSON to Terraform. It also returns a hash of the sources, helpers, dependency manifests, and renderer. The operator deployment uses that hash to pick up source changes on the next apply.

Turning on `install_monitoring` and `install_grafana` enables the renderer. To publish the dashboards, the stack also needs `install_grafana_dashboards`, `install_node_problem_detector_kube_prometheus_stack`, and a supported deployment path. So the renderer can still run even when dashboard publication is turned off.

| Source category | Dashboard count | Folder annotation | Additional selection |
| --- | --- | --- | --- |
| `dashboards/common` | 7 | `Kubernetes` | Shared publication conditions above |
| `dashboards/gpu` | 5 | `GPU Nodes` | `has_amd_gpu || has_nvidia_gpu` |
| `dashboards/oci` | 9 | `OCI Metrics` | `setup_oci_metrics_exporter` |

Terraform adjusts GPU Health Status to match the configured GPUs: panel `7` is for NVIDIA and panel `23` is for AMD. It then arranges the remaining stat panels in rows of eight. Once the dashboard is loaded, Grafana queries the live metrics as shown in diagram 8b.

The older JSON files under `files/grafana/dashboards` are kept as a reference for development checks. Running `make verify` checks formatting, compiles the dashboards, and compares IDs, queries, variables, layout, and GPU vendor variants against that reference. Terraform deploys the freshly generated JSON.

Alert rules and the ONS contact point still live in YAML under `files/grafana/alerts`. They follow the alert ConfigMap path shown in diagram 8.

Sources: [Terraform renderer and vendor filtering](../terraform/grafana.tf), [renderer implementation](../terraform/files/grafana/jsonnet/render_dashboards.py), [Grafonnet import](../terraform/files/grafana/jsonnet/lib/g.libsonnet), [dependency manifest](../terraform/files/grafana/jsonnet/jsonnetfile.json), [dependency lock](../terraform/files/grafana/jsonnet/jsonnetfile.lock.json), [provider publication](../terraform/via-provider-grafana.tf), [operator publication and triggers](../terraform/via-operator-grafana.tf), [Makefile](../terraform/files/grafana/jsonnet/Makefile), [contract verifier](../terraform/files/grafana/jsonnet/verify_dashboards.py).

#### 8b. Grafana Dashboards - Provisioning and Live Metric Queries

Here's what happens once the generated GPU Metrics dashboard reaches the cluster. The Grafana sidecar picks up the dashboard ConfigMap, and Grafana uses its queries and variables to show metrics for the nodes you select.

```mermaid
sequenceDiagram
    autonumber
    participant API as Dashboard ConfigMaps
    participant Sidecar as Grafana dashboard sidecar
    participant Grafana as Grafana
    participant User as Dashboard viewer
    participant Prom as Selected Prometheus datasource
    participant Exporters as Enabled exporters

    Note over API,Sidecar: grafana_dashboard=1 and grafana_dashboard_folder select dashboard content and folder
    API-->>Sidecar: Generated JSON available for configured dashboard provisioning
    Sidecar->>Grafana: Provision dashboard JSON through chart-managed integration
    User->>Grafana: Open GPU Metrics dashboard, UID gpu-metrics-single
    User->>Grafana: Select Prometheus datasource
    Grafana->>Prom: Resolve instance_shape from node_uname_info
    Prom-->>Grafana: Available shape values
    User->>Grafana: Select instance shape
    Grafana->>Prom: Resolve hostname and oci_name from up metrics filtered by shape
    Prom-->>Grafana: Available node and display-name values
    User->>Grafana: Select node, display name and time range
    par Independent metrics collection
        Prom->>Exporters: Scrape configured endpoints
        Exporters-->>Prom: GPU, host and RDMA metric samples
    and Dashboard query evaluation
        Grafana->>Prom: Evaluate panel PromQL with selected variables and time range
        Prom-->>Grafana: Query results
        Grafana-->>User: Render panels using generated layout, units and thresholds
    end
```

For example, `gpu-metrics.jsonnet` passes a title, query, legend, unit, position, and ID to `timeseries-panel.libsonnet`. The helper turns those into a time-series panel using the `$PROMETHEUS_DS` datasource. GPU temperature queries handle both AMD and NVIDIA metrics and normalize their labels where needed.

When you select a node in Grafana, the dashboard uses that selection in its Prometheus queries. When you edit a shared helper in the repository, every dashboard that imports it picks up the change on the next render and deployment.

Both deployment paths use the same ConfigMap names and folders. GPU Metrics lives in `dashboard-gpu-metrics`, under the key `gpu-metrics.json`, and keeps the dashboard UID `gpu-metrics-single`. The chart enables the dashboard sidecar, folder mapping, and UI edits.

You can try out changes in Grafana, then carry the ones you want to keep back into the Jsonnet source or shared helpers. That way, the next deployment includes them too.

Sources: [GPU Metrics source](../terraform/files/grafana/jsonnet/dashboards/gpu/gpu-metrics.jsonnet), [time-series panel helper](../terraform/files/grafana/jsonnet/lib/timeseries-panel.libsonnet), [GPU Metrics variables](../terraform/files/grafana/jsonnet/lib/gpu-metrics-variables.libsonnet), [sidecar configuration](../terraform/files/kube-prometheus/values.yaml.tftpl), [ConfigMap names and labels](../terraform/via-provider-grafana.tf). For operational procedures, see [Operating and developing Grafana dashboards](./grafonnet-dashboards.md).

### 9. Kueue Teardown - Drain Before Helm Removal

Before removing Kueue, Terraform runs a cleanup script through the operator or local/ORM runner. It removes Kueue resources across all namespaces and clears remaining finalizers so chart removal can proceed.

```mermaid
sequenceDiagram
    autonumber
    participant User as User / Resource Manager
    participant TF as Terraform destroy
    participant Runner as Operator or local / ORM runner
    participant API as Kubernetes API
    participant Helm as Helm cleanup

    User->>TF: Destroy resources containing Kueue deployment
    alt Operator path
        TF->>Runner: SSH through bastion and invoke saved drain script
    else Local / ORM path
        TF->>Runner: local-exec with saved kubeconfig and drain script
    end
    Runner->>API: Check for Kueue CRDs
    alt No Kueue CRDs found
        Runner-->>TF: Nothing to drain
    else Kueue CRDs found
        loop Each listed Kueue resource kind
            Runner->>API: Delete all instances across namespaces, timeout 60 seconds
        end
        loop Each remaining listed object
            Runner->>API: Patch metadata.finalizers to an empty list
        end
        Runner-->>TF: Drain script complete
    end
    TF->>Helm: Remove Kueue release
    Helm->>API: Uninstall chart
    Note over TF,API: Cleanup errors allow Terraform destroy to continue
```

The operator helper runs `helm uninstall --wait`, while the local/ORM release uses `wait = false`. Both paths run the Kueue resource cleanup first and allow destroy to continue if cleanup encounters an error.

Sources: [operator drain resource](../terraform/via-operator-kueue-predestroy-drain.tf), [local/ORM drain resource](../terraform/via-orm-kueue-predestroy-drain.tf), [drain script](../terraform/files/kueue/predestroy-drain.sh), [operator Helm cleanup](../terraform/helm-module/helm-deployment.tf), [provider Kueue release](../terraform/via-provider-kueue.tf).

### 10. Optional Slinky Installation on OKE

Slinky adds Slurm to the OKE cluster using the same SSH/Helm helper as diagram 2. Its operator path is enabled by `install_slinky && create_bastion && create_operator && !deploy_to_oke_from_orm`. This also works with a public control plane when those settings are enabled.

```mermaid
sequenceDiagram
    autonumber
    participant TF as Terraform
    participant Operator as OKE operator host
    participant API as Kubernetes API

    TF->>Operator: Install slurm-operator-crds chart
    Operator->>API: Apply CRDs through Helm
    TF->>TF: Satisfy applicable Kueue and cert-manager dependencies
    TF->>Operator: Install slurm-operator chart
    Operator->>API: Helm install and wait for operator webhook rollout
    opt slinky_install_slurm_cluster
        TF->>TF: Satisfy utilities, auth, storage and enabled identity/accounting dependencies
        opt Enabled GMC ComputeDomains
            TF->>Operator: Apply GPU memory fabric ComputeDomain configuration
        end
        TF->>Operator: Install slurm chart with generated and user values
        Operator->>API: Wait for slurm-controller StatefulSet rollout
        opt Login enabled
            Operator->>API: Wait for slurm-login-slinky Deployment rollout
        end
        opt Accounting enabled
            Operator->>API: Wait for slurm-accounting StatefulSet rollout
        end
        Operator->>API: Inspect worker NodeSets and pods without requiring readiness
        Operator->>API: Run sinfo inside slurm-controller-0
    end
```

The Slurm chart install checks the controller, login, and accounting rollouts explicitly instead of using Helm `--wait`. It also prints worker NodeSet status, allowing workers to finish joining after the control plane is ready.

Sources: [Slinky selectors and generated values](../terraform/slinky.tf), [operator deployments and dependencies](../terraform/via-operator-slinky.tf), [Helm helper](../terraform/helm-module/helm-deployment.tf).

## Reading the Flows Together

Start with diagrams 1–4 to follow cluster creation, Kubernetes access, worker bootstrap, and storage setup. Diagrams 5–7 then show how nodes get their topology labels, how Kueue queues are set up, and how an MPI benchmark starts.

Diagram 8 brings monitoring together. The two details below it follow Grafonnet from source to deployed dashboard, then show how Grafana queries live metrics. Diagram 9 covers Kueue cleanup during destroy, and diagram 10 covers the optional Slinky setup.
