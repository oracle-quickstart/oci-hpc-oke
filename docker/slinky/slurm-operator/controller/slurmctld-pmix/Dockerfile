# syntax=docker/dockerfile:1
#
# Custom slurmctld image with PMIx library installed.
# Required for srun --mpi=pmix to work (controller needs libpmix to load
# the mpi/pmix_v5 plugin).
#
# Build:
#   docker build -t your-registry/slurmctld-pmix:25.11-ubuntu24.04 .

ARG SLURMCTLD_IMAGE=ghcr.io/slinkyproject/slurmctld:25.11-ubuntu24.04

FROM ${SLURMCTLD_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
USER root

RUN apt-get -qq update \
    && apt-get -qq -y install --no-install-recommends libpmix2t64 \
    && rm -rf /var/lib/apt/lists/*
