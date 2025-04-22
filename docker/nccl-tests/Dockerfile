ARG PYTORCH_IMAGE_TAG
ARG BASE_IMAGE=nvcr.io/nvidia/pytorch:${PYTORCH_IMAGE_TAG}

FROM ${BASE_IMAGE}

RUN apt-get update && apt-get install -y \
    build-essential \
    infiniband-diags \
    openssh-server \
    kmod \
    wget \
&& rm -rf /var/lib/apt/lists/*

ARG NCCL_VERSION
ARG NCCL_TESTS_VERSION

RUN wget -qO- https://github.com/NVIDIA/nccl/archive/refs/tags/v${NCCL_VERSION}.tar.gz | tar -xvz && \
    cd nccl-${NCCL_VERSION} && \
    make -j src.build

RUN wget -qO- https://github.com/NVIDIA/nccl-tests/archive/refs/tags/v${NCCL_TESTS_VERSION}.tar.gz | tar -xvz && \
    cd nccl-tests-${NCCL_TESTS_VERSION} && \
    make -j MPI=1 MPI_HOME=/usr/local/mpi NCCL_HOME=/workspace/nccl-${NCCL_VERSION}/build && \
    ln -s /workspace/nccl-tests-${NCCL_TESTS_VERSION} /workspace/nccl-tests