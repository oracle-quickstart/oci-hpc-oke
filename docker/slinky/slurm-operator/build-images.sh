#!/usr/bin/env bash
set -euo pipefail

registry="${REGISTRY:-iad.ocir.io/idxzjcdglx2s/slurm-operator}"
platform="${PLATFORM:-linux/amd64}"
output="${OUTPUT:-push}"
build_version="${BUILD_VERSION:-2026-06-15.1}"
builder="${BUILDER:-}"

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
  local context="$1"
  local tag="$2"
  shift 2

  echo "== Building ${registry}:${tag} from ${context} =="
  docker buildx build \
    "${builder_args[@]}" \
    --platform "${platform}" \
    -t "${registry}:${tag}" \
    "$@" \
    "${output_args[@]}" \
    "${context}"
}

build_image controller/slurmctld-pmix "slurmctld-pmix-26.05.1-ubuntu24.04-${build_version}"
build_image controller/slurmctld-pmix-sssd-nss "slurmctld-pmix-sssd-nss-26.05.1-ubuntu24.04-${build_version}" \
  --build-arg "SLURMCTLD_PMIX_IMAGE=${registry}:slurmctld-pmix-26.05.1-ubuntu24.04-${build_version}"
build_image login/login-pyxis "login-pyxis-26.05.1-ubuntu24.04-${build_version}"
build_image workers/nvidia/slurmd-nvml-core "slurmd-nvml-core-26.05.1-ubuntu24.04-${build_version}"
build_image workers/nvidia/slurmd-nvml-nccl "slurmd-nvml-nccl-26.05.1-ubuntu24.04-${build_version}" \
  --build-arg "BASE_SLURMD_IMAGE=${registry}:slurmd-nvml-core-26.05.1-ubuntu24.04-${build_version}"
build_image workers/nvidia/slurmd-nvml-nccl-pyxis "slurmd-nvml-nccl-pyxis-26.05.1-ubuntu24.04-${build_version}" \
  --build-arg "BASE_SLURMD_IMAGE=${registry}:slurmd-nvml-nccl-26.05.1-ubuntu24.04-${build_version}"
build_image workers/amd/slurmd-rocm-rccl "slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-${build_version}"
build_image workers/amd/slurmd-rocm-rccl-pyxis "slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-pyxis-${build_version}" \
  --build-arg "BASE_IMAGE=${registry}:slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-${build_version}"
