#!/usr/bin/env bash
#
# Build the from-source Slurm base images that build-images.sh layers on top of:
# slurmctld, slurmd, slurmd-pyxis, and login-pyxis. Upstream's layered custom
# Dockerfiles (controller, login, NVIDIA workers) otherwise pull these bases
# straight from ghcr.io/slinkyproject; building them here keeps the whole stack
# in one registry, matching the control-plane images from build-control-plane-images.sh.
#
# The login base is NOT built here: it is already produced by
# build-control-plane-images.sh (the deployed SSSD login sidecar) and reused as
# BASE_LOGIN_IMAGE. Run build-control-plane-images.sh first, then this script,
# then build-images.sh.
#
# Naming: bases use the bare upstream component name (slurmctld, slurmd,
# slurmd-pyxis). The one exception is login-pyxis: the deployed custom login
# image built by build-images.sh is already named "login-pyxis", so the
# from-source upstream login-pyxis payload (only used as PYXIS_LOGIN_IMAGE to
# copy enroot/pyxis bits) is tagged "login-pyxis-base" to avoid colliding.
#
# Run on the image-builder host. Prerequisites:
# - docker buildx with a docker-container builder (default: multiarch-builder)
# - OCIR push credentials for the target registry
# - qemu binfmt for arm64: docker run --privileged --rm tonistiigi/binfmt --install arm64
#
# Multi-platform note: the upstream Dockerfile mounts the apt cache with
# sharing=locked (not arch-scoped), so building linux/amd64 and linux/arm64 in a
# single buildx call cross-contaminates the apt package lists. Each arch is built
# separately, the builder cache is pruned between them, and the results are
# combined into a multi-arch manifest (same approach as build-control-plane-images.sh).
set -euo pipefail

registry="${REGISTRY:-iad.ocir.io/idxzjcdglx2s/slurm-operator}"
build_version="${BUILD_VERSION:-2026-07-02.0}"
builder="${BUILDER:-multiarch-builder}"
platforms="${PLATFORMS:-linux/amd64,linux/arm64}"

slurm_version="${SLURM_VERSION:-26.05.1}"
flavor="${FLAVOR:-ubuntu26.04}"
slurm_minor="${slurm_version%.*}" # 26.05.1 -> 26.05

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}/slurm-source"

# tag for a base image: <registry>:<name>-<version>-<flavor>-<build_version>
base_tag() { printf '%s:%s-%s-%s-%s' "${registry}" "$1" "${slurm_version}" "${flavor}" "${build_version}"; }

bake_files=(--file ./docker-bake.hcl --file "./${slurm_minor}/${flavor}/slurm.hcl")

# Bake targets to build, and the image name each is tagged as in our registry.
# The pyxis targets build their slurmd/login bases from source via bake contexts.
targets=(slurmctld slurmd slurmd_pyxis login_pyxis)

IFS=',' read -r -a platform_list <<<"${platforms}"
for platform in "${platform_list[@]}"; do
  arch="${platform##*/}"
  echo "== build bases ${platform} =="
  docker buildx bake "${bake_files[@]}" --builder "${builder}" \
    --set "*.platform=${platform}" \
    --set "slurmctld.tags=$(base_tag slurmctld)-${arch}" \
    --set "slurmd.tags=$(base_tag slurmd)-${arch}" \
    --set "slurmd_pyxis.tags=$(base_tag slurmd-pyxis)-${arch}" \
    --set "login_pyxis.tags=$(base_tag login-pyxis-base)-${arch}" \
    --push "${targets[@]}"
  # Clear the apt-list cache so the next arch starts clean (see header note).
  docker buildx prune --builder "${builder}" -af >/dev/null 2>&1 || true
done

for name in slurmctld slurmd slurmd-pyxis login-pyxis-base; do
  src=()
  for platform in "${platform_list[@]}"; do
    src+=("$(base_tag "${name}")-${platform##*/}")
  done
  docker buildx imagetools create -t "$(base_tag "${name}")" "${src[@]}"
done

echo "Built from-source base images into ${registry}:"
for name in slurmctld slurmd slurmd-pyxis login-pyxis-base; do
  echo "  $(base_tag "${name}")"
done
