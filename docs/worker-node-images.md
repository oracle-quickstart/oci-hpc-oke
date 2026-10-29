# Images to Use for Worker Nodes

> [!NOTE]
> Use the images listed below for **all** worker pools in the cluster (system, CPU, GPU, and RDMA). These images include GPU drivers, the Lustre client, and other components required by this stack.

You can use the instructions [here](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/imageimportexport.htm#Importing) for importing the images below to your tenancy.

> [!TIP]
> This list is also available in machine-readable form in [worker-node-images.json](./worker-node-images.json) for automating image version checks. The JSON is updated together with this page. Use the `name` field to detect new images: the `url` values are download links that can change over time.

## VM.GPU.A10.1, VM.GPU.A10.2, BM.GPU.A10.4, BM.GPU4.8, BM.GPU.B4.8, BM.GPU.A100-v2.8, BM.GPU.L40S.4, BM.GPU.H100.8, BM.GPU.H200.8, BM.GPU.B200.8, BM.GPU.B300.8

### Ubuntu 24.04

#### 6.8 Kernel

- [GPU driver 595 & CUDA 13.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/_rIGL48EfDt7jgiuwzEpADRV_bjNfwMGTsSa54qB7wa6JhhwIZBflFN_DAa1rDb8/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-2026.09.18-0-KERNEL-ORACLE-6.8-DOCA-OFED-3.5.0-GPU-595-OPEN-CUDA-13.2-2026.10.29-0.oci)
- [GPU driver 580.178.04 LTS & CUDA 13.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/SKUnxF5sV6C7wnIYfOGQwy9LF6-_62zHDljaI1lG2NExAajsoUmjUu5h2vg93asK/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-2026.09.18-0-6.8-DOCA-OFED-3.2.3-GPU-580.178.04-OPEN-CUDA-13.2-LTS-2026.10.29-0.oci)

#### 6.17 Kernel

- [GPU driver 595 & CUDA 13.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/nddvOzZ9qEpQnTGsvjU3n0tiPBOFfIb4S4uoEdteGaHMLgtwokfYWkl0yPVNhUDM/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-2026.09.18-0-KERNEL-ORACLE-6.17-DOCA-OFED-3.5.0-GPU-595-OPEN-CUDA-13.2-2026.10.29-0.oci)

### Ubuntu 22.04

#### 6.8 Kernel

- [GPU driver 595 & CUDA 13.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/Ep3DfojJtSW73bPrmyXjC_Va73L8yNfSpDHgE3FD6xSk3F1fPHdAdxobreyOy24J/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-22.04-2026.09.18-0-KERNEL-ORACLE-6.8-DOCA-OFED-3.5.0-GPU-595-OPEN-CUDA-13.2-2026.10.29-0.oci)
- [GPU driver 580.178.04 LTS & CUDA 13.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/vsZ9bxM8UBgotEKqvQklEJuiXKJSExgdy8nhtb_PwPzWmagLxwOOx46QKyBlYsYB/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-22.04-2026.09.18-0-6.8-DOCA-OFED-3.2.3-GPU-580.178.04-OPEN-CUDA-13.2-LTS-2026.10.29-0.oci)

## BM.GPU.GB200.4, BM.GPU.GB200-v3.4, BM.GPU.GB300.4

### Ubuntu 24.04

#### 6.8 Kernel

- [GPU driver 580.178.04 LTS & CUDA 13.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/j7s6BOI5Zm_aZWSfiDar2MG_tnlOav9UH7FKFam-y1Yr6aKaCkPqnn4AIS6TdajN/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-aarch64-2026.09.18-0-KERNEL-NVIDIA-64K-6.8-DOCA-OFED-3.2.3-GPU-580.178.04-OPEN-CUDA-13.2-LTS-2026.10.29-0.oci)

#### 6.17 Kernel

- [GPU driver 595 & CUDA 13.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/jnuCWYjvI9xFWZKierf01gCYIgZHwKR7pSXox7JqI5xGHTKwuR44F1YY4zf_t9SZ/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-aarch64-2026.09.18-0-KERNEL-NVIDIA-64K-6.17-DOCA-OFED-3.5.0-GPU-595-OPEN-CUDA-13.2-2026.10.29-0.oci)

### Ubuntu 22.04

#### 6.8 Kernel

- [GPU driver 595 & CUDA 13.2](https://idxzjcdglx2s.objectstorage.eu-frankfurt-1.oci.customer-oci.com/p/ZPwaXxeidz3BPrdzEQt_9r-CnrWWOUR_DQ7sB60j3-lqq5bXhLL0LF43J-QYGaua/n/idxzjcdglx2s/b/oci-hpc-image-builds/o/images/release/2026.10.19/Canonical-Ubuntu-22.04-aarch64-2026.09.18-0-KERNEL-NVIDIA-64K-6.8-DOCA-OFED-3.5.0-GPU-595-OPEN-CUDA-13.2-2026.10.19-0.oci)
- [GPU driver 580.178.04 LTS & CUDA 13.2](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/chmNpigaBNeyhfqyLc0T9YpR4Di2oVaCnCpd9lID4IWidGevIWMSntOCDa74mhmx/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-22.04-aarch64-2026.09.18-0-KERNEL-NVIDIA-64K-6.8-DOCA-OFED-3.2.3-GPU-580.178.04-OPEN-CUDA-13.2-LTS-2026.10.29-0.oci)

## BM.GPU.MI300X.8, BM.GPU.MI355X-v1.8

### Ubuntu 24.04

#### 6.8 Kernel

- [ROCm 10.0](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/byxi1DomviLYjh3Z3XKCu_7lzMw-01euto-y0vMTauqHOa29Y-EI6ECim47fmIOB/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-2026.09.18-0-KERNEL-ORACLE-6.8-DOCA-OFED-3.5.0-AMD-ROCM-10.0-2026.10.29-0.oci)

#### 6.17 Kernel

- [ROCm 10.0](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/qbIFiQEuPJtMfDduQxBMZSYoObW0nLOTayHyL4Qt-pi-azZT6dgEHidcWfZNPcWN/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-24.04-2026.09.18-0-KERNEL-ORACLE-6.17-DOCA-OFED-3.5.0-AMD-ROCM-10.0-2026.10.29-0.oci)

### Ubuntu 22.04

#### 6.8 Kernel

- [ROCm 10.0](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/8jorRGfJH_bViyBB0aWqFuZwZj25CsiH_rwLcezfmRI4DP0F8upJotURFsHLpf-R/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-22.04-2026.09.18-0-KERNEL-ORACLE-6.8-DOCA-OFED-3.5.0-AMD-ROCM-10.0-2026.10.29-0.oci)

## BM.GPU.MI355X.8

### Ubuntu 22.04

#### 6.8 Kernel

- [ROCm 7.2.4 & Pollara 1.117.5-a-77](https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/L9oPDPkfUXM-1YSkhwCD3BIJ6RbSoLzv9f4U_FGPXj0mN_Sw4zLZDHsquo8j7b2K/n/idxzjcdglx2s/b/hpc-images/o/Canonical-Ubuntu-22.04-2026.09.18-0-KERNEL-ORACLE-6.8-POLLARA-1.117.5-a-77-AMD-ROCM-7.2.4-2026.10.29-0.oci)
