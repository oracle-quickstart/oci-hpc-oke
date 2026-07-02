# syntax=docker/dockerfile:1
# SPDX-FileCopyrightText: Copyright (C) SchedMD LLC.
# SPDX-License-Identifier: Apache-2.0

################################################################################

ARG SLURM_VERSION=26.05.1
ARG SLURM_VERSION_MICRO=1
ARG SLURM_DIR=slurm
ARG PARENT_IMAGE=ubuntu:26.04

################################################################################
FROM alpine:latest AS slurm-src

ARG SLURM_VERSION
ARG SLURM_VERSION_MICRO
ARG SLURM_DIR
ARG SLURM_TAR="slurm-${SLURM_VERSION//./-}-${SLURM_VERSION_MICRO}.tar.gz"

WORKDIR /workspace/

RUN apk add -q --no-cache tar

ADD https://github.com/SchedMD/slurm/archive/refs/tags/${SLURM_TAR} ${SLURM_TAR}

RUN \
  mkdir -p ${SLURM_DIR} && \
  tar --strip-components=1 -zxvf ${SLURM_TAR} -C ${SLURM_DIR} && \
  rm ${SLURM_TAR}

################################################################################
FROM ${PARENT_IMAGE} AS build

SHELL ["bash", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

ARG SLURM_VERSION
ENV SLURM_VERSION=${SLURM_VERSION}
ARG SLURM_DIR

USER root
WORKDIR /tmp/

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOR
# Pre-Build Slurm
set -xeuo pipefail
apt-get -qq update
apt-get -qq -y upgrade
apt-get -qq -y install --no-install-recommends \
  build-essential apt-utils fakeroot devscripts equivs
EOR

COPY --from=slurm-src /workspace/${SLURM_DIR} ${SLURM_DIR}

# Ref: https://slurm.schedmd.com/quickstart_admin.html#debuild
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOR
# Build Slurm
set -xeuo pipefail
mk-build-deps -ir --tool='apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends' ${SLURM_DIR}/debian/control >/dev/null
( cd ${SLURM_DIR} && debuild -b -uc -us >/dev/null )
EOR

################################################################################
FROM ${PARENT_IMAGE} AS base

SHELL ["bash", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

ARG SLURM_VERSION
ENV SLURM_VERSION=${SLURM_VERSION}

USER root
WORKDIR /tmp/

ARG SLURM_USER=slurm
ARG SLURM_USER_UID=401
ARG SLURM_USER_GID=401

RUN <<EOR
# Create SlurmUser
set -xeuo pipefail
groupadd --system --gid=${SLURM_USER_GID} ${SLURM_USER}
useradd --system --no-log-init --uid=${SLURM_USER_UID} --gid=${SLURM_USER_GID} --shell=/usr/sbin/nologin ${SLURM_USER}
EOR

RUN <<EOR
# Remove Users
set -xeuo pipefail
for user in $(ls /home/); do
  userdel --remove $user
done
EOR

COPY --from=build /tmp/*.deb /tmp/*.ddeb /tmp/

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOR
# Install Dependencies
set -xeuo pipefail
apt-get -qq update
apt-get -qq -y upgrade
# Init System
apt-get -qq -y install --no-install-recommends \
  supervisor tini
# Debug
apt-get -qq -y install --no-install-recommends \
  procps iputils-ping ncurses-bin
EOR

################################################################################
FROM base AS base-extra

SHELL ["bash", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOR
# Install Extra Packages
set -xeuo pipefail
apt-get -qq update
apt-get -qq -y install --no-install-recommends \
  openmpi-bin
EOR

################################################################################
FROM base AS slurmctld

SHELL ["bash", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

USER root
WORKDIR /tmp/

# Ref: https://slurm.schedmd.com/quickstart_admin.html#pkg_install
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOR
# Install Slurm Packages
set -xeuo pipefail
apt-get -qq update
apt-get -qq -y install --no-install-recommends --fix-broken \
  socat \
  ./slurm-smd-client_[0-9]*.deb \
  ./slurm-smd-client-dbgsym_[0-9]*.ddeb \
  ./slurm-smd-dev_[0-9]*.deb \
  ./slurm-smd-doc_[0-9]*.deb \
  ./slurm-smd-slurmctld_[0-9]*.deb \
  ./slurm-smd-slurmctld-dbgsym_[0-9]*.ddeb \
  ./slurm-smd_[0-9]*.deb \
  ./slurm-smd-dbgsym_[0-9]*.ddeb
rm *.deb && rm *.ddeb
EOR

COPY files/etc/supervisor/supervisord.conf /etc/supervisor/
COPY \
  files/etc/supervisor/conf.d/slurmctld.conf \
  files/etc/supervisor/conf.d/fakesystemd.conf \
  /etc/supervisor/conf.d/
COPY files/usr/local/bin/fakesystemd.sh /usr/local/bin/
COPY files/usr/local/bin/slurmctld-entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 6817/tcp
ENTRYPOINT ["entrypoint.sh"]

################################################################################
FROM base-extra AS slurmd

SHELL ["bash", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

USER root
WORKDIR /tmp/

# Ref: https://slurm.schedmd.com/quickstart_admin.html#pkg_install
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOR
# Install Slurm Packages
set -xeuo pipefail
apt-get -qq update
apt-get -qq -y install --no-install-recommends --fix-broken \
  gawk socat \
  openssh-server \
  authselect sssd sssd-ad sssd-ldap libpam-sss libnss-sss \
  ./slurm-smd-client_[0-9]*.deb \
  ./slurm-smd-client-dbgsym_[0-9]*.ddeb \
  ./slurm-smd-dev_[0-9]*.deb \
  ./slurm-smd-doc_[0-9]*.deb \
  ./slurm-smd-libnss-slurm_[0-9]*.deb \
  ./slurm-smd-libnss-slurm-dbgsym_[0-9]*.ddeb \
  ./slurm-smd-libpam-slurm-adopt_[0-9]*.deb \
  ./slurm-smd-libpmi2-0_[0-9]*.deb \
  ./slurm-smd-slurmd_[0-9]*.deb \
  ./slurm-smd-slurmd-dbgsym_[0-9]*.ddeb \
  ./slurm-smd_[0-9]*.deb \
  ./slurm-smd-dbgsym_[0-9]*.ddeb
rm *.deb && rm *.ddeb
# Configure
mkdir -p /var/spool/slurmd/
sed -i -E "s/^passwd:[[:space:]]+/&slurm /g" /etc/nsswitch.conf
sed -i -E "s/^group:[[:space:]]+/&slurm /g" /etc/nsswitch.conf
mkdir -p /etc/authselect
authselect select sssd with-mkhomedir --force
rm -f /etc/ssh/ssh_host_*
EOR

COPY files/etc/supervisor/supervisord.conf /etc/supervisor/
COPY \
  files/etc/supervisor/conf.d/fakesystemd.conf \
  files/etc/supervisor/conf.d/slurmd.conf \
  files/etc/supervisor/conf.d/sshd.conf \
  files/etc/supervisor/conf.d/sssd.conf \
  /etc/supervisor/conf.d/
COPY files/usr/local/bin/fakesystemd.sh /usr/local/bin/
COPY files/usr/local/bin/slurmd-entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 6818/tcp 22/tcp
ENTRYPOINT ["entrypoint.sh"]

################################################################################
FROM base AS slurmdbd

SHELL ["bash", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

USER root
WORKDIR /tmp/

# Ref: https://slurm.schedmd.com/quickstart_admin.html#pkg_install
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOR
# Install Slurm Packages
set -xeuo pipefail
apt-get -qq update
apt-get -qq -y install --no-install-recommends --fix-broken \
  ./slurm-smd-doc_[0-9]*.deb \
  ./slurm-smd-slurmdbd_[0-9]*.deb \
  ./slurm-smd-slurmdbd-dbgsym_[0-9]*.ddeb \
  ./slurm-smd_[0-9]*.deb \
  ./slurm-smd-dbgsym_[0-9]*.ddeb
rm *.deb && rm *.ddeb
EOR

EXPOSE 6819/tcp
ENTRYPOINT ["tini", "-g", "--", "slurmdbd", "-D"]

################################################################################
FROM base AS slurmrestd

SHELL ["bash", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

USER root
WORKDIR /tmp/

# Ref: https://slurm.schedmd.com/quickstart_admin.html#pkg_install
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOR
# Install Slurm Packages
set -xeuo pipefail
apt-get -qq update
apt-get -qq -y install --no-install-recommends --fix-broken \
  ./slurm-smd-doc_[0-9]*.deb \
  ./slurm-smd-slurmrestd_[0-9]*.deb \
  ./slurm-smd-slurmrestd-dbgsym_[0-9]*.ddeb \
  ./slurm-smd_[0-9]*.deb \
  ./slurm-smd-dbgsym_[0-9]*.ddeb
rm *.deb && rm *.ddeb
EOR

EXPOSE 6820/tcp
ENTRYPOINT ["tini", "-g", "--", "slurmrestd"]
CMD ["0.0.0.0:6820"]

################################################################################
FROM base-extra AS sackd

SHELL ["bash", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

USER root
WORKDIR /tmp/

ADD https://dl.k8s.io/release/stable.txt kubernetes_stable.txt

# Ref: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOR
# Install kubectl
set -xeuo pipefail
apt-get -qq update
VERSION="$(cat kubernetes_stable.txt | grep -Eo '^v[0-9]+\.[0-9]+')"
apt-get -qq -y install --no-install-recommends \
  apt-transport-https ca-certificates curl gnupg
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/${VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
chmod 644 /etc/apt/sources.list.d/kubernetes.list
apt-get -qq update
apt-get -qq -y install --no-install-recommends kubectl
rm *.txt
EOR

# Ref: https://slurm.schedmd.com/quickstart_admin.html#pkg_install
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOR
# Install Slurm Packages
set -xeuo pipefail
apt-get -qq update
apt-get -qq -y install --no-install-recommends --fix-broken \
  socat \
  ./slurm-smd-client_[0-9]*.deb \
  ./slurm-smd-client-dbgsym_[0-9]*.ddeb \
  ./slurm-smd-doc_[0-9]*.deb \
  ./slurm-smd-sackd_[0-9]*.deb \
  ./slurm-smd-sackd-dbgsym_[0-9]*.ddeb \
  ./slurm-smd_[0-9]*.deb \
  ./slurm-smd-dbgsym_[0-9]*.ddeb
rm *.deb && rm *.ddeb
# Prepare Directories
mkdir -p /run/slurm/
EOR

COPY files/etc/supervisor/supervisord.conf /etc/supervisor/
COPY \
  files/etc/supervisor/conf.d/sackd.conf \
  files/etc/supervisor/conf.d/fakesystemd-slurm.conf \
  /etc/supervisor/conf.d/
COPY files/usr/local/bin/fakesystemd.sh /usr/local/bin/
COPY files/usr/local/bin/sackd-entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]

################################################################################
FROM sackd AS login

SHELL ["bash", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

USER root
WORKDIR /tmp/

# Ref: https://slurm.schedmd.com/quickstart_admin.html#pkg_install
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOR
# Install Packages
set -xeuo pipefail
apt-get -qq update
apt-get -qq -y install --no-install-recommends \
  socat \
  openssh-server \
  authselect sssd sssd-ad sssd-ldap libpam-sss libnss-sss
# Configure
mkdir -p /etc/authselect
authselect select sssd with-mkhomedir --force
rm -f /etc/ssh/ssh_host_*
EOR

COPY files/etc/supervisor/supervisord.conf /etc/supervisor/
COPY \
  files/etc/supervisor/conf.d/fakesystemd-slurm.conf \
  files/etc/supervisor/conf.d/sackd.conf \
  files/etc/supervisor/conf.d/sshd.conf \
  files/etc/supervisor/conf.d/sssd.conf \
  /etc/supervisor/conf.d/
COPY files/usr/local/bin/fakesystemd.sh /usr/local/bin/
COPY files/usr/local/bin/login-entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 22/tcp
ENTRYPOINT ["entrypoint.sh"]
