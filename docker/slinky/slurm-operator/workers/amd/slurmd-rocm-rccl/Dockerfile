# syntax=docker/dockerfile:1.7
#
# Slinky slurmd image for AMD ROCm GPU shapes that need:
# - Slurm 26.05.1 with gpu_rsmi/gres_gpu support
# - SSSD/NSS client support for LDAP-backed Slurm users
# - RCCL tests built against the same ROCm/RCCL stack used at runtime
#
# The RCCL base image is linux/amd64 only, so this image is intentionally
# linux/amd64-only until the AMD base image strategy changes.

ARG SLURM_VERSION=26.05.1
ARG BASE_RCCL_IMAGE=iad.ocir.io/idxzjcdglx2s/rccl-tests:rocm-7.1.1-ubuntu22.04-rccl-2.27.7-011826.1

FROM ${BASE_RCCL_IMAGE} AS build-slurm

SHELL ["bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG SLURM_VERSION

USER root
WORKDIR /tmp

RUN <<'EOR'
set -xeuo pipefail
apt-get -qq update
apt-get -qq -y install --no-install-recommends \
  build-essential fakeroot devscripts equivs curl ca-certificates patch

SLURM_DIR="slurm-${SLURM_VERSION}"
mkdir -p "${SLURM_DIR}"
if [ "$(curl -s -Iw '%{http_code}' -o /dev/null "https://download.schedmd.com/slurm/${SLURM_DIR}.tar.bz2")" -eq 200 ]; then
  curl -s -O "https://download.schedmd.com/slurm/${SLURM_DIR}.tar.bz2"
  tar --strip-components=1 -jxvf "${SLURM_DIR}.tar.bz2" -C "${SLURM_DIR}"
else
  curl -s -L -H "Accept: application/vnd.github+json" -O "https://github.com/SchedMD/slurm/archive/${SLURM_VERSION}.tar.gz"
  tar --strip-components=1 -zxvf "${SLURM_VERSION}.tar.gz" -C "${SLURM_DIR}"
fi

mk-build-deps -ir --tool='apt-get -qq -y -o Debug::pkgProblemResolver=yes --no-install-recommends' "${SLURM_DIR}/debian/control"
( cd "${SLURM_DIR}" && debuild -b -uc -us >/dev/null )

mkdir -p /out
cp /tmp/*.deb /out/
EOR

FROM ${BASE_RCCL_IMAGE}

SHELL ["bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG SLURM_VERSION
ARG BASE_RCCL_IMAGE

USER root
WORKDIR /tmp

ARG SLURM_USER=slurm
ARG SLURM_USER_UID=401
ARG SLURM_USER_GID=401

COPY --from=build-slurm /out/*.deb /tmp/

RUN <<'EOR'
set -xeuo pipefail

if ! getent group "${SLURM_USER}" >/dev/null; then
  groupadd --system --gid="${SLURM_USER_GID}" "${SLURM_USER}"
fi
if ! getent passwd "${SLURM_USER}" >/dev/null; then
  useradd --system --no-log-init --uid="${SLURM_USER_UID}" --gid="${SLURM_USER_GID}" --shell=/usr/sbin/nologin "${SLURM_USER}"
fi

apt-get -qq update
apt-get -qq -y install --no-install-recommends \
  tini rsync gettext-base iputils-ping \
  libnss-sss libpam-sss sssd sssd-tools

apt-get -qq -y install --fix-broken \
  ./slurm-smd-client_[0-9]*.deb \
  ./slurm-smd-dev_[0-9]*.deb \
  ./slurm-smd-doc_[0-9]*.deb \
  ./slurm-smd-libnss-slurm_[0-9]*.deb \
  ./slurm-smd-libpam-slurm-adopt_[0-9]*.deb \
  ./slurm-smd-libpmi2-0_[0-9]*.deb \
  ./slurm-smd-slurmd_[0-9]*.deb \
  ./slurm-smd_[0-9]*.deb

sed -ri 's/^passwd:.*/passwd:     files sss systemd/' /etc/nsswitch.conf
sed -ri 's/^group:.*/group:      files sss systemd/' /etc/nsswitch.conf
sed -ri 's/^shadow:.*/shadow:     files/' /etc/nsswitch.conf

mkdir -p /opt/oci-hpc/rccl-tests/bin
cp -a /workspace/rccl-tests/build/*_perf /opt/oci-hpc/rccl-tests/bin/
ln -sf /opt/oci-hpc/rccl-tests/bin/*_perf /usr/local/bin/

cat > /opt/oci-hpc/rccl-tests/env.sh <<'EOF'
export RCCL_TEST_HOME=/opt/oci-hpc/rccl-tests
export ROCM_PATH=/opt/rocm
export MPI_HOME=/opt/ompi
export PATH=/opt/ompi/bin:/opt/rocm/bin:/opt/oci-hpc/rccl-tests/bin:${PATH}
export LD_LIBRARY_PATH=/opt/ompi/lib:/opt/rocm/lib:/opt/rocm/lib64:${LD_LIBRARY_PATH:-}
export OMPI_MCA_btl_tcp_if_include=${OMPI_MCA_btl_tcp_if_include:-eth0}
export OMPI_MCA_oob_tcp_if_include=${OMPI_MCA_oob_tcp_if_include:-eth0}
EOF

cat > /usr/local/bin/with-rccl-tests-env <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /opt/oci-hpc/rccl-tests/env.sh
exec "$@"
EOF

cat > /usr/local/sbin/slurmd-sssd-wrapper <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if ! ulimit -l unlimited; then
  echo "warning: unable to set memlock ulimit to unlimited" >&2
fi

if [ -f /etc/sssd/sssd.conf ] && command -v /usr/sbin/sssd >/dev/null 2>&1; then
  install -d -m 0755 /var/lib/sss /var/lib/sss/gpo_cache /var/lib/sss/pipes /var/lib/sss/pubconf /var/lib/sss/pubconf/krb5.include.d /run/sssd
  install -d -m 0700 /var/lib/sss/db /var/lib/sss/keytabs /var/lib/sss/secrets
  install -d -m 0751 /var/lib/sss/deskprofile
  install -d -m 0750 /var/lib/sss/pipes/private /var/log/sssd
  install -d -m 0775 /var/lib/sss/mc
  rm -f /var/lib/sss/pipes/nss /var/lib/sss/pipes/pam /var/lib/sss/pipes/ssh /run/sssd.pid /run/sssd/*.pid
  /usr/sbin/sssd -D
fi

raw_args=("$@")
clean_args=()
i=0
while [ "$i" -lt "${#raw_args[@]}" ]; do
  arg="${raw_args[$i]}"
  if [ "$arg" = "--conf" ] && [ "$((i + 1))" -lt "${#raw_args[@]}" ]; then
    conf="${raw_args[$((i + 1))]}"
    conf="${conf#\'}"
    conf="${conf%\'}"
    clean_args+=("--conf" "$conf")
    i=$((i + 2))
  else
    clean_args+=("$arg")
    i=$((i + 1))
  fi
done

exec slurmd -D "${clean_args[@]}"
EOF

chmod 0644 /opt/oci-hpc/rccl-tests/env.sh
chmod 0755 /usr/local/bin/with-rccl-tests-env /usr/local/sbin/slurmd-sssd-wrapper

cat > /opt/oci-hpc/rccl-tests/IMAGE_NOTES.md <<EOF
# slurmd-rocm-rccl

Base RCCL image:

\`${BASE_RCCL_IMAGE}\`

Slurm version:

\`${SLURM_VERSION}\`

Important paths:

- \`/opt/oci-hpc/rccl-tests/bin/*_perf\`
- \`/workspace/rccl-tests/build/*_perf\`
- \`/usr/local/bin/with-rccl-tests-env\`
- \`/opt/oci-hpc/rccl-tests/env.sh\`

The entrypoint starts SSSD when \`/etc/sssd/sssd.conf\` is mounted, strips the
literal surrounding quotes from Slinky's generated \`--conf\` value, and then
execs \`slurmd -D\`.
EOF

multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
ldd /opt/oci-hpc/rccl-tests/bin/all_reduce_perf
test -x /usr/local/bin/all_reduce_perf
test -x /usr/local/bin/with-rccl-tests-env
test -x /usr/local/sbin/slurmd-sssd-wrapper
test -f "/usr/lib/${multiarch}/slurm/gpu_rsmi.so"
test -f "/usr/lib/${multiarch}/slurm/gres_gpu.so"
test -f "/usr/lib/${multiarch}/libnss_sss.so.2"
slurmd -V

rm -f /tmp/*.deb
apt-get clean
rm -rf /var/lib/apt/lists/*
EOR

ENV RCCL_TEST_HOME=/opt/oci-hpc/rccl-tests
ENV ROCM_PATH=/opt/rocm
ENV MPI_HOME=/opt/ompi
ENV PATH=/opt/ompi/bin:/opt/rocm/bin:/opt/oci-hpc/rccl-tests/bin:${PATH}
ENV LD_LIBRARY_PATH=/opt/ompi/lib:/opt/rocm/lib:/opt/rocm/lib64
ENV UCX_WARN_UNUSED_ENV_VARS=n

ENTRYPOINT ["tini", "-g", "--", "/usr/local/sbin/slurmd-sssd-wrapper"]
WORKDIR /
