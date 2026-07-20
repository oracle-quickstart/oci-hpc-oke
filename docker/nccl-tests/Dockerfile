ARG BASE_IMAGE=nvcr.io/nvidia/cuda-dl-base:26.06-cuda13.3-inference-devel-ubuntu24.04
ARG INSTALL_LATEST_NCCL_VERSION=true

FROM ${BASE_IMAGE}

ARG INSTALL_LATEST_NCCL_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    infiniband-diags \
    openssh-server \
    kmod \
    wget \
    ca-certificates \
    iproute2 \
    net-tools \
    iputils-ping \
    curl \
    tcpdump \
    ethtool \
    lsof \
    pciutils \
    numactl \
    iperf3 \
    autoconf \
    automake \
    libtool \
    libpci-dev \
    git \
    && if [ "${INSTALL_LATEST_NCCL_VERSION}" = "true" ]; then \
        CUDA_ARCH=$([ "$(dpkg --print-architecture)" = "amd64" ] && echo "x86_64" || echo "sbsa") \
        && wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/${CUDA_ARCH}/cuda-keyring_1.1-1_all.deb \
        && dpkg -i cuda-keyring_1.1-1_all.deb \
        && rm cuda-keyring_1.1-1_all.deb \
        && apt-get update \
        && apt-get install -y --no-install-recommends \
            libnccl2 \
            libnccl-dev; \
    fi \
    && rm -rf /var/lib/apt/lists/*

ARG NCCL_TESTS_VERSION=2.19.6
ARG NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_90,code=sm_90 -gencode=arch=compute_100,code=sm_100 -gencode=arch=compute_120,code=sm_120 -gencode=arch=compute_120,code=compute_120"
WORKDIR /workspace

RUN git clone --depth 1 --branch v${NCCL_TESTS_VERSION} https://github.com/NVIDIA/nccl-tests.git nccl-tests-${NCCL_TESTS_VERSION} \
    && cd nccl-tests-${NCCL_TESTS_VERSION} \
    && make -j MPI=1 MPI_HOME=/usr/local/mpi NVCC_GENCODE="${NVCC_GENCODE}" \
    && ln -s /workspace/nccl-tests-${NCCL_TESTS_VERSION} /workspace/nccl-tests

ARG PERFTEST_VERSION=perftest-26.01.5
RUN LIB_DIR="/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)" \
    && for lib in libibverbs.so.1 librdmacm.so.1 libibumad.so.3 libmlx5.so.1 libefa.so.1; do \
        base=$(echo $lib | sed 's/\.so\..*/\.so/'); \
        [ -e "$LIB_DIR/$lib" ] && ln -sf "$LIB_DIR/$lib" "$LIB_DIR/$base" || true; \
    done \
    && git clone --depth 1 --branch ${PERFTEST_VERSION} https://github.com/linux-rdma/perftest.git /tmp/perftest \
    && cd /tmp/perftest \
    && ./autogen.sh \
    && ./configure --prefix=/usr/local CUDA_H_PATH=/usr/local/cuda/include/cuda.h --enable-cuda --with-cuda=/usr/local/cuda --enable-mpi --with-mpi=/usr/local/mpi \
    && make -j \
    && make install \
    && rm -rf /tmp/perftest

RUN sed -i 's/[ #]\(.*StrictHostKeyChecking \).*/ \1no/g' /etc/ssh/ssh_config && \
    echo "    UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config && \
    sed -i 's/#\(StrictModes \).*/\1no/g' /etc/ssh/sshd_config && \
    mkdir /var/run/sshd -p

COPY --from=ghcr.io/huggingface/gpu-fryer:1.2.0@sha256:aaaf8dab4caf257448204d4ac66e1b04a37768849a9e8d225f431a01958b4ef7 /usr/local/bin/gpu-fryer /usr/local/bin/gpu-fryer
COPY --from=ghcr.io/astral-sh/uv:0.11.23@sha256:d0a0a753ab981624b49c97abc98821c1c09f4ca69d1ef5cee69c501be3d88479 /uv /usr/local/bin/uv

RUN curl -o /usr/sbin/ibdev2netdev https://raw.githubusercontent.com/Mellanox/container_scripts/refs/heads/master/ibdev2netdev && \
    chmod +x /usr/sbin/ibdev2netdev
