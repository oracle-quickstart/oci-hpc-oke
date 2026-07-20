# nccl-tests

Docker images for running [NVIDIA NCCL Tests](https://github.com/NVIDIA/nccl-tests), built with MPI support. A single `Dockerfile` targets any CUDA version — select it via the `BASE_IMAGE` build argument.

| CUDA | `BASE_IMAGE` |
|---|---|
| 13.3 (default) | `nvcr.io/nvidia/cuda-dl-base:26.06-cuda13.3-inference-devel-ubuntu24.04` |
| 12.9 | `nvcr.io/nvidia/cuda-dl-base:25.06-cuda12.9-devel-ubuntu24.04` |

## Build arguments

| Argument | Default | Description |
|---|---|---|
| `BASE_IMAGE` | cuda13.3 (see above) | Base image to build from — sets the CUDA version |
| `NCCL_TESTS_VERSION` | `2.19.6` | nccl-tests git tag to build |
| `INSTALL_LATEST_NCCL_VERSION` | `true` | When `true`, adds the NVIDIA CUDA apt repo and installs the latest available `libnccl2` and `libnccl-dev`, overriding the version bundled in the base image |

## Build examples

### Single-arch

```bash
# Default — cuda13.3 base, latest NCCL from NVIDIA apt repo
docker build -t nccl-tests:cuda13.3 .

# cuda12.9 — select a different base image
docker build \
  --build-arg BASE_IMAGE=nvcr.io/nvidia/cuda-dl-base:25.06-cuda12.9-devel-ubuntu24.04 \
  -t nccl-tests:cuda12.9 .

# NCCL version from the base image (skip the apt-repo install)
docker build \
  --build-arg INSTALL_LATEST_NCCL_VERSION=false \
  -t nccl-tests:cuda13.3-base-nccl .
```

### Multi-arch (amd64 + arm64/sbsa)

Requires a buildx builder with multi-platform support:

```bash
docker buildx create --use --name multiarch-builder

# Build and push multi-arch manifest (cuda13.3 default)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t <registry>/nccl-tests:cuda13.3 \
  --push .

# cuda12.9
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg BASE_IMAGE=nvcr.io/nvidia/cuda-dl-base:25.06-cuda12.9-devel-ubuntu24.04 \
  -t <registry>/nccl-tests:cuda12.9 \
  --push .
```

The NCCL install step automatically selects the correct apt repo path (`x86_64` for amd64, `sbsa` for arm64).
- `ibdev2netdev` installed to `/usr/sbin/ibdev2netdev`
- Standard network/RDMA diagnostic tools: `infiniband-diags`, `iperf3`, `ethtool`, `tcpdump`, `pciutils`, `numactl`
