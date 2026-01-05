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

Optional:
- `OCI_PROFILE` (defaults to the OCI CLI `DEFAULT` profile)
- `OCI_COMPARTMENT_OCID` (defaults to the provided compartment OCID)

`TF_VAR_*` equivalents are also accepted for the required Terraform inputs.
If `TFVARS_FILE` is set, required inputs can come from the var file instead of env.
Missing required inputs will fail the test run.

## Run
From the repo root:

```sh
cd test

go mod tidy

go test ./... -run TestValidation -timeout 30m

go test ./... -run TestCoreProvisioning -timeout 2h
```

## Using tfvars files
Set `TFVARS_FILE` to a comma-separated list of var files (relative or absolute paths). Relative paths are resolved to absolute paths before invoking Terraform. When set, the test harness does not force the default feature flags, so include any desired toggles in your var file (for example, `create_policies=false` if you lack tenancy permissions).

```sh
TFVARS_FILE=./vars/core-provisioning.tfvars go test ./... -run TestCoreProvisioning -timeout 2h
```

Example with the provided templates (edit the placeholder values first):

```sh
TFVARS_FILE=./tfvars/base.tfvars,./tfvars/core-provisioning.tfvars go test ./... -run TestCoreProvisioning -timeout 2h
```

Monitoring example:

```sh
TFVARS_FILE=./tfvars/base.tfvars,./tfvars/core-provisioning.tfvars,./tfvars/monitoring.tfvars go test ./... -run TestMonitoring -timeout 3h
```

## Optional suites
Storage (FSS & Lustre):

```sh
RUN_FSS_TESTS=1 FSS_AD=<ad-name> go test ./... -run TestStorageFSS -timeout 3h
RUN_LUSTRE_TESTS=1 go test ./... -run TestStorageLustre -timeout 3h
```

Monitoring (provider path):

```sh
RUN_MONITORING_TESTS=1 go test ./... -run TestMonitoring -timeout 3h
```

Operator path (manual only):

```sh
RUN_OPERATOR_TESTS=1 go test ./... -run TestOperator -timeout 4h
```

## Retry Configuration

Configure retry behavior for flaky OCI API calls:

| Variable | Default | Description |
|----------|---------|-------------|
| `TERRATEST_MAX_RETRIES` | `3` | Maximum number of retries for retryable Terraform errors |
| `TERRATEST_RETRY_SLEEP_SECONDS` | `15` | Seconds to wait between retries |

Example with increased retries for unstable environments:

```sh
TERRATEST_MAX_RETRIES=5 TERRATEST_RETRY_SLEEP_SECONDS=30 go test ./... -run TestCoreProvisioning -timeout 2h
```

## Notes
- The default suite (no `TFVARS_FILE`) sets `create_policies=false` to avoid tenancy-level policy creation. When using a var file, set this explicitly if needed.
- For instance principal runs, set `OCI_CLI_AUTH=instance_principal` when using monitoring or operator tests so the `oci` CLI can authenticate.
- Optional test flags (`RUN_FSS_TESTS`, `RUN_LUSTRE_TESTS`, `RUN_MONITORING_TESTS`, `RUN_OPERATOR_TESTS`) are required to run those tests; missing flags now fail the test run.
- Validation tests run in parallel to reduce total test time.
