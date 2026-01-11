# Terratest

These tests run Terraform against OCI using API key auth by default, with optional instance principal support. The default suite covers validation failures and a minimal core provisioning apply. Storage, monitoring, and operator-path suites are optional and gated by env flags.

## Prereqs
- Terraform installed and available on PATH.
- Go installed (1.21+ recommended).
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
Set `TFVARS_FILE` to a comma-separated list of var files (relative or absolute paths). When set, the test harness does not force the default feature flags, so include any desired toggles in your var file (for example, `create_policies=false` if you lack tenancy permissions).

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

## Optional suites
Storage (FSS & Lustre):

```sh
RUN_FSS_TESTS=1 go test -count=1 ./... -run TestStorageFSS -timeout 3h
RUN_LUSTRE_TESTS=1 go test -count=1 ./... -run TestStorageLustre -timeout 3h
```

Both FSS and Lustre default to `worker_ops_ad`. Override with `FSS_AD` or `LUSTRE_AD` if needed.

Monitoring (provider path):

```sh
RUN_MONITORING_TESTS=1 go test -count=1 ./... -run TestMonitoring -timeout 3h
```

## Notes
- The default suite (no `TFVARS_FILE`) sets `create_policies=false` to avoid tenancy-level policy creation. When using a var file, set this explicitly if needed.
- For instance principal runs, set `OCI_CLI_AUTH=instance_principal` when using monitoring tests so the `oci` CLI can authenticate.
- Optional test flags (`RUN_FSS_TESTS`, `RUN_LUSTRE_TESTS`, `RUN_MONITORING_TESTS`) are required to run those tests; missing flags will fail the test run.
