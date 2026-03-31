# Terratest

These tests run Terraform against OCI using API key auth by default, with optional instance principal support. The default suite covers validation failures and a minimal core provisioning apply. Storage, monitoring, OCI Resource Manager (ORM), and operator-path suites are optional and gated by env flags.

## Prereqs
- Terraform installed and available on PATH.
- Go installed (1.26+).
- OCI CLI installed and configured (required for monitoring, FSS, and operator tests).
- API key auth configured in `~/.oci/config` (unless using instance principal).

## Required env (default suite)
- `OCI_AUTH` (optional; defaults to `api_key`, set to `instance_principal` to use instance principal auth)
- `OCI_TENANCY_OCID`
- `OCI_REGION`
- `WORKER_OPS_AD`
- `WORKER_OPS_IMAGE_ID`
- `SSH_PUBLIC_KEY` or `SSH_PUBLIC_KEY_PATH`

API key auth (default) also requires:
- `OCI_USER_OCID`
- `OCI_FINGERPRINT`

More info about configuring the OCI Terraform provider: https://docs.oracle.com/en-us/iaas/Content/dev/terraform/configuring.htm

`TF_VAR_*` equivalents are also accepted for the required Terraform inputs. If `TFVARS_FILE` is set, required inputs can come from the var file instead of env. Missing required inputs will fail the test run.

## Run
From the repo root:

```sh
cd test

go mod tidy

go test -count=1 ./... -run TestValidation -timeout 30m

go test -count=1 ./... -run TestPlanSmoke -timeout 10m

go test -count=1 ./... -run TestCoreProvisioning -timeout 2h
```

## Using tfvars files
Set `TFVARS_FILE` (or `TFVARS_FILES`) to a comma-separated list of var files (relative or absolute paths). When set, the test harness does not force the default feature flags, so include any desired toggles in your var file (for example, `create_policies=false` if you lack tenancy permissions).

```sh
TFVARS_FILE=./tfvars/base/base.tfvars go test -count=1 ./... -run TestCoreProvisioning -timeout 2h
```

Copy the example tfvars and fill in your values:

```sh
cp ./tfvars/base/base.tfvars.example ./tfvars/base/base.tfvars
# Edit base.tfvars with your OCI credentials
```

Example with the provided templates:

```sh
TFVARS_FILE=./tfvars/base/base.tfvars,./tfvars/core/cluster-only.tfvars go test -count=1 ./... -run TestCoreProvisioning -timeout 2h
```

Monitoring example:

```sh
TFVARS_FILE=./tfvars/base/base.tfvars,./tfvars/monitoring/monitoring.tfvars go test -count=1 ./... -run TestMonitoring -timeout 3h
```

Pre-built topology configs are available under `tfvars/core/` (Terraform core), `tfvars/tf/` (Terraform topologies), and `tfvars/orm/` (ORM JSON):

| Path | Description |
|------|-------------|
| `tfvars/core/cluster-only.tfvars` | Minimal cluster, no bastion or operator |
| `tfvars/core/all-public-bastion-operator.tfvars` | Public cluster with bastion and operator |
| `tfvars/core/all-private.tfvars` | Fully private cluster |
| `tfvars/core/all-private-operator.tfvars` | Fully private cluster with operator |
| `tfvars/core/all-private-bastion-service.tfvars` | Fully private cluster with bastion service |
| `tfvars/tf/public-base-tf.tfvars` | TF public cluster, base topology |
| `tfvars/tf/public-bastion-operator-tf.tfvars` | TF public cluster with bastion and operator |
| `tfvars/tf/public-fss-monitoring-tf.tfvars` | TF public cluster with FSS and monitoring |
| `tfvars/tf/public-lustre-tf.tfvars` | TF public cluster with Lustre |
| `tfvars/tf/private-base-tf.tfvars` | TF private cluster with bastion service |
| `tfvars/tf/private-bastion-operator-tf.tfvars` | TF private cluster with bastion VM, operator, and bastion service |
| `tfvars/tf/private-fss-monitoring-tf.tfvars` | TF private cluster with FSS, monitoring, and bastion service |
| `tfvars/tf/private-lustre-tf.tfvars` | TF private cluster with Lustre and bastion service |
| `tfvars/orm/public-base-orm.json` | ORM public cluster, base topology |
| `tfvars/orm/public-fss-monitoring-orm.json` | ORM public cluster with FSS and monitoring |
| `tfvars/orm/public-lustre-orm.json` | ORM public cluster with Lustre |
| `tfvars/orm/public-fss-lustre-monitoring-orm.json` | ORM public cluster with FSS, Lustre, and monitoring |
| `tfvars/orm/private-base-orm.json` | ORM private cluster with bastion service |
| `tfvars/orm/private-fss-monitoring-orm.json` | ORM private cluster with FSS, monitoring, and bastion service |
| `tfvars/orm/private-lustre-orm.json` | ORM private cluster with Lustre and bastion service |
| `tfvars/orm/private-fss-lustre-monitoring-orm.json` | ORM private cluster with FSS, Lustre, monitoring, and bastion service |

## Optional suites
Storage (FSS & Lustre):

```sh
RUN_FSS_TESTS=1 go test -count=1 ./... -run TestStorageFSS -timeout 3h
RUN_LUSTRE_TESTS=1 go test -count=1 ./... -run TestStorageLustre -timeout 3h
```

Both FSS and Lustre default to `worker_ops_ad`. Override with `FSS_AD` or `LUSTRE_AD` if needed.

Monitoring:

```sh
RUN_MONITORING_TESTS=1 go test -count=1 ./... -run TestMonitoring -timeout 3h
```

## CI health checks and assertions

The CI apply workflows (`ci-apply-tf.yml`, `ci-apply-orm.yml`) run the following checks after a successful apply. Health checks run for all topologies. Public topologies connect to the API server directly; private topologies tunnel through OCI Bastion Service using an ephemeral SSH keypair generated at runtime. Output assertions also run for all topologies.

### Output assertions

**All topologies:**
- `cluster_id`, `vcn_id`, `worker_subnet_id`, `worker_nsg_id`, `control_plane_subnet_id`, `control_plane_nsg_id`, `int_lb_subnet_id`, `int_lb_nsg_id`, `worker_ops_pool_id` are valid OCIDs
- `cluster_private_endpoint` starts with `https://`

**Public topologies (`public-*`):**
- `cluster_public_endpoint` starts with `https://`
- `pub_lb_subnet_id`, `pub_lb_nsg_id` are valid OCIDs

**Private topologies (`private-*`):**
- `cluster_public_endpoint` is empty
- `bastion_service_id` is a valid OCID
- `oke_private_endpoint_ip` is a valid IPv4

**FSS topologies (`*fss*`):**
- `fss_file_system_id`, `fss_nsg_id`, `fss_subnet_id` are valid OCIDs
- `fss_mount_target_ip` is a valid IPv4
- `fss_export_path` matches `/oke-gpu-*`
- FSS PersistentVolume resource exists in state (ORM: `kubernetes_persistent_volume_v1.fss`)

**Lustre topologies (`*lustre*`):**
- `lustre_subnet_id`, `lustre_nsg_id`, `lustre_file_system_id` are valid OCIDs
- `lustre_management_service_address` is a valid IPv4
- Lustre PersistentVolume resource exists in state (ORM: `kubectl_manifest.lustre_pv`)

**Monitoring topologies (`*monitoring*`):**
- `pub_lb_subnet_id`, `pub_lb_nsg_id` are valid OCIDs
- `grafana_url` starts with `http`
- `grafana_admin_password` is not empty

### Health checks (all topologies)

**Cluster:**
- API server connectivity (`kubectl cluster-info`)
- Node count matches expected pool sizes (30 min timeout, polls every 30s)
- All nodes Ready
- CoreDNS and kube-proxy pods Ready
- All kube-system pods Running or Completed

**Network:**
- Pod-to-pod connectivity (httpd server pod + wget client pod)
- DNS resolution (`nslookup kubernetes.default.svc.cluster.local`)

**GPU** (skipped if no GPU/RDMA pools)**:**
- `nvidia.com/gpu` or `amd.com/gpu` resources advertised on nodes

**FSS** (`*fss*` topologies only)**:**
- PVC binds to `fss-pv`
- CSI write: writer pod writes file via PVC
- CSI read: reader pod reads back on same node
- OS-level mount: hostPath reader verifies cloud-init NFS mount serves the same data

**Lustre** (`*lustre*` topologies only)**:**
- PVC binds to `lustre-pv`
- CSI write: writer pod writes file via PVC
- CSI read: reader pod reads back on same node
- OS-level mount: hostPath reader verifies cloud-init Lustre mount (60s retry loop for cache coherency)

**Monitoring** (`*monitoring*` topologies only)**:**
- Grafana API responds 200 (up to 30 retries in ORM, 60 in TF)
- Dashboards exist (count > 0)
- Prometheus queryable via Grafana (`up` query returns `success`)
- node-exporter DaemonSet desired == ready

All test pods include `nvidia.com/gpu` and `amd.com/gpu` tolerations.

## Notes
- The default suite (no `TFVARS_FILE`) sets `create_policies=false` to avoid tenancy-level policy creation. When using a var file, set this explicitly if needed.
- For instance principal runs, set `OCI_CLI_AUTH=instance_principal` when using monitoring tests so the `oci` CLI can authenticate.
- Optional test flags (`RUN_FSS_TESTS`, `RUN_LUSTRE_TESTS`, `RUN_MONITORING_TESTS`) are required to run those tests; missing flags will skip the test.
- Private topologies use OCI Bastion Service for CI health checks. The CI runner generates an ephemeral SSH keypair, creates a bastion port-forwarding session, and tunnels kubectl through it. No stored SSH keys are needed.
