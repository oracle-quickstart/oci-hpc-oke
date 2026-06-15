# syntax=docker/dockerfile:1.7
#
# Slinky login image with Pyxis/Enroot support.
#
# Multi-platform build:
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     -t iad.ocir.io/idxzjcdglx2s/slinky:login-pyxis-25.11.5-ubuntu24.04-r6 \
#     --push .

ARG BASE_LOGIN_IMAGE=ghcr.io/slinkyproject/login:25.11-ubuntu24.04
ARG PYXIS_LOGIN_IMAGE=ghcr.io/slinkyproject/login-pyxis:25.11-ubuntu24.04

FROM --platform=$TARGETPLATFORM ${PYXIS_LOGIN_IMAGE} AS pyxis

FROM --platform=$TARGETPLATFORM ${BASE_LOGIN_IMAGE}

SHELL ["bash", "-o", "pipefail", "-c"]

ARG BASE_LOGIN_IMAGE
ARG PYXIS_LOGIN_IMAGE
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
  bash-completion bsdmainutils bzip2 curl dnsutils file gawk gettext-base git \
  gzip fail2ban htop iproute2 iptables iputils-ping jq less locales lsof \
  man-db manpages nano ncurses-term netcat-openbsd openssh-client parallel \
  pigz procps psmisc python-is-python3 python3 python3-pip python3-venv rsync screen \
  squashfs-tools tar tmux traceroute tree unzip vim wget xz-utils yq zip zstd
rm -rf /var/lib/apt/lists/*
EOR

RUN <<'EOR'
set -xeuo pipefail

install -D -m 0755 /dev/stdin /usr/local/sbin/sshd-with-authlog <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

touch /var/log/auth.log
chown root:adm /var/log/auth.log 2>/dev/null || chown root:root /var/log/auth.log
chmod 0640 /var/log/auth.log

host="$(hostname -s 2>/dev/null || hostname || echo login)"

if [ -n "${SSHD_OPTIONS:-}" ]; then
  # Preserve compatibility with Slinky's SSHD_OPTIONS environment variable.
  # shellcheck disable=SC2086
  exec /usr/sbin/sshd -D -e ${SSHD_OPTIONS} \
    2> >(awk -v host="${host}" '{ print strftime("%b %e %H:%M:%S"), host, "sshd:", $0; fflush(); }' | tee -a /var/log/auth.log >&2)
fi

exec /usr/sbin/sshd -D -e \
  2> >(awk -v host="${host}" '{ print strftime("%b %e %H:%M:%S"), host, "sshd:", $0; fflush(); }' | tee -a /var/log/auth.log >&2)
EOS

install -D -m 0755 /dev/stdin /usr/local/sbin/fail2ban-foreground <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p /run/fail2ban
touch /var/log/auth.log
chown root:adm /var/log/auth.log 2>/dev/null || chown root:root /var/log/auth.log
chmod 0640 /var/log/auth.log

exec /usr/bin/fail2ban-server -f -x start
EOS

cat > /etc/supervisor/conf.d/sshd.conf <<'EOS'
# SPDX-FileCopyrightText: Copyright (C) SchedMD LLC.
# SPDX-License-Identifier: Apache-2.0

[program:sshd]
command=/usr/local/sbin/sshd-with-authlog
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
stopasgroup=true
EOS

cat > /etc/supervisor/conf.d/fail2ban.conf <<'EOS'
[program:fail2ban]
command=/usr/local/sbin/fail2ban-foreground
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
autorestart=true
startsecs=2
priority=30
EOS

cat > /etc/fail2ban/jail.d/sshd-login.local <<'EOS'
[DEFAULT]
backend = polling
banaction = iptables-multiport
ignoreip = 127.0.0.1/8 ::1
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
mode = normal
EOS

touch /var/log/auth.log
chmod 0640 /var/log/auth.log
fail2ban-server --test
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

install -D -m 0755 \
  "/pyxis-root/usr/lib/${multiarch}/slurm/spank_pyxis.so" \
  "/usr/lib/${multiarch}/slurm/spank_pyxis.so"

setcap cap_sys_admin,cap_mknod=ep /usr/bin/enroot-aufs2ovlfs
setcap cap_sys_admin=ep /usr/bin/enroot-mksquashovlfs

test -x /usr/bin/enroot
test -f /usr/share/pyxis/pyxis.conf
test -f "/usr/lib/${multiarch}/slurm/spank_pyxis.so"
test -x /usr/bin/srun
ldd "/usr/lib/${multiarch}/slurm/spank_pyxis.so"
getcap /usr/bin/enroot-aufs2ovlfs /usr/bin/enroot-mksquashovlfs
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

RUN <<'EOR'
set -euo pipefail
{
  printf '# login-pyxis\n\n'
  printf 'Base login image:\n\n`%s`\n\n' "${BASE_LOGIN_IMAGE}"
  printf 'Pyxis/Enroot payload source image:\n\n`%s`\n\n' "${PYXIS_LOGIN_IMAGE}"
  cat <<'EOS'
This image is intended to provide Pyxis command-line option support from login
pods while preserving the normal Slinky login image behavior.

It also includes the default interactive login toolset for users who SSH into a
login pod to edit, inspect, transfer, and submit Slurm jobs. `sshd` logs are
mirrored to `/var/log/auth.log` in syslog format, and fail2ban runs under
supervisor with an enabled `sshd` jail.
EOS
} > /opt/PYXIS_IMAGE_NOTES.md
EOR

WORKDIR /
