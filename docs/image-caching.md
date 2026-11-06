# GPU image caching with kube-fledged

The stack uses [kube-fledged](https://github.com/senthilrch/kube-fledged/tree/v0.11.0) to pre-pull container images onto GPU nodes. It replaces the in-house `oci-hpc-oke-utils` prepuller DaemonSets. Caching remains opt-in and is independent of the utilities chart and RDMA/GMC settings.

## Enable and configure

```hcl
install_kube_fledged = true
# Defaults:
kube_fledged_chart_version     = "v0.11.0"
kube_fledged_refresh_frequency = "15m"
kube_fledged_pull_deadline     = "30m"
kube_fledged_image_pull_policy = "IfNotPresent"
```

Terraform installs two releases in the `kube-fledged` namespace:

1. `kube-fledged`: the pinned upstream controller, validating webhook, RBAC, and `imagecaches.kubefledged.io` CRD.
2. `oci-hpc-imagecaches`: one `kubefledged.io/v1alpha2` ImageCache per active image group, installed after the controller and Kueue (when enabled).

Both the local/Resource Manager provider path and the operator-host path use the same controller settings and image-cache values. On removal, image-cache resources are removed before the controller. Helm retains the upstream CRD; it is cluster-wide and may be used by other caches. No purge annotation is issued by the stack, so disabling the feature does not deliberately delete cached images.

The default groups preserve the old images and selectors:

| Group | Node selector | Image |
|---|---|---|
| `nvidia` | `nvidia.com/gpu: "true"` | `iad.ocir.io/idxzjcdglx2s/nccl-tests:cuda-13.1.1-ubuntu-24.04-nccl-2.29.3-020926.1` |
| `amd` | `amd.com/gpu: "true"` | `iad.ocir.io/idxzjcdglx2s/rccl-tests:rocm-7.1.1-ubuntu22.04-rccl-2.27.7-012126.1` |

Set `kube_fledged_image_groups` to replace the defaults. Omitted groups are disabled; `{}` creates no caches. Each active group requires a nonempty selector to avoid accidentally pulling large images onto every node.

```hcl
kube_fledged_image_groups = {
  training = {
    nodeSelector = { "nvidia.com/gpu" = "true" }
    images       = ["my-registry.example/training:v1"]
  }
}
kube_fledged_image_pull_secrets = ["registry-credentials"]
```

Registry credentials must already exist in `kube-fledged`. References are passed to both the upstream deployments and the ImageCache resources. Existing secrets in `kube-system` must be provisioned in the new namespace; secrets cannot be referenced across namespaces. OCI kubelet credential-provider access continues to depend on node configuration and IAM permissions.

Use immutable image tags or digests. With `IfNotPresent`, existing cached tags are reused; `Always` can be selected when mutable tags must be checked. Kubernetes image garbage collection can evict cached images; periodic refresh repopulates them. This feature does not reserve disk space or gate workload scheduling on cache readiness.

## Compatibility evaluation

The evaluation uses the published `v0.11.0` chart and its matching upstream source, including [pull-job generation](https://github.com/senthilrch/kube-fledged/blob/v0.11.0/pkg/images/image_helpers.go) and [refresh handling](https://github.com/senthilrch/kube-fledged/blob/v0.11.0/cmd/controller/app/controller.go).

| Existing behavior | kube-fledged behavior and migration |
|---|---|
| Separate NVIDIA and AMD image groups | Separate ImageCache resources retain the exact default image lists and selectors. |
| GPU taints tolerated | Upstream pull Jobs use an `Exists` toleration and target each selected node through `kubernetes.io/hostname`. Nodes must have that label. |
| `IfNotPresent` pulls | Same policy configured explicitly; no long-lived pause pod is required. |
| Registry secret references | ImageCache `spec.imagePullSecrets`; move credentials to `kube-fledged`. |
| Pull failure retries | Upstream Jobs have zero Job backoff. The controller reports failures; the next periodic refresh retries eligible caches. This replaces the old pod's indefinite pull backoff. |
| New nodes automatically get a DaemonSet pod | Refresh discovers nodes matching each selector; allow up to the refresh interval plus pull time. Node addition is not an immediate DaemonSet event. |
| Init containers require `sh` in cached images | Upstream copies an echo executable from a helper image into a shared volume and runs it in the target image. Verify helper/target architecture and executable compatibility for custom images. |
| DaemonSet custom affinity, pod resources, annotations, pause image | These have no direct ImageCache equivalent. Migrate exact-match scheduling constraints to per-group selectors. Do not assume arbitrary pod customization carries over. |
| Runtime support | Upstream lists containerd and CRI-O support. Pull Jobs use kubelet image pulling and do not mount the runtime socket. Explicit purge and removal of images from an existing cache use a runtime socket mounted into a Job and require separate validation. |
| Kueue integration | Cache Jobs have no queue label and the bundled Kueue configuration does not manage unlabeled Jobs. If enforcing namespace-wide queue management, exclude `kube-fledged`; cache Jobs must not require GPU quota. |

The chart renders `apps/v1`, `apiextensions.k8s.io/v1`, `admissionregistration.k8s.io/v1`, and the upstream custom API. Rendering against Kubernetes 1.36.4 is an offline check, not proof of controller compatibility on that release. Live acceptance is required on the actual OKE version and both worker runtimes in use.

Updating an existing ImageCache to remove an image causes upstream to launch image-deletion Jobs for the removed image. This differs from the old prepuller, which left obsolete images cached. Validate deletion on each worker runtime and account for its runtime-socket access requirements before changing image lists. Removing an entire ImageCache or disabling the feature does not request purge. Selector-only updates can report no images pulled; request a refresh afterward to populate newly selected nodes.

The upstream chart generates webhook TLS certificates valid for 365 days and restarts the webhook on Helm upgrade. Renew them with a controlled Helm upgrade before expiry, verify webhook admission afterward, and account for brief admission unavailability during certificate rotation. The chart has no controller/webhook readiness probes; Helm availability alone does not establish successful cache admission or image pulls. Keep one controller replica: this integration does not establish leader-election safety for multiple replicas.

## Migrate existing deployments

For Terraform deployments:

1. Move any manually customized image groups and credentials to the variables above. Editing the former utilities `values.yaml` is no longer a cache configuration path.
2. Set `install_kube_fledged = true`. Existing `install_image_prepuller = true` tfvars continue to enable caching through a deprecated alias; set the old flag false when switching to the new flag. Either true flag enables the feature.
3. Review and apply the Terraform plan. The utilities upgrade removes its prepuller DaemonSets; the new releases install the controller and ImageCache resources. These operations are not an atomic handover. Existing cached images remain on nodes, but pause new workload submissions until cache validation succeeds.
4. Run the completion check below and a representative warm-start workload. For rollback, restore the previous utilities chart/configuration after disabling both kube-fledged flags. Disabling both flags removes the kube-fledged releases.

For manual Helm deployments, move old `prepuller.groups` into `groups` in a cache values file and `prepuller.imagePullSecrets` into `imagePullSecrets`. The cache chart has no built-in groups: pass `terraform/files/kube-fledged/imagecaches.yaml` for the default groups, or your own values file for custom groups. This avoids Helm merging an old selector or unwanted default group into a custom configuration.

```bash
helm upgrade --install kube-fledged kube-fledged \
  --repo https://senthilrch.github.io/kubefledged-charts/ \
  --version v0.11.0 --namespace kube-fledged --create-namespace \
  -f terraform/files/kube-fledged/values.yaml --wait --timeout 600s
helm upgrade --install oci-hpc-imagecaches ./terraform/files/oci-hpc-imagecaches \
  --namespace kube-fledged -f my-cache-values.yaml --wait
```

After successful validation, upgrade the utilities chart with all `prepuller` values removed. It deliberately rejects `prepuller.enabled=true` instead of silently dropping caching. Do not use `--reuse-values` to carry the removed flag forward.

## Validate operations on OKE

Run against a disposable test cluster or explicitly selected OKE context. The check is read-only, waits up to 45 minutes by default, requires at least one matching Ready node per active group and rejects a completed operation that predates a matching node, and fails for missing caches, pending refreshes, incomplete operations, or reported failures. On a single-vendor cluster, disable the other default group before running it.

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get imagecaches -n kube-fledged
python3 scripts/validate-image-caches.py kube-fledged 2700
kubectl get imagecaches -n kube-fledged -o yaml
kubectl logs -n kube-fledged deployment/kube-fledged-controller --tail=100
```

Helm `--wait` waits for deployments, not for custom resource pull completion. A successful Terraform apply is therefore not a cache-readiness signal. The completion check catches no-node matches as well as reported image failures, but does not inspect every node's runtime cache or replace a warm-start test.

Complete this acceptance matrix on OKE before rollout:

| Scenario | Acceptance evidence |
|---|---|
| Default caches, on each available GPU vendor/runtime | Only selected nodes run pull Jobs; ImageCache reports `Succeeded`, with no `status.failures`; default images match the previous workflow. |
| Warm workload start | Run the existing NCCL/RCCL workload using the same immutable image and `IfNotPresent`, pinned to a tested GPU node. Inspect events for an already-present image and compare image/startup timings to a measured cold pull. |
| New or replacement GPU node | Add a test node with the existing selector and hostname label. After the next refresh, verify a successful pull on that node and repeat the warm-start test. |
| Bad tag and recovery | In a separate test group, configure a nonexistent tag. Confirm failure details after the deadline; correct the tag, request refresh, and verify recovery. |
| Registry outage / expired credentials | Confirm failures remain visible. Restore registry access/credentials, refresh, and verify success without reinstalling the controller. |
| Controller restart | Restart the controller during a test operation. Verify restart recovery and a subsequent refresh succeed; inspect `Aborted` operations rather than treating restart as success. |
| Refresh and garbage collection | Request refresh and verify completion time advances. On an isolated node, evict a test image through the runtime and confirm refresh pulls it again. |
| Image-list removal | On an isolated node/runtime, remove a test image from an existing group, inspect the resulting deletion Job and verify it succeeds. Confirm a remaining image can still start a workload. |
| Upgrade and disable | Upgrade both Helm releases and verify admission/pulls still work. Disable both Terraform flags; verify caches are deleted before the controller, old prepuller DaemonSets do not return, and no purge was requested. |

Request a refresh for a specific cache (the controller removes the annotation after processing):

```bash
kubectl annotate imagecache oci-hpc-imagecaches-nvidia -n kube-fledged \
  kubefledged.io/refresh-imagecache= --overwrite
python3 scripts/validate-image-caches.py kube-fledged 2700
```

Inspect `status.failures`, pull Job events, controller logs, registry access, disk space, and node readiness on failure. Completed Jobs are deleted by default, so the ImageCache status is the durable diagnostic source until the next operation updates it. Refresh after correcting invalid cache specifications; upstream skips periodic retries for cache-spec validation failures. Do not use the purge annotation as part of routine disable/rollback: it deliberately deletes images from nodes.
