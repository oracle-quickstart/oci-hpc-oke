# syntax=docker/dockerfile:1.7
#
# Slinky slurmd image for OKE NVIDIA GPU shapes with:
# - Slurm 25.11.5
# - NVML AutoDetect plugins
# - NCCL tests and HPCX payload
# - Pyxis SPANK plugin and Enroot runtime
# - libnvidia-container for GPU injection into Enroot containers
#
# Multi-platform build:
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     -t iad.ocir.io/idxzjcdglx2s/slinky:slurmd-nvml-nccl-pyxis-25.11.5-ubuntu24.04-r7 \
#     --push .

ARG BASE_SLURMD_IMAGE=iad.ocir.io/idxzjcdglx2s/slinky:slurmd-nvml-nccl-25.11.5-ubuntu24.04-r2
ARG PYXIS_SLURMD_IMAGE=ghcr.io/slinkyproject/slurmd-pyxis:25.11-ubuntu24.04

FROM --platform=$TARGETPLATFORM ${PYXIS_SLURMD_IMAGE} AS pyxis

FROM --platform=$TARGETPLATFORM ${BASE_SLURMD_IMAGE}

SHELL ["bash", "-o", "pipefail", "-c"]

ARG BASE_SLURMD_IMAGE
ARG PYXIS_SLURMD_IMAGE
ARG DEBIAN_FRONTEND=noninteractive

USER root
WORKDIR /

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked <<'EOR'
set -xeuo pipefail

find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -print0 \
  | xargs -0 sed -i \
    -e 's|http://archive.ubuntu.com/ubuntu|https://archive.ubuntu.com/ubuntu|g' \
    -e 's|http://security.ubuntu.com/ubuntu|https://security.ubuntu.com/ubuntu|g' \
    -e 's|http://ports.ubuntu.com/ubuntu-ports|https://ports.ubuntu.com/ubuntu-ports|g'
printf '%s\n' 'Acquire::https::Verify-Peer "false";' > /etc/apt/apt.conf.d/99bootstrap-ca
apt-get -qq update
apt-get -qq -y install --no-install-recommends ca-certificates
rm -f /etc/apt/apt.conf.d/99bootstrap-ca

apt-get -qq update
apt-get -qq -y install --no-install-recommends \
  bsdmainutils curl gawk jq parallel pigz squashfs-tools zstd
rm -rf /var/lib/apt/lists/*
EOR

RUN --mount=from=pyxis,source=/,target=/pyxis-root,readonly <<'EOR'
set -xeuo pipefail

case "$(dpkg --print-architecture)" in
  amd64) multiarch="x86_64-linux-gnu" ;;
  arm64) multiarch="aarch64-linux-gnu" ;;
  *) echo "Unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;;
esac

cp -a /pyxis-root/usr/bin/enroot* /usr/bin/
cp -a /pyxis-root/usr/lib/enroot /usr/lib/
cp -a /pyxis-root/usr/share/enroot /usr/share/
cp -a /pyxis-root/usr/share/pyxis /usr/share/

rm -rf /etc/enroot
cp -a /pyxis-root/etc/enroot /etc/enroot
if [ -d /pyxis-root/etc/apparmor.d ]; then
  mkdir -p /etc/apparmor.d
  cp -a /pyxis-root/etc/apparmor.d/enroot /etc/apparmor.d/enroot
fi

# The stock 98-nvidia.sh hook depends on nvidia-container-cli, which cannot
# work inside nested Kubernetes + Enroot namespaces: its ldconfig sandbox needs
# a fresh /proc mount, and the pod's /proc carries locked NVIDIA bind mounts
# that make the kernel deny it. Validated replacement: bind-mount the GPU
# driver userland that the Kubernetes GPU runtime already injected into the
# slurmd container, the same way the Mellanox hook injects the RDMA userland.
mv /etc/enroot/hooks.d/98-nvidia.sh /usr/share/enroot/98-nvidia.sh.disabled
cat > /etc/enroot/hooks.d/97-oke-nvidia-mounts.sh <<'EOH'
#! /usr/bin/env bash

# OKE replacement for the 98-nvidia.sh libnvidia-container hook; see the image
# Dockerfile for why the stock hook cannot work on OKE. Bind-mounts the GPU
# driver userland and device nodes from the slurmd container into the Enroot
# container. Activates on NVIDIA_VISIBLE_DEVICES like the stock hook; CUDA
# images set it by default, plain images opt in by exporting it.

set -euo pipefail
shopt -s lastpipe nullglob

source "${ENROOT_LIBRARY_PATH}/common.sh"

tac "${ENROOT_ENVIRON}" | { grep "^NVIDIA_" || true; } | while IFS='=' read -r key value; do
    [ -v "${key}" ] || export "${key}=${value}"
done || :

if [ "${NVIDIA_VISIBLE_DEVICES:-void}" = "void" ] || [ "${NVIDIA_VISIBLE_DEVICES:-}" = "none" ]; then
    exit 0
fi

case "$(uname -m)" in
  x86_64)  multiarch="x86_64-linux-gnu" ;;
  aarch64) multiarch="aarch64-linux-gnu" ;;
  *) exit 0 ;;
esac

{
  for f in "/usr/lib/${multiarch}"/libcuda.so* "/usr/lib/${multiarch}"/libcudadebugger.so* "/usr/lib/${multiarch}"/libnvidia-*.so*; do
    echo "${f} ${f} none x-create=file,bind,ro,nosuid,private,nofail,silent"
  done
  for b in nvidia-smi nvidia-debugdump nvidia-cuda-mps-control nvidia-cuda-mps-server; do
    p="/usr/bin/${b}"
    [ -e "${p}" ] && echo "${p} ${p} none x-create=file,bind,ro,nosuid,private,nofail,silent"
  done
  for d in /dev/nvidiactl /dev/nvidia-uvm /dev/nvidia-uvm-tools /dev/nvidia-modeset /dev/nvidia[0-9]*; do
    [ -e "${d}" ] && echo "${d} ${d} none x-create=file,bind,private,nofail,silent"
  done
  [ -d /dev/nvidia-caps ] && echo "/dev/nvidia-caps /dev/nvidia-caps none x-create=dir,rbind,private,nofail,silent"
  true
} | enroot-mount --root "${ENROOT_ROOTFS}" -
EOH
chmod 0755 /etc/enroot/hooks.d/97-oke-nvidia-mounts.sh
bash -n /etc/enroot/hooks.d/97-oke-nvidia-mounts.sh
test ! -e /etc/enroot/hooks.d/98-nvidia.sh

install -D -m 0755 \
  "/pyxis-root/usr/lib/${multiarch}/slurm/spank_pyxis.so" \
  "/usr/lib/${multiarch}/slurm/spank_pyxis.so"

setcap cap_sys_admin,cap_mknod=ep /usr/bin/enroot-aufs2ovlfs
setcap cap_sys_admin=ep /usr/bin/enroot-mksquashovlfs

test -x /usr/bin/enroot
test -f /usr/share/pyxis/pyxis.conf
test -f "/usr/lib/${multiarch}/slurm/spank_pyxis.so"
test -f "/usr/lib/${multiarch}/slurm/gpu_nvml.so"
test -f "/usr/lib/${multiarch}/slurm/gres_gpu.so"
test -x /opt/nccl-tests/bin/all_reduce_perf
test -x /usr/local/bin/with-nccl-tests-env
ldd "/usr/lib/${multiarch}/slurm/spank_pyxis.so"
getcap /usr/bin/enroot-aufs2ovlfs /usr/bin/enroot-mksquashovlfs
EOR

# RDMA jobs inherit slurmd's locked-memory limit (slurm.conf propagates all
# limits except MEMLOCK), and ibv_reg_mr fails against the container default of
# 8 MB. Raise the limit before slurmd starts instead of adjusting the running
# process from a Kubernetes postStart hook.
RUN <<'EOR'
set -xeuo pipefail
sed -i 's|command=bash -xc "exec slurmd|command=bash -xc "ulimit -l unlimited \&\& exec slurmd|' /etc/supervisor/conf.d/slurmd.conf
grep -q 'ulimit -l unlimited && exec slurmd' /etc/supervisor/conf.d/slurmd.conf
EOR

RUN cat >> /etc/enroot/enroot.conf <<'EOR'

# Slurm jobs run as LDAP users inside Kubernetes containers where /run is not
# user-writable. Keep Enroot runtime/cache/data paths local to the pod and
# separated by UID so Pyxis works without per-job environment overrides.
ENROOT_RUNTIME_PATH        /tmp/enroot-runtime-${UID}
ENROOT_CONFIG_PATH         /tmp/enroot-config-${UID}
ENROOT_CACHE_PATH          /tmp/enroot-cache-${UID}
ENROOT_DATA_PATH           /tmp/enroot-data-${UID}
ENROOT_TEMP_PATH           /tmp
EOR

RUN cat > /opt/nccl-tests/PYXIS_IMAGE_NOTES.md <<EOR
# slurmd-nvml-nccl-pyxis

Base Slurm/NVML/NCCL worker image:

\`${BASE_SLURMD_IMAGE}\`

Pyxis/Enroot payload source image:

\`${PYXIS_SLURMD_IMAGE}\`

This image is intended to run both regular Slurm jobs and Pyxis container jobs.
Container execution is opt-in per job through Pyxis flags such as
\`--container-image\`; regular jobs continue to use the worker filesystem.
EOR

WORKDIR /
