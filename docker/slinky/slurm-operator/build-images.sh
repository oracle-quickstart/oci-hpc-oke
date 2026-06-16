#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

registry="${REGISTRY:-iad.ocir.io/idxzjcdglx2s/slurm-operator}"
platform="${PLATFORM:-linux/amd64,linux/arm64}"
amd_platform="${AMD_PLATFORM:-linux/amd64}"
output="${OUTPUT:-push}"
build_version="${BUILD_VERSION:-2026-06-16.0}"
builder="${BUILDER:-}"
slurm_version="${SLURM_VERSION:-25.11.6}"
slurm_os="${SLURM_OS:-ubuntu24.04}"
slurm_base_tag="${SLURM_BASE_TAG:-${slurm_version}-${slurm_os}}"
custom_version="${CUSTOM_VERSION:-${slurm_version}-${slurm_os}}"
parent_ubuntu_image="${PARENT_UBUNTU_IMAGE:-ubuntu:${slurm_os#ubuntu}}"
rocm_version="${ROCM_VERSION:-7.1.1}"
rccl_image="${RCCL_IMAGE:-iad.ocir.io/idxzjcdglx2s/rccl-tests:rocm-${rocm_version}-ubuntu22.04-rccl-2.27.7-011826.1}"

output_args=()
case "${output}" in
  push)
    output_args=(--push)
    ;;
  load)
    output_args=(--load)
    ;;
  none)
    output_args=()
    ;;
  *)
    echo "Unsupported OUTPUT=${output}; use push, load, or none." >&2
    exit 1
    ;;
esac

builder_args=()
if [ -n "${builder}" ]; then
  builder_args=(--builder "${builder}")
fi

build_image() {
  local image_platform="$1"
  local context="$2"
  local tag="$3"
  shift 3

  echo "== Building ${registry}:${tag} from ${context} =="
  docker buildx build \
    "${builder_args[@]}" \
    --platform "${image_platform}" \
    -t "${registry}:${tag}" \
    "$@" \
    "${output_args[@]}" \
    "${context}"
}

build_image "${platform}" controller/slurmctld-pmix "slurmctld-pmix-${custom_version}-${build_version}" \
  --build-arg "SLURMCTLD_IMAGE=ghcr.io/slinkyproject/slurmctld:${slurm_base_tag}"
build_image "${platform}" controller/slurmctld-pmix-sssd-nss "slurmctld-pmix-sssd-nss-${custom_version}-${build_version}" \
  --build-arg "SLURMCTLD_PMIX_IMAGE=${registry}:slurmctld-pmix-${custom_version}-${build_version}"
build_image "${platform}" login/login-pyxis "login-pyxis-${custom_version}-${build_version}" \
  --build-arg "BASE_LOGIN_IMAGE=ghcr.io/slinkyproject/login:${slurm_base_tag}" \
  --build-arg "PYXIS_LOGIN_IMAGE=ghcr.io/slinkyproject/login-pyxis:${slurm_base_tag}"
build_image "${platform}" workers/nvidia/slurmd-nvml-core "slurmd-nvml-core-${custom_version}-${build_version}" \
  --build-arg "SLURM_VERSION=${slurm_version}" \
  --build-arg "PARENT_IMAGE=${parent_ubuntu_image}" \
  --build-arg "BASE_SLURMD_IMAGE=ghcr.io/slinkyproject/slurmd:${slurm_base_tag}"
build_image "${platform}" workers/nvidia/slurmd-nvml-nccl "slurmd-nvml-nccl-${custom_version}-${build_version}" \
  --build-arg "BASE_SLURMD_IMAGE=${registry}:slurmd-nvml-core-${custom_version}-${build_version}"
build_image "${platform}" workers/nvidia/slurmd-nvml-nccl-pyxis "slurmd-nvml-nccl-pyxis-${custom_version}-${build_version}" \
  --build-arg "BASE_SLURMD_IMAGE=${registry}:slurmd-nvml-nccl-${custom_version}-${build_version}" \
  --build-arg "PYXIS_SLURMD_IMAGE=ghcr.io/slinkyproject/slurmd-pyxis:${slurm_base_tag}"

build_image "${amd_platform}" workers/amd/slurmd-rocm-rccl "slurmd-rocm-rccl-${slurm_version}-rocm${rocm_version}-sssd-${build_version}" \
  --build-arg "SLURM_VERSION=${slurm_version}" \
  --build-arg "BASE_RCCL_IMAGE=${rccl_image}"
build_image "${amd_platform}" workers/amd/slurmd-rocm-rccl-pyxis "slurmd-rocm-rccl-${slurm_version}-rocm${rocm_version}-sssd-pyxis-${build_version}" \
  --build-arg "SLURM_VERSION=${slurm_version}" \
  --build-arg "BASE_IMAGE=${registry}:slurmd-rocm-rccl-${slurm_version}-rocm${rocm_version}-sssd-${build_version}"
