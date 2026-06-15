# syntax=docker/dockerfile:1
#
# Custom slurmctld image with PMIx plus SSSD/NSS client support.
# SSSD itself is expected to run as a root sidecar in the controller pod.

ARG SLURMCTLD_PMIX_IMAGE=iad.ocir.io/idxzjcdglx2s/slinky:slurmctld-pmix-25.11-ubuntu24.04

FROM ${SLURMCTLD_PMIX_IMAGE}

SHELL ["bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
USER root

RUN set -eux; \
    find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -print0 \
      | xargs -0 sed -i \
        -e 's|http://archive.ubuntu.com/ubuntu|https://archive.ubuntu.com/ubuntu|g' \
        -e 's|http://security.ubuntu.com/ubuntu|https://security.ubuntu.com/ubuntu|g'; \
    printf '%s\n' 'Acquire::https::Verify-Peer "false";' > /etc/apt/apt.conf.d/99bootstrap-ca; \
    apt-get -qq update; \
    apt-get -qq -y install --no-install-recommends ca-certificates; \
    rm -f /etc/apt/apt.conf.d/99bootstrap-ca; \
    apt-get -qq update \
    && apt-get -qq -y install --no-install-recommends \
        authselect \
        sssd \
        sssd-ad \
        sssd-ldap \
        libpam-sss \
        libnss-sss \
    && mkdir -p /etc/authselect \
    && authselect select sssd --force \
    && rm -rf /var/lib/apt/lists/*
