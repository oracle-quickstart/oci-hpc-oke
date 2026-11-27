# Images to Use for Worker Nodes

> [!NOTE]
> Use the images listed below for **all** worker pools in the cluster (system, CPU, GPU, and RDMA). These images include GPU drivers, the Lustre client, and other components required by this stack.

You can use the instructions [here](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/imageimportexport.htm#Importing) for importing the images below to your tenancy.

> [!TIP]
> This list is also available in machine-readable form in [worker-node-images.json](./worker-node-images.json) for automating image version checks. The JSON is updated together with this page. Use the `name` field to detect new images: the `url` values are download links that can change over time.

## VM.GPU.A10.1, VM.GPU.A10.2, BM.GPU.A10.4, BM.GPU4.8, BM.GPU.B4.8, BM.GPU.A100-v2.8, BM.GPU.L40S.4, BM.GPU.H100.8, BM.GPU.H200.8, BM.GPU.B200.8, BM.GPU.B300.8

### Ubuntu 24.04

#### 6.8 Kernel

- [GPU driver 580.196.07 LTS & CUDA 13.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/osB3J4-ciVUfoA0BVjmh8wVMp5rgsBAC24CdeywkvKx-_2iHXUXLZxPohJguV6d9/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-2026.11.05-0-6.8-DOCA-OFED-3.2.3-GPU-580.196.07-OPEN-CUDA-13.2-LTS-2026.11.25-0)

- [GPU driver 620 & CUDA 13.5](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/3mSUQn6AC-ATWf6PsG53wJ7bIK_ovrdBaoCFCvRNXxJoyiuR2iOY7d9jvFQjNM8F/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-2026.11.05-0-KERNEL-NVIDIA-6.8-DOCA-OFED-3.6.0-GPU-620-OPEN-CUDA-13.5-2026.11.25-0)

#### 7 Kernel

- [GPU driver 620 & CUDA 13.5](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/AwvnoRIKTvuDFzf_-irngLCB5yEF4AdbdCwA2v8u1_GTto7EqYKKlVWXZFhKQGJv/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-2026.11.05-0-KERNEL-ORACLE-7-DOCA-OFED-3.6.0-GPU-620-OPEN-CUDA-13.5-2026.11.25-0)

### Ubuntu 22.04

#### 6.8 Kernel

- [GPU driver 580.196.07 LTS & CUDA 13.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/LRpUoD7n_CST4l-svO8r7LuIoLoVnqi-OY6qQWUdE-UTUJr7IigcEOnwM5k4oIJW/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-22.04-2026.11.05-0-6.8-DOCA-OFED-3.2.3-GPU-580.196.07-OPEN-CUDA-13.2-LTS-2026.11.25-0)

## BM.GPU.GB200.4, BM.GPU.GB200-v3.4, BM.GPU.GB300.4

### Ubuntu 24.04

#### 6.8 Kernel

- [GPU driver 580.196.07 LTS & CUDA 13.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/Uq1aUHf_SBzm2tzs-uucXlcELCVu7WF3u9a57IQZyxnQdAKcAiMAzNDeX1nw0ygI/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-aarch64-2026.11.05-0-KERNEL-NVIDIA-64K-6.8-DOCA-OFED-3.2.3-GPU-580.196.07-OPEN-CUDA-13.2-LTS-2026.11.25-0)
- [GPU driver 620 & CUDA 13.5](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/Wj1xMGDLOjPyNlUtL2mNGJVCLTV5tBEBEJmSq2bkpjWDn0S7GqqdSMLLkSx4Egu7/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-aarch64-2026.11.05-0-KERNEL-NVIDIA-64K-6.8-DOCA-OFED-3.6.0-GPU-620-OPEN-CUDA-13.5-2026.11.25-0)

#### 7 Kernel

- [GPU driver 620 & CUDA 13.5](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/m1Kef0X-ZGW8tXc5dXDnNHPTb0ueJ42OoihSadSHWi71NipSbRPvSpcK5J9QklEM/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-aarch64-2026.11.05-0-KERNEL-NVIDIA-64K-7-DOCA-OFED-3.6.0-GPU-620-OPEN-CUDA-13.5-2026.11.25-0)

### Ubuntu 22.04

#### 6.8 Kernel

- [GPU driver 580.196.07 LTS & CUDA 13.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/DWTmY5iCtl16k8xh6eGenY54PGVEERX7npEiBe69or3xnVN-TEGlR3ZvBlEGEQ7N/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-22.04-aarch64-2026.11.05-0-KERNEL-NVIDIA-64K-6.8-DOCA-OFED-3.2.3-GPU-580.196.07-OPEN-CUDA-13.2-LTS-2026.11.25-0)

## BM.GPU.MI300X.8, BM.GPU.MI355X-v1.8

### Ubuntu 24.04

#### 6.8 Kernel

- [ROCm 7.14](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/wq7ZlLcf8zjB1swc8Ym8iIQv0P_j-m1-3pYIcTJU81Iu8Cc-pBM4DBxPMP-TUc7K/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-2026.11.05-0-KERNEL-ORACLE-6.8-DOCA-OFED-3.6.0-AMD-ROCM-7141-2026.11.25-0)

- [ROCm 10.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/p8vcRPc8PouX6XWWWYADkuB4LBRl9nMamcndKYO35EIfhC51CexpZvhiSsv1Az-T/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-2026.11.05-0-KERNEL-ORACLE-6.8-DOCA-OFED-3.6.0-AMD-ROCM-10.2-2026.11.25-0)

### Ubuntu 22.04

#### 6.8 Kernel

- [ROCm 10.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/hb3X2fK8fnZZpHmLj6tyArc9pbJmdMjZ3CQjnATh35ZUskPYeMnzQXfbexXv_Hdw/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-22.04-2026.11.05-0-KERNEL-ORACLE-6.8-DOCA-OFED-3.6.0-AMD-ROCM-10.2-2026.11.25-0)

## BM.GPU.MI355X.8

### Ubuntu 22.04

#### 6.8 Kernel

- [ROCm 7.2.4 & Pollara 1.117.5-a-77](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/L9oPDPkfUXM-1YSkhwCD3BIJ6RbSoLzv9f4U_FGPXj0mN_Sw4zLZDHsquo8j7b2K/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-22.04-2026.09.18-0-KERNEL-ORACLE-6.8-POLLARA-1.117.5-a-77-AMD-ROCM-7.2.4-2026.10.29-0.oci)
