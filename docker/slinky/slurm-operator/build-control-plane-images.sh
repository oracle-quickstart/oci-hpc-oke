#!/usr/bin/env bash
#
# Build the SlurmDBD, slurmrestd, login (SSSD sidecar), operator, and webhook
# images from upstream source into our registry, so the whole Slurm stack comes
# from one registry instead of mixing iad.ocir.io/.../slurm-operator with
# ghcr.io/slinkyproject. These are the images the deployment otherwise pulls
# straight from upstream; build-images.sh covers the layered custom images
# (controller, login-pyxis, workers).
#
# Run on the image-builder host. Prerequisites:
# - docker buildx with a docker-container builder (default: multiarch-builder)
# - OCIR push credentials for the target registry
# - qemu binfmt for arm64: docker run --privileged --rm tonistiigi/binfmt --install arm64
#
# Sources:
# - slurmdbd, slurmrestd, login build from the vendored upstream assets in
#   slurm-source/ (copied from SlinkyProject/containers; see slurm-source/README.md)
#   via Docker Bake -- a single multi-stage Dockerfile with per-component targets.
# - operator + webhook build from a pinned clone of SlinkyProject/slurm-operator
#   (its Dockerfile needs the Go source tree, so it cannot be vendored standalone;
#   a reference copy lives at operator/slurm-operator/Dockerfile). Go cross-compile.
#
# Multi-platform note: the containers Dockerfile mounts the apt cache with
# sharing=locked (not arch-scoped), so building linux/amd64 and linux/arm64 in a
# single buildx call cross-contaminates the apt package lists (arm64 then fails
# to find e.g. bash-completion:arm64). Upstream builds each arch on native
# runners. Here each arch is built separately, the builder cache is pruned
# between them, and the results are combined into a multi-arch manifest. The
# operator is a clean Go cross-compile and builds both arches in one call.
set -euo pipefail

registry="${REGISTRY:-iad.ocir.io/idxzjcdglx2s/slurm-operator}"
operator_registry="${OPERATOR_REGISTRY:-iad.ocir.io/idxzjcdglx2s}"
build_version="${BUILD_VERSION:-2026-06-19.0}"
builder="${BUILDER:-multiarch-builder}"
platforms="${PLATFORMS:-linux/amd64,linux/arm64}"

slurm_version="${SLURM_VERSION:-25.11.6}"
flavor="${FLAVOR:-ubuntu24.04}"
slurm_minor="${slurm_version%.*}" # 25.11.6 -> 25.11

operator_repo="${OPERATOR_REPO:-https://github.com/SlinkyProject/slurm-operator.git}"
operator_ref="${OPERATOR_REF:-v1.1.1}"
operator_version="${OPERATOR_VERSION:-1.1.1}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

comp_tag() { printf '%s:%s-%s-%s-%s' "${registry}" "$1" "${slurm_version}" "${flavor}" "${build_version}"; }

# ---- Slurm component images: slurmdbd, slurmrestd, login (per-arch + combine) ----
# Built from the vendored upstream assets in slurm-source/ (copied from
# SlinkyProject/containers at the ref in slurm-source/README.md), so the build
# is self-contained and does not depend on a network clone.
cd "${script_dir}/slurm-source"

bake_files=(--file ./docker-bake.hcl --file "./${slurm_minor}/${flavor}/slurm.hcl")
components=(slurmdbd slurmrestd login)

IFS=',' read -r -a platform_list <<<"${platforms}"
for platform in "${platform_list[@]}"; do
  arch="${platform##*/}"
  echo "== build components ${platform} =="
  docker buildx bake "${bake_files[@]}" --builder "${builder}" \
    --set "*.platform=${platform}" \
    --set "slurmdbd.tags=$(comp_tag slurmdbd)-${arch}" \
    --set "slurmrestd.tags=$(comp_tag slurmrestd)-${arch}" \
    --set "login.tags=$(comp_tag login)-${arch}" \
    --push "${components[@]}"
  # Clear the apt-list cache so the next arch starts clean (see header note).
  docker buildx prune --builder "${builder}" -af >/dev/null 2>&1 || true
done

for c in "${components[@]}"; do
  src=()
  for platform in "${platform_list[@]}"; do
    src+=("$(comp_tag "$c")-${platform##*/}")
  done
  docker buildx imagetools create -t "$(comp_tag "$c")" "${src[@]}"
done

# ---- Operator + webhook (Go cross-compile, both arches in one call) ----
git clone --quiet --branch "${operator_ref}" "${operator_repo}" "${workdir}/operator"
cd "${workdir}/operator"
REGISTRY="${operator_registry}" VERSION="${operator_version}" docker buildx bake \
  --builder "${builder}" --file ./docker-bake.hcl \
  --set "*.platform=${platforms}" --push operator webhook

echo "Built control-plane images into ${registry} and ${operator_registry}."
