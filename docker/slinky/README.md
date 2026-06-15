# Slinky Dockerfiles

This directory collects the custom Dockerfiles used by the Slinky deployment
templates. The Slurm operator image bundle lives under `slurm-operator/`.

## Layout

| Path | Image role | Image/tag reference | Copied from |
| --- | --- | --- | --- |
| `slurm-operator/operator/slurm-operator/Dockerfile` | Slinky Slurm operator manager and webhook images | `ghcr.io/slinkyproject/slurm-operator:*`, `ghcr.io/slinkyproject/slurm-operator-webhook:*` | `../slurm-operator-oke/Dockerfile` |
| `slurm-operator/controller/slurmctld-pmix/Dockerfile` | Base controller with PMIx support | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmctld-pmix-26.05.1-ubuntu24.04-2026-06-15.1` | `image-builder:/home/ubuntu/slurmctld-pmix/Dockerfile` |
| `slurm-operator/controller/slurmctld-pmix-sssd-nss/Dockerfile` | Default controller with PMIx plus SSSD/NSS client support | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmctld-pmix-sssd-nss-26.05.1-ubuntu24.04-2026-06-15.1` | `image-builder:/home/ubuntu/slurmctld-pmix-sssd-nss/Dockerfile` |
| `slurm-operator/login/login-pyxis/Dockerfile` | Default login image with Pyxis, Enroot, and login tools | `iad.ocir.io/idxzjcdglx2s/slurm-operator:login-pyxis-26.05.1-ubuntu24.04-2026-06-15.1` | `image-builder:/home/ubuntu/login-pyxis/Dockerfile` |
| `slurm-operator/workers/nvidia/slurmd-nvml-core/Dockerfile` | NVIDIA worker base with Slurm NVML AutoDetect plugins | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-nvml-core-26.05.1-ubuntu24.04-2026-06-15.1` | `image-builder:/home/ubuntu/slurmd-nvml-gb200/Dockerfile` |
| `slurm-operator/workers/nvidia/slurmd-nvml-nccl/Dockerfile` | NVIDIA worker with NCCL tests and HPCX payload | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-nvml-nccl-26.05.1-ubuntu24.04-2026-06-15.1` | `image-builder:/home/ubuntu/slurmd-nvml-nccl/Dockerfile` |
| `slurm-operator/workers/nvidia/slurmd-nvml-nccl-pyxis/Dockerfile` | Default NVIDIA worker with NCCL plus Pyxis/Enroot | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-nvml-nccl-pyxis-26.05.1-ubuntu24.04-2026-06-15.1` | `image-builder:/home/ubuntu/builds/slurmd-nvml-nccl-pyxis/Dockerfile` |
| `slurm-operator/workers/amd/slurmd-rocm-rccl/Dockerfile` | Default AMD worker with ROCm/RCCL and SSSD/NSS | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-2026-06-15.1` | `image-builder:/home/ubuntu/slurmd-rocm-rccl/Dockerfile` |
| `slurm-operator/workers/amd/slurmd-rocm-rccl-pyxis/Dockerfile` | AMD worker variant with ROCm/RCCL plus Pyxis/Enroot | `iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-pyxis-2026-06-15.1` | `image-builder:/home/ubuntu/slurmd-rocm-rccl-pyxis/Dockerfile` |

## Notes

- The deployment defaults are in `terraform/variables.tf` and
  `terraform/slinky.tf`.
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
