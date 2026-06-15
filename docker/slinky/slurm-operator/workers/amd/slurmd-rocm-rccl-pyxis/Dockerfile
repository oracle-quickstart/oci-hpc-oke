# syntax=docker/dockerfile:1.7
#
# Slinky slurmd image for OKE AMD MI300X with:
# - Slurm 26.05.1, ROCm 7.1.1 RCCL tests payload, SSSD identity
#   (everything from slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-2026-06-15.1)
# - Pyxis SPANK plugin and Enroot runtime
#
# Pyxis is built from source against the matching Slurm headers because this
# image is Ubuntu 22.04 and the slinkyproject pyxis images are Ubuntu 24.04
# (glibc mismatch prevents copying their binaries). Versions are pinned to
# match the ghcr.io/slinkyproject 26.05 images used by the login pod:
# pyxis v0.23.0, enroot 4.1.2.
#
# Build:
#   docker build \
#     -t iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-pyxis-2026-06-15.1 \
#     -f Dockerfile .

ARG BASE_IMAGE=iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-rocm-rccl-26.05.1-rocm7.1.1-sssd-2026-06-15.1
ARG SLURM_VERSION=26.05.1
ARG PYXIS_VERSION=0.23.0
ARG ENROOT_VERSION=4.1.2

FROM ${BASE_IMAGE} AS build-pyxis

SHELL ["bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG SLURM_VERSION
ARG PYXIS_VERSION

USER root
WORKDIR /build

RUN <<'EOR'
set -xeuo pipefail
apt-get -qq update
apt-get -qq -y install --no-install-recommends build-essential curl ca-certificates
mkdir -p slurm pyxis
curl -fsSL "https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2" \
  | tar -xj --strip-components=1 -C slurm
curl -fsSL "https://github.com/NVIDIA/pyxis/archive/v${PYXIS_VERSION}.tar.gz" \
  | tar -xz --strip-components=1 -C pyxis
cd pyxis
CPPFLAGS="-I/build/slurm" make
test -f spank_pyxis.so
EOR

FROM ${BASE_IMAGE}

SHELL ["bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG ENROOT_VERSION

USER root
WORKDIR /

RUN <<'EOR'
set -xeuo pipefail
apt-get -qq update
apt-get -qq -y install --no-install-recommends \
  bsdmainutils ca-certificates curl gawk jq parallel pigz squashfs-tools zstd
arch="$(dpkg --print-architecture)"
curl -fsSL -o "/tmp/enroot_${ENROOT_VERSION}-1_${arch}.deb" \
  "https://github.com/NVIDIA/enroot/releases/download/v${ENROOT_VERSION}/enroot_${ENROOT_VERSION}-1_${arch}.deb"
curl -fsSL -o "/tmp/enroot-caps_${ENROOT_VERSION}-1_${arch}.deb" \
  "https://github.com/NVIDIA/enroot/releases/download/v${ENROOT_VERSION}/enroot+caps_${ENROOT_VERSION}-1_${arch}.deb"
apt-get -qq -y install --no-install-recommends \
  "/tmp/enroot_${ENROOT_VERSION}-1_${arch}.deb" \
  "/tmp/enroot-caps_${ENROOT_VERSION}-1_${arch}.deb"
rm -f /tmp/enroot*.deb
rm -rf /var/lib/apt/lists/*
EOR

COPY --from=build-pyxis /build/pyxis/spank_pyxis.so /usr/lib/x86_64-linux-gnu/slurm/spank_pyxis.so

RUN <<'EOR'
set -xeuo pipefail
chmod 0755 /usr/lib/x86_64-linux-gnu/slurm/spank_pyxis.so
mkdir -p /usr/share/pyxis
printf '%s\n' 'required /usr/lib/x86_64-linux-gnu/slurm/spank_pyxis.so' > /usr/share/pyxis/pyxis.conf

cat >> /etc/enroot/enroot.conf <<'EOF'

# Slurm jobs run as LDAP users inside Kubernetes containers where /run is not
# user-writable. Keep Enroot runtime/cache/data paths local to the pod and
# separated by UID so Pyxis works without per-job environment overrides.
ENROOT_RUNTIME_PATH        /tmp/enroot-runtime-${UID}
ENROOT_CONFIG_PATH         /tmp/enroot-config-${UID}
ENROOT_CACHE_PATH          /tmp/enroot-cache-${UID}
ENROOT_DATA_PATH           /tmp/enroot-data-${UID}
ENROOT_TEMP_PATH           /tmp
EOF

test -x /usr/bin/enroot
test -f /usr/share/pyxis/pyxis.conf
ldd /usr/lib/x86_64-linux-gnu/slurm/spank_pyxis.so
getcap /usr/bin/enroot-aufs2ovlfs /usr/bin/enroot-mksquashovlfs
test -x /opt/oci-hpc/rccl-tests/bin/all_reduce_perf
EOR

WORKDIR /
