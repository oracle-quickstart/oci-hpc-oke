# oci-hpc-oke-utils

`oci-hpc-oke-utils` is a Helm chart that deploys utility DaemonSets on GPU nodes. It has three components:

| Component | Default | Description |
|-----------|---------|-------------|
| [Labeler](#labeler) | Enabled | Applies RDMA topology, compute host, firmware, maintenance, and custom labels to nodes |
| [Prepuller](#prepuller) | Disabled | Pre-pulls container images on GPU nodes |
| [Hostexec](#hostexec) | Disabled | Runs shell scripts on the host via `nsenter` |

All three target GPU nodes by default (nodes with `nvidia.com/gpu` or `amd.com/gpu` labels).

---

## Labeler

The labeler is a DaemonSet that automatically applies Kubernetes node labels and conditions with infrastructure metadata. It sources data from three places:

1. **Instance Metadata Service (IMDS)** -- RDMA topology and GPU memory fabric placement
2. **OCI ComputeHost, FirmwareBundle, and MaintenanceEvent APIs** -- host health, platform, firmware versions, maintenance events
3. **User-provided CSV label mappings** -- custom labels derived from existing labels

Labels are applied periodically and kept up to date. If a data source is temporarily unavailable, existing labels are preserved rather than overwritten.

### Configuration

| Value | Default | Description |
|-------|---------|-------------|
| `labeler.enabled` | `true` | Enable/disable the labeler DaemonSet |
| `labeler.interval` | `300` | Seconds between IMDS label refreshes |
| `labeler.hostInterval` | `900` | Seconds between OCI API label refreshes |
| `labeler.labelMappings` | `{}` | CSV-based label mappings (see [Label Mappings](#label-mappings)) |

The labeler staggers startup by a random 0-120 second jitter per node to avoid thundering herd API calls during DaemonSet rollout.

### Labels

#### RDMA Topology Labels

Applied to all GPU nodes. Sourced from IMDS every 5 minutes (default).

| Label | Description | Example |
|-------|-------------|---------|
| `oci.oraclecloud.com/rdma.hpc_island_id` | HPC island placement (last 11 chars of OCID) | `md2gqsaja` |
| `oci.oraclecloud.com/rdma.host_id` | Host identifier within the island | `clnbliq` |
| `oci.oraclecloud.com/rdma.local_block_id` | Local block placement | `xvl2gga` |
| `oci.oraclecloud.com/rdma.network_block_id` | Network block placement | `sn4ibrza` |

These labels are used by [Kueue Topology-Aware Scheduling](./using-rdma-network-locality-when-running-workloads-on-oke.md) to place workloads on nodes with optimal RDMA locality.

#### GPU Memory Fabric Labels (GB200/GB300 only)

Applied only to GPU memory fabric shapes. Sourced from IMDS.

| Label | Description | Example |
|-------|-------------|---------|
| `oci.oraclecloud.com/host.gpu_memory_fabric_id` | GPU memory fabric placement (last 11 chars) | `tkj3zctga` |
| `oci.oraclecloud.com/host.gpu_memory_cluster_id` | GPU memory cluster association (last 11 chars) | `5edoma` |

#### Compute Host Labels

Applied to nodes where the OCI ComputeHost API returns data (currently bare metal GPU shapes). Sourced from the OCI API every 15 minutes (default).

| Label | Description | Values |
|-------|-------------|--------|
| `oci.oraclecloud.com/host.platform` | Hardware platform revision | `GPU_GB200-NVL72_S.01` |
| `oci.oraclecloud.com/host.health` | Host health status | `HEALTHY`, `UNHEALTHY` |
| `oci.oraclecloud.com/host.lifecycle_state` | Host lifecycle state | `AVAILABLE`, `OCCUPIED`, `PROVISIONING`, `REPAIR`, `UNAVAILABLE` |
| `oci.oraclecloud.com/host.has_impacted_components` | Whether the host has degraded components | `true`, `false` |
| `oci.oraclecloud.com/host.recycle_level` | Host recycle policy | `FULL_RECYCLE`, `SKIP_RECYCLE` |
| `oci.oraclecloud.com/host.capacity_reservation_id` | Capacity reservation (last 11 chars of OCID) | Only set when using reserved capacity |
| `oci.oraclecloud.com/host.compute_host_group_id` | Host group association (last 11 chars of OCID) | Only set when part of a host group |

#### GPU Tray Index Label

On NVIDIA GPU nodes, the labeler reads the compute tray position from `nvidia-smi` via an init container:

| Label | Description | Example |
|-------|-------------|---------|
| `oci.oraclecloud.com/host.tray_index` | Compute tray position within the rack (0-17 for NVL72) | `13` |

This label is only set on nodes where `nvidia-smi` is available on the host. It is read once at pod startup and does not change.

#### Fault Labels

When a host component has an active fault (`impacting: true`), a label is added per component type with the OCI fault ID:

| Label | Description | Example |
|-------|-------------|---------|
| `oci.oraclecloud.com/host.fault.<component_type>` | Active fault ID for the component type | `SPENV-8000-9M` |

For example, an actively faulting SSD would produce `oci.oraclecloud.com/host.fault.ssd = SPENV-8000-9M`. If multiple components of the same type have different fault IDs, the label shows the count and first ID (e.g., `4x_SPENV-8000-9M`).

These labels are automatically removed when the fault clears. Stale fault labels are only cleaned up when the OCI API is reachable -- if the API is temporarily unavailable, existing fault labels are preserved to avoid false negatives.

#### Maintenance Event Labels

When an instance has an active maintenance event (`SCHEDULED` or `IN_PROGRESS`), the following labels are applied:

| Label | Description | Example |
|-------|-------------|---------|
| `oci.oraclecloud.com/host.maintenance.reason` | Reason for maintenance | `EVACUATION` |
| `oci.oraclecloud.com/host.maintenance.action` | Action OCI will take | `NONE`, `REBOOT`, `STOP`, `TERMINATE` |
| `oci.oraclecloud.com/host.maintenance.state` | Maintenance lifecycle state | `SCHEDULED`, `IN_PROGRESS` |

These labels are automatically removed when the maintenance event completes or is canceled.

#### Maintenance Node Condition

In addition to labels, the labeler sets a Kubernetes node condition for active maintenance events:

```
Type:    oci.oraclecloud.com/MaintenanceFault
Status:  True
Reason:  HPCGPU-0002-02
Message: The GPU has exceeded the maximum number of ECC defective row remaps.
```

The condition includes fault details (fault ID, description) from the OCI `InstanceMaintenanceEvent` API when available. When the maintenance event resolves, the condition is set to `False`:

```
Type:    oci.oraclecloud.com/MaintenanceFault
Status:  False
Reason:  Resolved
Message: No active maintenance events
```

#### Firmware Labels

Applied to nodes where the OCI FirmwareBundle API returns data. These labels are dynamic -- the exact set depends on the hardware platform and shape.

| Label | Description | Example |
|-------|-------------|---------|
| `oci.oraclecloud.com/host.fw.bundle_version` | Firmware bundle version | `1.3.5` |

**Host firmware components** (prefix: `oci.oraclecloud.com/host.fw.`):

| Label | Description | Example |
|-------|-------------|---------|
| `host.fw.hgx_fw_gpu_0` .. `host.fw.hgx_fw_gpu_N` | GPU InfoROM firmware per GPU | `97.00.B9.00.95` |
| `host.fw.hgx_fw_bmc_0` | HGX baseboard management controller | `GB200Nvl-25.06-A` |
| `host.fw.hgx_fw_cpu_0`, `host.fw.hgx_fw_cpu_1` | HGX CPU firmware | `00020414` |
| `host.fw.hgx_fw_fpga_0`, `host.fw.hgx_fw_fpga_1` | HGX FPGA firmware | `1.60` |
| `host.fw.hgx_fw_cpld_0` | HGX CPLD firmware | `0.22` |
| `host.fw.hgx_fw_erot_cpu_0` .. `host.fw.hgx_fw_erot_bmc_0` | ERoT firmware per component | `01.04.0031.0000_n04` |
| `host.fw.nvme` | NVMe drive firmware | `GDC6602Q` |
| `host.fw.mezz` | Mezzanine NIC firmware | `28.47.1026` |
| `host.fw.hostnic` | Host NIC firmware | `28.47.1026` |

**Switch firmware components** (prefix: `oci.oraclecloud.com/host.fw.switch.`):

| Label | Description | Example |
|-------|-------------|---------|
| `host.fw.switch.nvos` | NVLink switch OS version | `25.02.2553` |
| `host.fw.switch.bmc` | Switch BMC firmware | `88.0002.1336` |

Components with multiple firmware versions (e.g., NVMe drives with different firmware across drive models) are joined with underscores: `GDC6602Q_E2MU200_RG41020E`.

The number of GPU firmware labels matches the GPU count of the shape (e.g., 4 labels for BM.GPU.GB200.4, 8 for BM.GPU.H100.8).

### Label Mappings

The labeler supports user-defined label mappings via CSV. This allows adding custom labels to nodes based on the value of an existing label. For example, mapping GPU memory fabric IDs to internal rack identifiers.

#### Configuration

Add CSV mappings in the Helm values:

```yaml
labeler:
  labelMappings:
    gpu-fabric-racks.csv: |
      oci.oraclecloud.com/host.gpu_memory_fabric_id,oci.oraclecloud.com/host.internal_rack_id
      ocid1.computegpumemoryfabric.oc1.ap-sydney-1.anzxsljr2472ivyc7lzxt7l3wo2...bq,sk-e6df6e21-5b1d-492e-a5b1-145abbbdaa1b
      ocid1.computegpumemoryfabric.oc1.ap-sydney-1.anzxsljr2472ivycjwpjvudm7z...ga,sk-d8d2f63d-7c30-4284-a59a-193575cc9f4a
```

#### CSV Format

- **Header row**: first column is the existing label key to match, remaining columns are new label keys to add
- **Data rows**: first column is the value to match, remaining columns are the values to set

#### Matching

The labeler uses **suffix matching** -- the CSV value and the node's label value are compared by suffix. This means you can use full OCIDs in the CSV even though the labeler truncates OCIDs to the last 11 characters. For example, a CSV row with `ocid1.computegpumemoryfabric...pvtkj3zctga` matches a node label value of `pvtkj3zctga`.

#### Multiple Mappings

You can define multiple CSV files for different label keys:

```yaml
labeler:
  labelMappings:
    gpu-fabric-racks.csv: |
      oci.oraclecloud.com/host.gpu_memory_fabric_id,oci.oraclecloud.com/host.internal_rack_id
      ...
    network-block-zones.csv: |
      oci.oraclecloud.com/rdma.network_block_id,oci.oraclecloud.com/host.zone
      ...
```

#### Cleanup

When a CSV row is removed or a mapping no longer matches, the corresponding labels are automatically removed from nodes. Updating `labelMappings` in the Helm values triggers a pod restart via the checksum annotation.

### How It Works

The labeler runs as a DaemonSet pod on each GPU node with `hostNetwork: true` for IMDS access. It uses three data sources on independent refresh intervals:

**IMDS path (every 5 minutes):**
1. Queries `http://169.254.169.254/opc/v2/host/rdmaTopologyData` for RDMA placement
2. Queries `/instance/shape` to detect GPU memory fabric shapes
3. For GB200/GB300, queries `/instance/` for GPU memory cluster tags

**OCI API path (every 15 minutes):**
1. Creates an OCI ComputeClient using instance principals
2. Gets the instance OCID and tenancy OCID from IMDS
3. Lists compute hosts in the tenancy (paginated, host ID cached after first lookup)
4. Calls `get_compute_hosts` for full host details including firmware bundle ID
5. Calls `get_firmware_bundle` for per-component firmware versions
6. Lists maintenance events for the instance, sets labels and node conditions for active events
7. All API calls use exponential backoff on 429 throttling (up to 3 retries)

**Label mappings (every 5 minutes):**
1. Reads CSV files from the mounted ConfigMap
2. For each CSV, checks if the node has the label specified in the header
3. Suffix-matches the label value against CSV rows
4. Applies additional labels from matching rows
5. Removes stale mapping labels that no longer match

If the ComputeHost API does not have an entry for the instance (e.g., non-bare-metal shapes), the host and firmware labels are simply not applied.

### Using Labels

#### Querying nodes by firmware version

```bash
kubectl get nodes -l oci.oraclecloud.com/host.fw.bundle_version=1.3.5
```

#### Finding nodes with mismatched GPU firmware

```bash
kubectl get nodes -L oci.oraclecloud.com/host.fw.hgx_fw_gpu_0
```

#### Avoiding unhealthy hosts

Use a node affinity or node selector to avoid scheduling on degraded hosts:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: oci.oraclecloud.com/host.health
              operator: In
              values: ["HEALTHY"]
            - key: oci.oraclecloud.com/host.has_impacted_components
              operator: In
              values: ["false"]
```

#### Avoiding nodes with active maintenance

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: oci.oraclecloud.com/host.maintenance.state
              operator: DoesNotExist
```

#### Checking maintenance node conditions

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,MAINTENANCE:.status.conditions[?(@.type==\"oci.oraclecloud.com/MaintenanceFault\")].status
```

#### Selecting nodes by RDMA locality

See [Using RDMA Network Locality](./using-rdma-network-locality-when-running-workloads-on-oke.md) for Kueue topology-aware scheduling with the `rdma.*` labels.

---

## Prepuller

The prepuller is a DaemonSet that pre-pulls container images on GPU nodes so they are cached locally before workloads need them. This avoids long image pull times when large GPU container images (often 10+ GB) are first scheduled.

### Configuration

| Value | Default | Description |
|-------|---------|-------------|
| `prepuller.enabled` | `false` | Enable/disable the prepuller |
| `prepuller.pauseImage` | `registry.k8s.io/pause:3.10` | Pause container that keeps the pod alive after pulls complete |
| `prepuller.groups` | See below | Image groups with per-group node selectors |

#### Image Groups

Images are organized into groups, each with its own node selector. This allows pulling NVIDIA images only on NVIDIA nodes and AMD images only on AMD nodes.

Default groups:

```yaml
prepuller:
  groups:
    nvidia:
      nodeSelector:
        nvidia.com/gpu: "true"
      images:
        - iad.ocir.io/idxzjcdglx2s/nccl-tests:cuda-13.1.1-ubuntu-24.04-nccl-2.29.3-020926.1
    amd:
      nodeSelector:
        amd.com/gpu: "true"
      images:
        - iad.ocir.io/idxzjcdglx2s/rccl-tests:rocm-7.1.1-ubuntu22.04-rccl-2.27.7-012126.1
```

Each group creates a separate DaemonSet. You can add custom groups for your own workload images:

```yaml
prepuller:
  enabled: true
  groups:
    nvidia:
      nodeSelector:
        nvidia.com/gpu: "true"
      images:
        - my-registry/my-training-image:latest
        - my-registry/my-inference-image:latest
```

### How It Works

For each image group, the prepuller creates a DaemonSet with:

1. **Init containers** -- one per image, each runs `echo Image cached` and exits. The image pull happens as part of container startup, caching the image on the node.
2. **Pause container** -- a minimal container that keeps the pod alive after all init containers complete, ensuring the DaemonSet stays running.

The init containers run with `readOnlyRootFilesystem: true` and drop all capabilities. The pod uses `system-node-critical` priority to ensure it is not evicted.

If an image pull fails, the pod restarts (via `restartPolicy: Always`) and retries the pull.

---

## Hostexec

Hostexec is a DaemonSet that runs a user-defined shell script directly on the host using `nsenter`. This is useful for operations that require host-level access, such as loading kernel modules or configuring system services.

### Configuration

| Value | Default | Description |
|-------|---------|-------------|
| `hostexec.enabled` | `false` | Enable/disable the hostexec DaemonSet |
| `hostexec.interval` | `30` | Seconds between script executions |
| `hostexec.hostRootPath` | `/` | Host root filesystem mount path |
| `hostexec.script` | LNet setup script | The shell script to execute on the host |

### Default Script

The default script configures LNet (Lustre Networking) on nodes that have the `lnet` kernel module available:

```bash
#!/usr/bin/env bash
set -euo pipefail

if ! modinfo lnet >/dev/null 2>&1; then
  echo "lnet kernel module is not available on this node; skipping"
  exit 0
fi

if ! grep -q '^lnet ' /proc/modules 2>/dev/null; then
  echo "LNet not loaded, loading..."
  modprobe lnet
fi

lnet_output="$(lnetctl net show 2>&1 || true)"

if printf '%s\n' "$lnet_output" | grep -q "LNet stack down"; then
  lnetctl lnet configure
  DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}')
  lnetctl net add --net tcp --if "$DEFAULT_IFACE" \
    --peer-timeout 180 --peer-credits 120 --credits 1024
  echo "LNet configured successfully"
fi
```

### Custom Scripts

Replace the default script with your own by setting `hostexec.script`:

```yaml
hostexec:
  enabled: true
  interval: 60
  script: |
    #!/usr/bin/env bash
    set -euo pipefail
    # Your custom host-level commands here
    sysctl -w vm.swappiness=10
```

### How It Works

The hostexec DaemonSet:

1. Copies the script from a ConfigMap to the host filesystem via a `hostPath` volume
2. Runs the script using `nsenter --target 1 --net --mount --uts --ipc --pid` to enter the host's namespaces
3. Sleeps for the configured interval and repeats

The pod runs as **privileged** with `hostPID: true` because `nsenter` requires access to PID 1 on the host. It uses `system-node-critical` priority and allows 100% max unavailable during rolling updates since the script is idempotent.

The ConfigMap checksum is included as a pod annotation, so updating the script triggers a rolling restart of the DaemonSet.
