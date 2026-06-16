# syntax=docker/dockerfile:1.7
#
# Slinky slurmd image for OKE GPU shapes that need both:
# - the validated Slurm NVML AutoDetect path from slurmd-nvml-core
# - NCCL test/runtime payloads for Slurm-launched NCCL jobs
#
# This intentionally reuses the NCCL/HPCX payload from the nccl-tests image
# already validated on GB300 instead of rebuilding NCCL inside the Slurm image.
#
# Multi-platform build:
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     -t iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-nvml-nccl-25.11.6-ubuntu24.04-2026-06-16.0 \
#     --push .

ARG BASE_SLURMD_IMAGE=iad.ocir.io/idxzjcdglx2s/slurm-operator:slurmd-nvml-core-25.11.6-ubuntu24.04-2026-06-16.0
ARG NCCL_TESTS_IMAGE=iad.ocir.io/idxzjcdglx2s/nccl-tests:cuda-13.1.1-ubuntu-24.04-nccl-2.29.3-020926.1

FROM --platform=$TARGETPLATFORM ${NCCL_TESTS_IMAGE} AS nccl-tests

FROM --platform=$TARGETPLATFORM ${BASE_SLURMD_IMAGE}

SHELL ["bash", "-o", "pipefail", "-c"]

ARG TARGETARCH
ARG BASE_SLURMD_IMAGE
ARG NCCL_TESTS_IMAGE

USER root
WORKDIR /

RUN --mount=from=nccl-tests,source=/,target=/nccl-root,readonly <<'EOR'
set -xeuo pipefail

case "$(dpkg --print-architecture)" in
  amd64)
    multiarch="x86_64-linux-gnu"
    cuda_target="x86_64-linux"
    ;;
  arm64)
    multiarch="aarch64-linux-gnu"
    cuda_target="sbsa-linux"
    ;;
  *)
    echo "Unsupported architecture: $(dpkg --print-architecture)" >&2
    exit 1
    ;;
esac

mkdir -p /opt/nccl-tests/bin /opt/nccl-tests/lib /opt/hpcx /workspace

# Keep a stable source tree layout available for compatibility with existing
# commands that call /workspace/nccl-tests/build/all_reduce_perf.  The source
# image may use either /workspace/nccl-tests or /workspace/nccl-tests-<version>.
nccl_build="$(find /nccl-root/workspace -maxdepth 4 -path '*/build/all_reduce_perf' -type f -print -quit)"
if [ -n "${nccl_build}" ]; then
  nccl_src="$(dirname "$(dirname "${nccl_build}")")"
  cp -aL "${nccl_src}" /workspace/nccl-tests
  cp -a "/workspace/nccl-tests/build/"*_perf /opt/nccl-tests/bin/
else
  cp -a /nccl-root/usr/local/bin/*_perf /opt/nccl-tests/bin/
  mkdir -p /workspace/nccl-tests/build
  cp -a /opt/nccl-tests/bin/*_perf /workspace/nccl-tests/build/
fi

# Stage NCCL and CUDA runtime libs in a stable, architecture-neutral path.
cp -a /nccl-root/usr/lib/${multiarch}/libnccl.so* /opt/nccl-tests/lib/

if [ -d "/nccl-root/usr/local/cuda/targets/${cuda_target}/lib" ]; then
  cp -a /nccl-root/usr/local/cuda/targets/${cuda_target}/lib/libcudart.so* /opt/nccl-tests/lib/
fi
if [ -d "/nccl-root/usr/local/cuda-13.1/targets/${cuda_target}/lib" ]; then
  cp -a /nccl-root/usr/local/cuda-13.1/targets/${cuda_target}/lib/libcudart.so* /opt/nccl-tests/lib/
fi

# Copy the HPCX pieces used by the validated GB300 run.  The Spectrum-X plugin
# is the primary NCCL net plugin; RDMA/SHARP is included for optional tests.
for d in ompi ucx sharp nccl_spectrum-x_plugin nccl_rdma_sharp_plugin; do
  if [ -d "/nccl-root/opt/hpcx/${d}" ]; then
    cp -a "/nccl-root/opt/hpcx/${d}" /opt/hpcx/
  fi
done

# Optional diagnostic utilities from the NCCL image.
for bin in gpu-fryer ib_write_bw ib_read_bw ib_send_bw ibv_rc_pingpong; do
  if [ -x "/nccl-root/usr/local/bin/${bin}" ]; then
    cp -a "/nccl-root/usr/local/bin/${bin}" /usr/local/bin/
  fi
done
if [ -x /nccl-root/usr/sbin/ibdev2netdev ]; then
  cp -a /nccl-root/usr/sbin/ibdev2netdev /usr/sbin/ibdev2netdev
fi

ln -sf /opt/nccl-tests/bin/*_perf /usr/local/bin/

LD_LIBRARY_PATH=/opt/nccl-tests/lib:/opt/hpcx/ucx/lib:/opt/hpcx/ompi/lib:/opt/hpcx/nccl_spectrum-x_plugin/lib ldd /opt/nccl-tests/bin/all_reduce_perf
test -x /opt/nccl-tests/bin/all_reduce_perf
test -f /opt/nccl-tests/lib/libnccl.so.2
test -f /opt/hpcx/ompi/lib/libmpi.so.40
test -f /opt/hpcx/nccl_spectrum-x_plugin/lib/libnccl-net.so
test -f /usr/lib/${multiarch}/slurm/gpu_nvml.so
test -f /usr/lib/${multiarch}/slurm/gres_gpu.so
EOR

RUN cat > /opt/nccl-tests/IMAGE_NOTES.md <<EOR
# slurmd-nvml-nccl

Base Slurm worker image:

\`${BASE_SLURMD_IMAGE}\`

NCCL payload source image:

\`${NCCL_TESTS_IMAGE}\`

Important paths:

- \`/opt/nccl-tests/bin/*_perf\`
- \`/workspace/nccl-tests/build/*_perf\`
- \`/opt/nccl-tests/lib\`
- \`/opt/hpcx/ompi\`
- \`/opt/hpcx/ucx\`
- \`/opt/hpcx/nccl_spectrum-x_plugin\`
- \`/opt/hpcx/nccl_rdma_sharp_plugin\`

The image keeps Slurm's NVML GPU AutoDetect plugins from the base worker image
and adds the NCCL/HPCX runtime stack validated on the GB300 Slurm IMEX/DRA run.
EOR

RUN <<'EOR'
set -xeuo pipefail
cat > /opt/nccl-tests/env.sh <<'EOF'
export NCCL_TEST_HOME=/opt/nccl-tests
export PATH=/opt/hpcx/ompi/bin:/opt/nccl-tests/bin:${PATH}
export LD_LIBRARY_PATH=/opt/nccl-tests/lib:/opt/hpcx/ucx/lib:/opt/hpcx/ompi/lib:/opt/hpcx/nccl_spectrum-x_plugin/lib:/opt/hpcx/nccl_rdma_sharp_plugin/lib:${LD_LIBRARY_PATH:-}
export OPAL_PREFIX=/opt/hpcx/ompi
EOF
cat > /usr/local/bin/with-nccl-tests-env <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /opt/nccl-tests/env.sh
exec "$@"
EOF
chmod 0644 /opt/nccl-tests/env.sh
chmod 0755 /usr/local/bin/with-nccl-tests-env
EOR

ENV NCCL_TEST_HOME=/opt/nccl-tests
ENV PATH=/opt/nccl-tests/bin:${PATH}

WORKDIR /
