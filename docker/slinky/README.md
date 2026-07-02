# Slinky Dockerfiles

This directory collects the custom Dockerfiles used by the Slinky deployment
templates. The Slurm operator image bundle lives under `slurm-operator/`.

## Current Version Set

Target for now:

| Item | Version |
| --- | --- |
| Slurm Operator chart | `1.2.0` |
| Slurm chart | `1.2.0` |
| Slurm image family | `26.05.1-ubuntu26.04` |
| Custom image registry | `iad.ocir.io/idxzjcdglx2s/slurm-operator` |
| Custom image build suffix | `2026-07-02.0` |

The `1.2.0` Slurm chart defaults to upstream `26.05-ubuntu26.04` images, so the
custom image family now matches the chart default. Pin the full Slurm patch
level to `26.05.1` so the rebuilt plugins match the upstream 26.05.1 payloads
(chart `1.2.0` supports Slurm `25.11` and later).

## 26.05.1 Ubuntu 26.04 Images

### Upstream Images Available

These are the images Slinky publishes upstream. We no longer pull them at
deploy time: the operator/webhook and the SlurmDBD/slurmrestd/login control-plane
images are rebuilt from source (see "Control-Plane Images Built from Upstream
Source"), and the controller/login/worker base layers are rebuilt from source
(see "Base Images Built from Upstream Source"). The table is kept as a reference
of the upstream equivalents we mirror.

| Role | Image |
| --- | --- |
| Operator manager | `ghcr.io/slinkyproject/slurm-operator:1.2.0` |
| Operator webhook | `ghcr.io/slinkyproject/slurm-operator-webhook:1.2.0` |
| Controller base | `ghcr.io/slinkyproject/slurmctld:26.05.1-ubuntu26.04` |
| REST API | `ghcr.io/slinkyproject/slurmrestd:26.05.1-ubuntu26.04` |
| Accounting | `ghcr.io/slinkyproject/slurmdbd:26.05.1-ubuntu26.04` |
| Login base and SSSD sidecar | `ghcr.io/slinkyproject/login:26.05.1-ubuntu26.04` |
| Login Pyxis payload | `ghcr.io/slinkyproject/login-pyxis:26.05.1-ubuntu26.04` |
| Worker base | `ghcr.io/slinkyproject/slurmd:26.05.1-ubuntu26.04` |
| Worker Pyxis payload | `ghcr.io/slinkyproject/slurmd-pyxis:26.05.1-ubuntu26.04` |

If we choose a patch tag such as `26.05.1-ubuntu26.04`, switch the whole Slurm
stack together. Do not mix `25.11`, `25.11.x`, `26.05`, and `26.05.x` images in
one deployment.

### Derived Images Built

These 26.05.1 custom images are built and pushed in OCIR by `build-images.sh`.
The controller, login, and NVIDIA worker images build FROM the from-source base
images (see "Base Images Built from Upstream Source") instead of
`ghcr.io/slinkyproject`, so the whole stack comes from one registry.

| Role | Dockerfile | Target image | Platforms |
| --- | --- | --- | --- |
| Controller with PMIx | `slurm-operator/controller/slurmctld-pmix/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmctld-pmix-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |
| Controller with PMIx plus SSSD/NSS | `slurm-operator/controller/slurmctld-pmix-sssd-nss/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmctld-pmix-sssd-nss-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |
| Login with Pyxis, Enroot, and login tools | `slurm-operator/login/login-pyxis/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:login-pyxis-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |
| NVIDIA worker base with NVML AutoDetect plugins | `slurm-operator/workers/nvidia/slurmd-nvml-core/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-nvml-core-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |
| NVIDIA worker with NCCL tests and HPCX payload | `slurm-operator/workers/nvidia/slurmd-nvml-nccl/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-nvml-nccl-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |
| NVIDIA worker with NCCL plus Pyxis/Enroot | `slurm-operator/workers/nvidia/slurmd-nvml-nccl-pyxis/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-nvml-nccl-pyxis-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |

The current AMD worker Dockerfiles build from the RCCL test image
`iad.ocir.io/idxzjcdglx2s/rccl-tests:rocm-7.1.1-ubuntu22.04-rccl-2.27.7-011826.1`.
They build Slurm `26.05.1` from source, but they are not Ubuntu 26.04 images
until the ROCm/RCCL base image is also moved off Ubuntu 22.04, so their tags
use `rocm7.1.1` instead of an Ubuntu flavor.

| Role | Dockerfile | Target image if keeping current AMD base | Platforms |
| --- | --- | --- | --- |
| AMD worker with ROCm/RCCL and SSSD/NSS | `slurm-operator/workers/amd/slurmd-rocm-rccl/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-2026-07-02.0` | `linux/amd64` |
| AMD worker with ROCm/RCCL plus Pyxis/Enroot | `slurm-operator/workers/amd/slurmd-rocm-rccl-pyxis/Dockerfile` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-pyxis-2026-07-02.0` | `linux/amd64` |

### Control-Plane Images Built from Upstream Source

These otherwise come straight from `ghcr.io/slinkyproject`. They are rebuilt
from upstream source into our registry so the whole stack comes from one place
(the `build-images.sh` table above covers the layered custom images).
`build-control-plane-images.sh` builds these on the image-builder, multi-platform
(`linux/amd64`, `linux/arm64`):

- `slurmdbd`, `slurmrestd`, and `login` build from the vendored upstream assets
  in `slurm-operator/slurm-source/` (copied from `SlinkyProject/containers` at
  the per-directory refs listed in `slurm-source/README.md`) via Docker Bake --
  one multi-stage Dockerfile with per-component `--target` stages. The upstream Dockerfile shares
  the apt cache mount across arches, so each arch is built separately and combined
  into a multi-arch manifest.
- `operator` and `webhook` build from a pinned clone of
  `SlinkyProject/slurm-operator` @ `v1.2.0` (its Dockerfile needs the Go source
  tree, so it cannot be vendored standalone; a reference copy is at
  `slurm-operator/operator/slurm-operator/Dockerfile`). Go cross-compile, both
  arches in one pass.

| Role | Upstream source / target | Target image | Platforms |
| --- | --- | --- | --- |
| SlurmDBD (accounting) | `containers` target `slurmdbd` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmdbd-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |
| slurmrestd (REST API) | `containers` target `slurmrestd` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmrestd-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |
| Login / SSSD sidecar | `containers` target `login` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:login-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |
| Slinky operator | `slurm-operator` target `manager` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:1.2.0` | `linux/amd64`, `linux/arm64` |
| Slinky operator webhook | `slurm-operator` target `webhook` | `iad.ocir.io/idxzjcdglx2s/slurm-operator-webhook:1.2.0` | `linux/amd64`, `linux/arm64` |

The terraform `26.05.1-ubuntu26.04` image profile points SlurmDBD, slurmrestd,
and the SSSD sidecar at these tags, and the operator Helm values use the custom
operator/webhook images.

### Base Images Built from Upstream Source

The layered controller/login/NVIDIA worker Dockerfiles in `build-images.sh`
otherwise build FROM `ghcr.io/slinkyproject` base layers. These bases are rebuilt
from the same vendored `slurm-source/` assets so the layered images come entirely
from our registry. `build-base-images.sh` builds them on the image-builder,
multi-platform (`linux/amd64`, `linux/arm64`), using the same per-arch build and
combine as the control-plane script (the upstream Dockerfile shares the apt cache
mount across arches). The `login` base is produced by `build-control-plane-images.sh`
(it doubles as the deployed SSSD sidecar) and reused here.

| Role | Upstream target | Base image | Platforms |
| --- | --- | --- | --- |
| Controller base | `containers` target `slurmctld` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmctld-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |
| Worker base | `containers` target `slurmd` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |
| Worker Pyxis payload | `containers` target `slurmd_pyxis` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-pyxis-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |
| Login Pyxis payload | `containers` target `login_pyxis` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:login-pyxis-base-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |
| Login base / SSSD sidecar | `containers` target `login` | `iad.ocir.io/idxzjcdglx2s/slurm-operator:login-26.05.1-ubuntu26.04-2026-07-02.0` | `linux/amd64`, `linux/arm64` |

The `login_pyxis` target is tagged `login-pyxis-base` so it does not collide with
the deployed `login-pyxis` image. AMD workers already build entirely from source
(custom RCCL base), so they have no upstream base layer to rebuild.

### Current OCIR Status

OCIR now has the `26.05.1-ubuntu26.04-2026-07-02.0` tags listed above, built
from the latest vendored `SlinkyProject/containers` source. The non-AMD images
were built as multi-platform manifests for `linux/amd64` and `linux/arm64`. The
AMD ROCm/RCCL images were built for `linux/amd64` only.

## Other Existing Custom Images

These tags exist in OCIR but are not the current target. The
`25.11.6-ubuntu24.04-2026-06-19.0` family is the complete previous default set
(control-plane, bases, and layered images; referenced by the
`25.11.6-ubuntu24.04` profile), with AMD workers at
`slurmd-rocm-rccl-25.11.6-rocm7.1.1-sssd[-pyxis]-2026-06-16.0`.

| Role | Existing tag |
| --- | --- |
| Controller with PMIx | `slurmctld-pmix-26.05-ubuntu24.04-2026-06-15.0` |
| Controller with PMIx | `slurmctld-pmix-26.05.1-ubuntu26.04-2026-06-16.1` |
| Controller with PMIx plus SSSD/NSS | `slurmctld-pmix-sssd-nss-26.05-ubuntu24.04-2026-06-15.0` |
| Controller with PMIx plus SSSD/NSS | `slurmctld-pmix-sssd-nss-26.05.1-ubuntu26.04-2026-06-16.1` |
| Login with Pyxis | `login-pyxis-26.05-ubuntu24.04-2026-06-15.0` |
| Login with Pyxis | `login-pyxis-26.05.1-ubuntu26.04-2026-06-16.1` |
| NVIDIA worker base | `slurmd-nvml-core-26.05-ubuntu24.04-2026-06-15.0` |
| NVIDIA worker base | `slurmd-nvml-core-26.05.1-ubuntu26.04-2026-06-16.1` |
| NVIDIA worker base | `slurmd-nvml-core-26.05.1-ubuntu26.04-2026-06-16.2` |
| NVIDIA worker with NCCL | `slurmd-nvml-nccl-26.05-ubuntu24.04-2026-06-15.0` |
| NVIDIA worker with NCCL | `slurmd-nvml-nccl-26.05.1-ubuntu26.04-2026-06-16.1` |
| NVIDIA worker with NCCL | `slurmd-nvml-nccl-26.05.1-ubuntu26.04-2026-06-16.2` |
| NVIDIA worker with NCCL plus Pyxis | `slurmd-nvml-nccl-pyxis-26.05-ubuntu24.04-2026-06-15.0` |
| NVIDIA worker with NCCL plus Pyxis | `slurmd-nvml-nccl-pyxis-26.05.1-ubuntu26.04-2026-06-16.1` |
| NVIDIA worker with NCCL plus Pyxis | `slurmd-nvml-nccl-pyxis-26.05.1-ubuntu26.04-2026-06-16.2` |
| AMD worker with RCCL | `slurmd-rocm-rccl-26.05-rocm7.1.1-sssd-2026-06-15.0` |
| AMD worker with RCCL | `slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-2026-06-16.1` |
| AMD worker with RCCL plus Pyxis | `slurmd-rocm-rccl-26.05-rocm7.1.1-sssd-pyxis-2026-06-15.0` |
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

- Build order on the image-builder (all from `docker/slinky/slurm-operator`):
  1. `build-control-plane-images.sh` -- deployed SlurmDBD/slurmrestd/login plus
     operator/webhook (the `login` image doubles as the layered login base).
  2. `build-base-images.sh` -- the from-source `slurmctld`, `slurmd`,
     `slurmd-pyxis`, and `login-pyxis-base` bases that the layered images build FROM.
  3. `build-images.sh` -- the derived layered controller/login/NVIDIA/AMD images.
- Set `REGISTRY`, `PLATFORM`, or `OUTPUT=load` to override `build-images.sh`
  defaults. Image tags use a dated build suffix; set `BUILD_VERSION=YYYY-MM-DD.X`
  to increment it. `BASE_BUILD_VERSION` selects which from-source base tags the
  layered images build FROM; `AMD_BUILD_VERSION` pins the AMD worker tags.
- `slurmctld-pmix-sssd-nss` builds on `slurmctld-pmix`.
- `slurmd-nvml-nccl-pyxis` builds on `slurmd-nvml-nccl`, which builds on
  `slurmd-nvml-core`.
- `slurmd-rocm-rccl-pyxis` builds on `slurmd-rocm-rccl`.
- External images such as `jpgouin/openldap` are not copied here because their
  Dockerfiles are not owned by this repository.
- The operator Dockerfile is a reference copy and still expects the Slurm
  operator source tree as its build context.

## Template Versioning

Terraform uses `slinky_image_profile` as the version switch for generated Slinky
values. The default profile is `26.05.1-ubuntu26.04`; when chart and image tag
variables are left as `auto`, Terraform resolves them from
`local.slinky_image_profiles` in `terraform/slinky.tf`.

Supported profiles:

| Profile | Notes |
| --- | --- |
| `26.05.1-ubuntu26.04` | Current default target. Whole stack (control-plane, bases, layered images) built from the latest vendored containers source into OCIR. |
| `25.11.6-ubuntu24.04` | Previous default. Complete OCIR image family, kept for rollback. |
| `26.05-ubuntu24.04` | Older OCIR 26.05 custom image family. Accounting, REST API, and SSSD sidecar stay on the upstream `ghcr.io` 26.05 Ubuntu 24.04 tags. |

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
