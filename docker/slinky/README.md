# Slinky Dockerfiles

This directory collects the custom Dockerfiles used by the Slinky deployment
templates. The Slurm operator image bundle lives under `slurm-operator/`.

## Current Version Set

Target for now:

| Item | Version |
| --- | --- |
| Slurm Operator chart | `1.1.1` |
| Slurm chart | `1.1.1` |
| Slurm image family | `25.11.6-ubuntu24.04` |
| Custom image registry | `iad.ocir.io/idxzjcdglx2s/slurm-operator` |
| Custom image build suffix | `2026-06-16.0` |

The `1.1.1` Slurm chart defaults to upstream `25.11-ubuntu24.04` images. For
the custom images in this repo, pin the full Slurm patch level to `25.11.6` so
the rebuilt plugins match the upstream 25.11.6 payloads.

## 25.11 Ubuntu 24.04 Images

### Upstream Images Available

These images are published by Slinky and do not need to be built in this repo.

| Role | Image |
| --- | --- |
| Operator manager | `ghcr.io/slinkyproject/slurm-operator:1.1.1` |
| Operator webhook | `ghcr.io/slinkyproject/slurm-operator-webhook:1.1.1` |
| Controller base | `ghcr.io/slinkyproject/slurmctld:25.11.6-ubuntu24.04` |
| REST API | `ghcr.io/slinkyproject/slurmrestd:25.11.6-ubuntu24.04` |
| Accounting | `ghcr.io/slinkyproject/slurmdbd:25.11.6-ubuntu24.04` |
| Login base and SSSD sidecar | `ghcr.io/slinkyproject/login:25.11.6-ubuntu24.04` |
| Login Pyxis payload | `ghcr.io/slinkyproject/login-pyxis:25.11.6-ubuntu24.04` |
| Worker base | `ghcr.io/slinkyproject/slurmd:25.11.6-ubuntu24.04` |
| Worker Pyxis payload | `ghcr.io/slinkyproject/slurmd-pyxis:25.11.6-ubuntu24.04` |

If we choose a patch tag such as `25.11.6-ubuntu24.04`, switch the whole Slurm
stack together. Do not mix `25.11`, `25.11.x`, `26.05`, and `26.05.x` images in
one deployment.

### Derived Images Built

These 25.11.6 custom images are built and pushed in OCIR.

| Role | Dockerfile | Target image | Platforms |
| --- | --- | --- | --- |
| Controller with PMIx | `slurm-operator/controller/slurmctld-pmix/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmctld-pmix-25.11.6-ubuntu24.04-2026-06-16.0` | `linux/amd64`, `linux/arm64` |
| Controller with PMIx plus SSSD/NSS | `slurm-operator/controller/slurmctld-pmix-sssd-nss/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmctld-pmix-sssd-nss-25.11.6-ubuntu24.04-2026-06-16.0` | `linux/amd64`, `linux/arm64` |
| Login with Pyxis, Enroot, and login tools | `slurm-operator/login/login-pyxis/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:login-pyxis-25.11.6-ubuntu24.04-2026-06-16.0` | `linux/amd64`, `linux/arm64` |
| NVIDIA worker base with NVML AutoDetect plugins | `slurm-operator/workers/nvidia/slurmd-nvml-core/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-nvml-core-25.11.6-ubuntu24.04-2026-06-16.0` | `linux/amd64`, `linux/arm64` |
| NVIDIA worker with NCCL tests and HPCX payload | `slurm-operator/workers/nvidia/slurmd-nvml-nccl/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-nvml-nccl-25.11.6-ubuntu24.04-2026-06-16.0` | `linux/amd64`, `linux/arm64` |
| NVIDIA worker with NCCL plus Pyxis/Enroot | `slurm-operator/workers/nvidia/slurmd-nvml-nccl-pyxis/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-nvml-nccl-pyxis-25.11.6-ubuntu24.04-2026-06-16.0` | `linux/amd64`, `linux/arm64` |

The current AMD worker Dockerfiles build from the RCCL test image
`iad.ocir.io/idxzjcdglx2s/rccl-tests:rocm-7.1.1-ubuntu22.04-rccl-2.27.7-011826.1`.
They can be moved to Slurm `25.11`, but they are not Ubuntu 24.04 images until
the ROCm/RCCL base image is also moved to Ubuntu 24.04.

| Role | Dockerfile | Target image if keeping current AMD base | Platforms |
| --- | --- | --- | --- |
| AMD worker with ROCm/RCCL and SSSD/NSS | `slurm-operator/workers/amd/slurmd-rocm-rccl/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-rocm-rccl-25.11.6-rocm7.1.1-sssd-2026-06-16.0` | `linux/amd64` |
| AMD worker with ROCm/RCCL plus Pyxis/Enroot | `slurm-operator/workers/amd/slurmd-rocm-rccl-pyxis/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-rocm-rccl-25.11.6-rocm7.1.1-sssd-pyxis-2026-06-16.0` | `linux/amd64` |

### Current OCIR Status

OCIR now has the `25.11.6` tags listed above. The non-AMD images were built as
multi-platform manifests for `linux/amd64` and `linux/arm64`. The AMD ROCm/RCCL
images were built for `linux/amd64` only.

## Existing 26.05 Custom Images

These tags exist in OCIR but are not the current target.

| Role | Existing tag |
| --- | --- |
| Controller with PMIx | `slurmctld-pmix-26.05-ubuntu24.04-2026-06-15.0` |
| Controller with PMIx | `slurmctld-pmix-26.05.1-ubuntu24.04-2026-06-15.1` |
| Controller with PMIx | `slurmctld-pmix-26.05.1-ubuntu26.04-2026-06-16.1` |
| Controller with PMIx plus SSSD/NSS | `slurmctld-pmix-sssd-nss-26.05-ubuntu24.04-2026-06-15.0` |
| Controller with PMIx plus SSSD/NSS | `slurmctld-pmix-sssd-nss-26.05.1-ubuntu24.04-2026-06-15.1` |
| Controller with PMIx plus SSSD/NSS | `slurmctld-pmix-sssd-nss-26.05.1-ubuntu26.04-2026-06-16.1` |
| Login with Pyxis | `login-pyxis-26.05-ubuntu24.04-2026-06-15.0` |
| Login with Pyxis | `login-pyxis-26.05.1-ubuntu24.04-2026-06-15.1` |
| Login with Pyxis | `login-pyxis-26.05.1-ubuntu26.04-2026-06-16.1` |
| NVIDIA worker base | `slurmd-nvml-core-26.05-ubuntu24.04-2026-06-15.0` |
| NVIDIA worker base | `slurmd-nvml-core-26.05.1-ubuntu24.04-2026-06-15.1` |
| NVIDIA worker base | `slurmd-nvml-core-26.05.1-ubuntu26.04-2026-06-16.1` |
| NVIDIA worker base | `slurmd-nvml-core-26.05.1-ubuntu26.04-2026-06-16.2` |
| NVIDIA worker with NCCL | `slurmd-nvml-nccl-26.05-ubuntu24.04-2026-06-15.0` |
| NVIDIA worker with NCCL | `slurmd-nvml-nccl-26.05.1-ubuntu24.04-2026-06-15.1` |
| NVIDIA worker with NCCL | `slurmd-nvml-nccl-26.05.1-ubuntu26.04-2026-06-16.1` |
| NVIDIA worker with NCCL | `slurmd-nvml-nccl-26.05.1-ubuntu26.04-2026-06-16.2` |
| NVIDIA worker with NCCL plus Pyxis | `slurmd-nvml-nccl-pyxis-26.05-ubuntu24.04-2026-06-15.0` |
| NVIDIA worker with NCCL plus Pyxis | `slurmd-nvml-nccl-pyxis-26.05.1-ubuntu24.04-2026-06-15.1` |
| NVIDIA worker with NCCL plus Pyxis | `slurmd-nvml-nccl-pyxis-26.05.1-ubuntu26.04-2026-06-16.1` |
| NVIDIA worker with NCCL plus Pyxis | `slurmd-nvml-nccl-pyxis-26.05.1-ubuntu26.04-2026-06-16.2` |
| AMD worker with RCCL | `slurmd-rocm-rccl-26.05-rocm7.1.1-sssd-2026-06-15.0` |
| AMD worker with RCCL | `slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-2026-06-15.1` |
| AMD worker with RCCL | `slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-2026-06-16.1` |
| AMD worker with RCCL plus Pyxis | `slurmd-rocm-rccl-26.05-rocm7.1.1-sssd-pyxis-2026-06-15.0` |
| AMD worker with RCCL plus Pyxis | `slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-pyxis-2026-06-15.1` |
| AMD worker with RCCL plus Pyxis | `slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-pyxis-2026-06-16.1` |

The `26.05.1-ubuntu26.04-2026-06-16.1` controller and login images, plus the
`26.05.1-ubuntu26.04-2026-06-16.2` NVIDIA worker images, are multi-platform
manifests for `linux/amd64` and `linux/arm64`. The `.2` NVIDIA worker tags
rebuild the Slurm 26.05.1 Ubuntu 26.04 chain with `--disable-pam` instead of the
removed `--without-pam` configure option. The AMD ROCm/RCCL images in that set
are `linux/amd64` only and still inherit from the ROCm/RCCL Ubuntu 22.04 base
image, so their tags intentionally use `rocm7.1.1` instead of `ubuntu26.04`.

## Layout

| Path | Image role | Copied from |
| --- | --- | --- |
| `slurm-operator/operator/slurm-operator/Dockerfile` | Slinky Slurm operator manager and webhook images | `../slurm-operator-oke/Dockerfile` |
| `slurm-operator/controller/slurmctld-pmix/Dockerfile` | Base controller with PMIx support | `image-builder:/home/ubuntu/slurmctld-pmix/Dockerfile` |
| `slurm-operator/controller/slurmctld-pmix-sssd-nss/Dockerfile` | Default controller with PMIx plus SSSD/NSS client support | `image-builder:/home/ubuntu/slurmctld-pmix-sssd-nss/Dockerfile` |
| `slurm-operator/login/login-pyxis/Dockerfile` | Default login image with Pyxis, Enroot, and login tools | `image-builder:/home/ubuntu/login-pyxis/Dockerfile` |
| `slurm-operator/workers/nvidia/slurmd-nvml-core/Dockerfile` | NVIDIA worker base with Slurm NVML AutoDetect plugins | `image-builder:/home/ubuntu/slurmd-nvml-gb200/Dockerfile` |
| `slurm-operator/workers/nvidia/slurmd-nvml-nccl/Dockerfile` | NVIDIA worker with NCCL tests and HPCX payload | `image-builder:/home/ubuntu/slurmd-nvml-nccl/Dockerfile` |
| `slurm-operator/workers/nvidia/slurmd-nvml-nccl-pyxis/Dockerfile` | Default NVIDIA worker with NCCL plus Pyxis/Enroot | `image-builder:/home/ubuntu/builds/slurmd-nvml-nccl-pyxis/Dockerfile` |
| `slurm-operator/workers/amd/slurmd-rocm-rccl/Dockerfile` | Default AMD worker with ROCm/RCCL and SSSD/NSS | `image-builder:/home/ubuntu/slurmd-rocm-rccl/Dockerfile` |
| `slurm-operator/workers/amd/slurmd-rocm-rccl-pyxis/Dockerfile` | AMD worker variant with ROCm/RCCL plus Pyxis/Enroot | `image-builder:/home/ubuntu/slurmd-rocm-rccl-pyxis/Dockerfile` |

## Build Notes

- Run `slurm-operator/build-images.sh` from `docker/slinky/slurm-operator` to
  rebuild and push the derived runtime images. Set `REGISTRY`, `PLATFORM`, or
  `OUTPUT=load` to override the defaults. Image tags use a dated build suffix;
  set `BUILD_VERSION=YYYY-MM-DD.X` to increment it.
- `slurmctld-pmix-sssd-nss` builds on `slurmctld-pmix`.
- `slurmd-nvml-nccl-pyxis` builds on `slurmd-nvml-nccl`, which builds on
  `slurmd-nvml-core`.
- `slurmd-rocm-rccl-pyxis` builds on `slurmd-rocm-rccl`.
- Upstream chart images such as `ghcr.io/slinkyproject/login`,
  `ghcr.io/slinkyproject/slurmrestd`, `ghcr.io/slinkyproject/slurmdbd`, and
  external images such as `jpgouin/openldap` are not copied here because their
  Dockerfiles are not owned by this repository.
- The operator Dockerfile is a reference copy and still expects the Slurm
  operator source tree as its build context.

## Template Versioning

Terraform uses `slinky_image_profile` as the version switch for generated Slinky
values. The default profile is `25.11.6-ubuntu24.04`; when chart and image tag
variables are left as `auto`, Terraform resolves them from
`local.slinky_image_profiles` in `terraform/slinky.tf`.

Supported profiles:

| Profile | Notes |
| --- | --- |
| `25.11.6-ubuntu24.04` | Current default target. |
| `26.05-ubuntu24.04` | Existing OCIR 26.05 custom image family. |
| `26.05.1-ubuntu24.04` | Existing OCIR 26.05.1 Ubuntu 24.04 custom image family. |
| `26.05.1-ubuntu26.04` | Existing OCIR 26.05.1 Ubuntu 26.04 custom controller, login, and NVIDIA worker image family. Accounting, REST API, and SSSD sidecar stay on the upstream 26.05 Ubuntu 24.04 tags. |

The existing advanced repository and tag variables remain escape hatches. Set a
specific chart version or image tag only when testing a one-off image. Otherwise
leave them as `auto` so the controller, login, accounting, REST API, SSSD
sidecar, and worker images stay on the same tested Slurm release.

To add a new supported release, add a profile entry to
`local.slinky_image_profiles`, add the profile name to the
`slinky_image_profile` validation and Resource Manager enum, and keep all tags in
that profile on the same Slurm release and OS family.

That gives the normal path a single switch while preserving advanced overrides
for testing.
