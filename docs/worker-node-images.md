# Images to Use for Worker Nodes

> [!NOTE]
> Use the images listed below for **all** worker pools in the cluster (system, CPU, GPU, and RDMA). These images include GPU drivers, the Lustre client, and other components required by this stack.

You can use the instructions [here](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/imageimportexport.htm#Importing) for importing the images below to your tenancy.

> [!TIP]
> This list is also available in machine-readable form in [worker-node-images.json](./worker-node-images.json) for automating image version checks. The JSON is updated together with this page. Use the `name` field to detect new images: the `url` values are download links that can change over time.

## VM.GPU.A10.1, VM.GPU.A10.2, BM.GPU.A10.4, BM.GPU4.8, BM.GPU.B4.8, BM.GPU.A100-v2.8, BM.GPU.L40S.4, BM.GPU.H100.8, BM.GPU.H200.8, BM.GPU.B200.8, BM.GPU.B300.8

### Ubuntu 24.04

#### 6.8 Kernel

- [GPU driver 595 & CUDA 13.2](https://idxzjcdglx2s.objectstorage.eu-frankfurt-1.oci.customer-oci.com/p/rr0d4Zw8yIc-Bwwu8cUDPJ6ooh4LQ_SVHPDBFJ5T89j2drv-hmkeMTwVv8DANpvC/n/idxzjcdglx2s/b/oci-hpc-image-builds/o/images/2026.07.13/Canonical-Ubuntu-24.04-2026.02.28-0-KERNEL-ORACLE-6.8-DOCA-OFED-3.4.0-GPU-595-OPEN-CUDA-13.2-2026.07.13-0.oci)

#### 6.14 Kernel

- [GPU driver 595 & CUDA 13.2](https://idxzjcdglx2s.objectstorage.eu-frankfurt-1.oci.customer-oci.com/p/rr0d4Zw8yIc-Bwwu8cUDPJ6ooh4LQ_SVHPDBFJ5T89j2drv-hmkeMTwVv8DANpvC/n/idxzjcdglx2s/b/oci-hpc-image-builds/o/images/2026.07.13/Canonical-Ubuntu-24.04-2026.02.28-0-KERNEL-ORACLE-6.14-DOCA-OFED-3.4.0-GPU-595-OPEN-CUDA-13.2-2026.07.13-0.oci)

### Ubuntu 22.04

#### 6.8 Kernel

- [GPU driver 595 & CUDA 13.2](https://idxzjcdglx2s.objectstorage.eu-frankfurt-1.oci.customer-oci.com/p/rr0d4Zw8yIc-Bwwu8cUDPJ6ooh4LQ_SVHPDBFJ5T89j2drv-hmkeMTwVv8DANpvC/n/idxzjcdglx2s/b/oci-hpc-image-builds/o/images/2026.07.13/Canonical-Ubuntu-22.04-2026.02.28-0-KERNEL-ORACLE-6.8-DOCA-OFED-3.4.0-GPU-595-OPEN-CUDA-13.2-2026.07.13-0.oci)

## BM.GPU.GB200.4, BM.GPU.GB200-v3.4, BM.GPU.GB300.4

### Ubuntu 24.04

#### 6.8 Kernel

- [GPU driver 595 & CUDA 13.2](https://idxzjcdglx2s.objectstorage.eu-frankfurt-1.oci.customer-oci.com/p/rr0d4Zw8yIc-Bwwu8cUDPJ6ooh4LQ_SVHPDBFJ5T89j2drv-hmkeMTwVv8DANpvC/n/idxzjcdglx2s/b/oci-hpc-image-builds/o/images/2026.07.13/Canonical-Ubuntu-24.04-aarch64-2026.02.28-0-KERNEL-NVIDIA-64K-6.8-DOCA-OFED-3.4.0-GPU-595-OPEN-CUDA-13.2-2026.07.13-0.oci)

#### 6.14 Kernel

- [GPU driver 595 & CUDA 13.2](https://idxzjcdglx2s.objectstorage.eu-frankfurt-1.oci.customer-oci.com/p/rr0d4Zw8yIc-Bwwu8cUDPJ6ooh4LQ_SVHPDBFJ5T89j2drv-hmkeMTwVv8DANpvC/n/idxzjcdglx2s/b/oci-hpc-image-builds/o/images/2026.07.13/Canonical-Ubuntu-24.04-aarch64-2026.02.28-0-KERNEL-NVIDIA-64K-6.14-DOCA-OFED-3.4.0-GPU-595-OPEN-CUDA-13.2-2026.07.13-0.oci)

### Ubuntu 22.04

#### 6.8 Kernel

- [GPU driver 595 & CUDA 13.2](https://idxzjcdglx2s.objectstorage.eu-frankfurt-1.oci.customer-oci.com/p/rr0d4Zw8yIc-Bwwu8cUDPJ6ooh4LQ_SVHPDBFJ5T89j2drv-hmkeMTwVv8DANpvC/n/idxzjcdglx2s/b/oci-hpc-image-builds/o/images/2026.07.13/Canonical-Ubuntu-22.04-aarch64-2026.02.28-0-KERNEL-NVIDIA-64K-6.8-DOCA-OFED-3.4.0-GPU-595-OPEN-CUDA-13.2-2026.07.13-0.oci)

## BM.GPU.MI300X.8, BM.GPU.MI355X-v1.8

### Ubuntu 24.04

#### 6.8 Kernel

- [ROCm 7.2.4](https://idxzjcdglx2s.objectstorage.eu-frankfurt-1.oci.customer-oci.com/p/rr0d4Zw8yIc-Bwwu8cUDPJ6ooh4LQ_SVHPDBFJ5T89j2drv-hmkeMTwVv8DANpvC/n/idxzjcdglx2s/b/oci-hpc-image-builds/o/images/2026.07.13/Canonical-Ubuntu-24.04-2026.02.28-0-KERNEL-ORACLE-6.8-DOCA-OFED-3.4.0-AMD-ROCM-724-2026.07.13-0.oci)

#### 6.14 Kernel

- [ROCm 7.2.4](https://idxzjcdglx2s.objectstorage.eu-frankfurt-1.oci.customer-oci.com/p/rr0d4Zw8yIc-Bwwu8cUDPJ6ooh4LQ_SVHPDBFJ5T89j2drv-hmkeMTwVv8DANpvC/n/idxzjcdglx2s/b/oci-hpc-image-builds/o/images/2026.07.13/Canonical-Ubuntu-24.04-2026.02.28-0-KERNEL-ORACLE-6.14-DOCA-OFED-3.4.0-AMD-ROCM-724-2026.07.13-0.oci)

### Ubuntu 22.04

#### 6.8 Kernel

- [ROCm 7.2.4](https://idxzjcdglx2s.objectstorage.eu-frankfurt-1.oci.customer-oci.com/p/rr0d4Zw8yIc-Bwwu8cUDPJ6ooh4LQ_SVHPDBFJ5T89j2drv-hmkeMTwVv8DANpvC/n/idxzjcdglx2s/b/oci-hpc-image-builds/o/images/2026.07.13/Canonical-Ubuntu-22.04-2026.02.28-0-KERNEL-ORACLE-6.8-DOCA-OFED-3.4.0-AMD-ROCM-724-2026.07.13-0.oci)

## BM.GPU.MI355X.8

### Ubuntu 24.04

- [ROCm 7.2.1](https://objectstorage.ap-kulai-1.oraclecloud.com/p/tbQvgvf3OBUWCUHudgkXKWKQcKXDc1FUvLlcAqn0gIJGucJ7oVuojGo24vPoiymV/n/hpctraininglab/b/Sudhir-Bucket/o/Canonical-Ubuntu-24.04-2026.02.28-0-MOFED-2410_1140-AMD-ROCM-721-oca-plugin-157-10-2967-ipv4-2026.04.08-0)

### Ubuntu 22.04

- [ROCm 7.0.2](https://objectstorage.us-saltlake-2.oraclecloud.com/p/02QYYf_pFsZlBzMQi5-kp3jTYTJiX4RnkOfgpqTxlvwpO7pCie2bfYrRCr5KD_ll/n/hpctraininglab/b/Sudhir-test-bucket/o/Canonical-Ubuntu-22.04-Kernel-5.15-OFED-5.9-AMD-ROCM-702_POLLARA-OPENMPI-4.1.6)
