## base docker image
ARG ROCM_IMAGE_NAME=rocm/dev-ubuntu-22.04
ARG ROCM_IMAGE_TAG=6.3.2
FROM "${ROCM_IMAGE_NAME}:${ROCM_IMAGE_TAG}"

## rccl repo
ARG RCCL_REPO=https://github.com/ROCm/rccl
ARG RCCL_BRANCH=develop

## rccl-tests repo
ARG RCCL_TESTS_REPO=https://github.com/ROCm/rccl-tests
ARG RCCL_TESTS_BRANCH=develop

## Mellanox OFED version
ARG MELLANOX_OFED_VERSION

## creating scratch space
RUN mkdir -p /workspace
WORKDIR /workspace

## install dependencies
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    openssh-server \
    iputils-ping \
    net-tools \
    make \
    rocm-cmake \
    ninja-build \
    gfortran \
    build-essential \
    libomp5 \
    libomp-dev \
    libbfd-dev \
    libboost-all-dev \
    libnuma1 \
    libnuma-dev \
    libpthread-stubs0-dev \
    libzstd-dev \
    lcov \
    zip \
    zlib1g-dev \
    wget \
    pkg-config \
    unzip \
    chrpath \
    doxygen \
    lshw \
    build-essential \
    libssl-dev \
    curl \
    libncursesw5-dev \
    xz-utils \
    liblzma-dev \
    python3-pip \
    python3-setuptools \
    python3-venv \
    python3-dev \
    python3-tk \
    python3-yaml \
    wget \
    && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Mellanox OFED
RUN wget -qO - https://www.mellanox.com/downloads/ofed/RPM-GPG-KEY-Mellanox | apt-key add -
RUN cd /etc/apt/sources.list.d/ && wget https://linux.mellanox.com/public/repo/mlnx_ofed/${MELLANOX_OFED_VERSION}/ubuntu22.04/mellanox_mlnx_ofed.list

RUN apt-get -qq update \
    && apt-get -qq install -y --no-install-recommends \
    ibverbs-utils libibverbs-dev libibumad3 libibumad-dev librdmacm-dev rdmacm-utils infiniband-diags ibverbs-utils \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/Kitware/CMake/releases/download/v3.28.0/cmake-3.28.0-linux-x86_64.sh \
    && chmod +x cmake-3.28.0-linux-x86_64.sh \
    && bash ./cmake-3.28.0-linux-x86_64.sh --prefix=/usr --exclude-subdir --skip-license \
    && rm cmake-3.28.0-linux-x86_64.sh

## Install UCX
ENV UCX_INSTALL_PREFIX=/opt/ucx
RUN wget https://github.com/openucx/ucx/releases/download/v1.16.0/ucx-1.16.0.tar.gz \
    && mkdir -p ucx \
    && tar -zxf ucx-1.16.0.tar.gz -C ucx --strip-components=1 \
    && cd ucx \
    && mkdir build \
    && cd build \
    && ../configure --prefix=${UCX_INSTALL_PREFIX} --with-rocm=/opt/rocm \
    && make -j$(nproc) install \
    && cd ../.. \
    && rm -rf ucx ucx-1.16.0.tar.gz

## Install OpenMPI
ENV MPI_INSTALL_PREFIX=/opt/ompi
RUN wget https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-4.1.6.tar.gz \
    && mkdir -p ompi4 \
    && tar -zxf openmpi-4.1.6.tar.gz -C ompi4 --strip-components=1 \
    && cd ompi4 \
    && mkdir build \
    && cd build \
    && ../configure --prefix=${MPI_INSTALL_PREFIX} --with-ucx=${UCX_INSTALL_PREFIX} --disable-oshmem --disable-mpi-fortran --enable-orterun-prefix-by-default \
    && make -j$(nproc) install \
    && cd ../.. \
    && rm -rf ompi4 openmpi-4.1.6.tar.gz

## building RCCL
ENV RCCL_INSTALL_PREFIX=/opt/rocm
RUN git clone --recurse-submodules -b "${RCCL_BRANCH}" "${RCCL_REPO}" ./rccl \
    && cd ./rccl \
    && ./install.sh -t -j$(nproc) --amdgpu_targets="gfx942" --prefix=${RCCL_INSTALL_PREFIX}

## building RCCL-Tests
RUN git clone -b "${RCCL_TESTS_BRANCH}" "${RCCL_TESTS_REPO}" ./rccl-tests \
    && cd ./rccl-tests \
    && make MPI=1 MPI_HOME=${MPI_INSTALL_PREFIX} NCCL_HOME=${RCCL_INSTALL_PREFIX} -j$(nproc)

## set environment variables
ENV PATH="${RCCL_INSTALL_PREFIX}/bin:${MPI_INSTALL_PREFIX}/bin:${PATH}"
ENV LD_LIBRARY_PATH="${RCCL_INSTALL_PREFIX}/lib:${MPI_INSTALL_PREFIX}/lib:${LD_LIBRARY_PATH}"

# Configure SSH
RUN sed -i 's/[ #]\(.*StrictHostKeyChecking \).*/ \1no/g' /etc/ssh/ssh_config && \
    echo "    UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config && \
    sed -i 's/#\(StrictModes \).*/\1no/g' /etc/ssh/sshd_config && \
    mkdir /var/run/sshd -p