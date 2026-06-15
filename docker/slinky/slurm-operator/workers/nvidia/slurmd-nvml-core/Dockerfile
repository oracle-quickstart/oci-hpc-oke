# syntax=docker/dockerfile:1
#
# Minimal Slinky slurmd image with Slurm's NVML GPU path enabled.
# This is intended for GPU shapes where the stock Slinky image has gpu_nvidia.so
# but `AutoDetect=nvml` needs Slurm core GPU detection and plugins compiled
# with NVML support.
#
# Multi-platform build example:
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     -t iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-nvml-core-26.05.1-ubuntu24.04-2026-06-15.1 \
#     --push .

ARG SLURM_VERSION=26.05.1
ARG SLURM_VERSION_MICRO=1
ARG SLURM_DIR=slurm
ARG PARENT_IMAGE=ubuntu:24.04
ARG BASE_SLURMD_IMAGE=ghcr.io/slinkyproject/slurmd:26.05-ubuntu24.04

################################################################################
FROM --platform=$BUILDPLATFORM alpine:latest AS slurm-src

ARG SLURM_VERSION
ARG SLURM_VERSION_MICRO
ARG SLURM_DIR
ARG SLURM_TAR="slurm-${SLURM_VERSION//./-}-${SLURM_VERSION_MICRO}.tar.gz"

WORKDIR /workspace/

RUN apk add -q --no-cache tar

ADD https://github.com/SchedMD/slurm/archive/refs/tags/${SLURM_TAR} ${SLURM_TAR}

RUN mkdir -p ${SLURM_DIR} \
    && tar --strip-components=1 -zxvf ${SLURM_TAR} -C ${SLURM_DIR} \
    && rm ${SLURM_TAR}

################################################################################
FROM ${PARENT_IMAGE} AS build

SHELL ["bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG SLURM_DIR

USER root
WORKDIR /tmp/

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOR
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
apt-get -qq -y upgrade
apt-get -qq -y install --no-install-recommends \
  autoconf automake bison build-essential ca-certificates dpkg-dev flex \
  libhwloc-dev libjson-c-dev libjwt-dev liblz4-dev libmunge-dev \
  libnvidia-ml-dev libreadline-dev libssl-dev libtool pkg-config python3 \
  zlib1g-dev
EOR

COPY --from=slurm-src /workspace/${SLURM_DIR} ${SLURM_DIR}

RUN <<EOR
set -xeuo pipefail
cd ${SLURM_DIR}
if [ ! -x ./configure ]; then
  ./autogen.sh
fi
multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
./configure \
  --prefix=/usr \
  --sysconfdir=/etc/slurm \
  --libdir="/usr/lib/${multiarch}" \
  --with-nvml=/usr \
  --without-hdf5 \
  --without-pam \
  --disable-debug
make -j"$(nproc)" -C src/api full_version.map libslurmfull.la
make -j"$(nproc)" -C src/plugins/gpu/common
make -j"$(nproc)" -C src/plugins/gpu/nvml
make -j"$(nproc)" -C src/plugins/gres/common
make -j"$(nproc)" -C src/plugins/gres/gpu
install -Dm755 src/api/.libs/libslurmfull.so /out/libslurmfull.so
install -Dm755 src/plugins/gpu/nvml/.libs/gpu_nvml.so /out/gpu_nvml.so
install -Dm755 src/plugins/gres/gpu/.libs/gres_gpu.so /out/gres_gpu.so
EOR

################################################################################
FROM ${BASE_SLURMD_IMAGE}

SHELL ["bash", "-o", "pipefail", "-c"]

ARG TARGETARCH

USER root
WORKDIR /

COPY --from=build /out/ /tmp/slurm-nvml-plugins/

RUN set -xeuo pipefail; \
    case "${TARGETARCH}" in \
      amd64) multiarch="x86_64-linux-gnu" ;; \
      arm64) multiarch="aarch64-linux-gnu" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    plugin_dir="/usr/lib/${multiarch}/slurm"; \
    test -d "${plugin_dir}"; \
    install -m 0755 /tmp/slurm-nvml-plugins/libslurmfull.so "${plugin_dir}/libslurmfull.so"; \
    install -m 0755 /tmp/slurm-nvml-plugins/gpu_nvml.so "${plugin_dir}/gpu_nvml.so"; \
    install -m 0755 /tmp/slurm-nvml-plugins/gres_gpu.so "${plugin_dir}/gres_gpu.so"; \
    test -f "${plugin_dir}/libslurmfull.so"; \
    test -f "${plugin_dir}/gpu_nvml.so"; \
    test -f "${plugin_dir}/gres_gpu.so"; \
    rm -rf /tmp/slurm-nvml-plugins
