# Images to Use for Worker Nodes

> [!NOTE]
> Use the images listed below for **all** worker pools in the cluster (system, CPU, GPU, and RDMA). These images include GPU drivers, the Lustre client, and other components required by this stack.

You can use the instructions [here](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/imageimportexport.htm#Importing) for importing the images below to your tenancy.

## VM.GPU.A10.1, VM.GPU.A10.2, BM.GPU.A10.4, BM.GPU4.8, BM.GPU.B4.8, BM.GPU.A100-v2.8, BM.GPU.L40S.4, BM.GPU.H100.8, BM.GPU.H200.8, BM.GPU.B200.8, BM.GPU.B300.8

### Ubuntu 24.04

- [GPU driver 590 & CUDA 13.1](https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-24.04-2026.02.28-0-6.8-DOCA-OFED-3.2.1-GPU-590-OPEN-CUDA-13.1-2026.05.05-0)

- [GPU driver 580 & CUDA 13.0](https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-24.04-2026.02.28-0-6.8-DOCA-OFED-3.2.1-GPU-580-OPEN-CUDA-13.0-2026.05.05-0)

### Ubuntu 22.04

- [GPU driver 590 & CUDA 13.1](https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-22.04-2026.02.28-0-DOCA-OFED-3.2.1-GPU-590-OPEN-CUDA-13.1-2026.05.05-0)

- [GPU driver 580 & CUDA 13.0](https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-22.04-2026.02.28-0-DOCA-OFED-3.2.1-GPU-580-OPEN-CUDA-13.0-2026.05.05-0)

## BM.GPU.GB200.4, BM.GPU.GB200-v3.4, BM.GPU.GB300.4

### Ubuntu 24.04

- [GPU driver 580 & CUDA 13.0](https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-24.04-aarch64-2026.02.28-0-6.8-DOCA-OFED-3.2.1-GPU-580-OPEN-CUDA-13.0-2026.05.05-0)

### Ubuntu 22.04

- [GPU driver 580 & CUDA 13.0](https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-22.04-aarch64-2026.02.28-0-DOCA-OFED-3.2.1-GPU-580-OPEN-CUDA-13.0-2026.05.05-0)

## BM.GPU.MI300X.8, BM.GPU.MI355X-v1.8

### Ubuntu 24.04

- [ROCm 7.2.0](https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-24.04-2026.02.28-0-6.8-DOCA-OFED-3.2.1-AMD-ROCM-72-2026.05.05-0)

### Ubuntu 22.04

- [ROCm 7.2.0](https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-22.04-2026.02.28-0-DOCA-OFED-3.2.1-AMD-ROCM-72-2026.05.05-0)

## BM.GPU.MI355X.8

### Ubuntu 24.04

- [ROCm 7.2.1](https://objectstorage.ap-kulai-1.oraclecloud.com/p/tbQvgvf3OBUWCUHudgkXKWKQcKXDc1FUvLlcAqn0gIJGucJ7oVuojGo24vPoiymV/n/hpctraininglab/b/Sudhir-Bucket/o/Canonical-Ubuntu-24.04-2026.02.28-0-MOFED-2410_1140-AMD-ROCM-721-oca-plugin-157-10-2967-ipv4-2026.04.08-0)

### Ubuntu 22.04

- [ROCm 7.0.2](https://objectstorage.us-saltlake-2.oraclecloud.com/p/02QYYf_pFsZlBzMQi5-kp3jTYTJiX4RnkOfgpqTxlvwpO7pCie2bfYrRCr5KD_ll/n/hpctraininglab/b/Sudhir-test-bucket/o/Canonical-Ubuntu-22.04-Kernel-5.15-OFED-5.9-AMD-ROCM-702_POLLARA-OPENMPI-4.1.6)
