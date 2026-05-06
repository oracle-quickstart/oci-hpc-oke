# CVE-2026-31431 ("Copy Fail")

This is a high-severity (CVSS ~7.8) local privilege escalation vulnerability in the Linux kernel's `algif_aead` cryptographic module. It arises from a flawed in-place buffer optimization that allows an unprivileged local attacker to use AF_ALG sockets and the `splice()` syscall to perform a controlled 4-byte overwrite in the page cache of arbitrary readable files, including setuid binaries. This enables reliable root privilege escalation on affected kernels (most distributions since 2017). A short public exploit exists, making it easy to weaponize. Mitigation requires applying the kernel patch or disabling the vulnerable module.

See [copy.fail][copy-fail] for additional details.

## Ubuntu

This affects all Ubuntu releases with kernels from 2017 through the latest patches, except 26.04.

Affected Ubuntu releases available in OCI:
- Focal (20.04) (kmod < 27-1ubuntu2.1+esm1)
- Jammy (22.04) (kmod < 29-1ubuntu1.1)
- Noble (24.04) (kmod < 31+20240202-2ubuntu7.2)

To get the current kmod version:

```bash
dpkg -s kmod | grep Version
```

### Fix

#### Upgrade the kmod package

```bash
# Check if the module is loaded:
grep -qE '^algif_aead ' /proc/modules && echo "Affected module is loaded" || echo "Affected module is NOT loaded"

# Unload the kernel module:
sudo rmmod algif_aead 2>/dev/null || echo "Failed to unload the module. It may be in use."

# If it doesn't work, it may be in use. Try to stop the application which is using it or reboot the system.

# Upgrade kmod:
sudo apt update && sudo apt install --only-upgrade kmod
```

#### Switch to patched Ubuntu HPC images

##### Jammy (22.04)

- NVIDIA Grace-Blackwell GB200/GB300
  - Stack: CUDA 13.0
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-22.04-aarch64-2026.02.28-0-DOCA-OFED-3.2.1-GPU-580-OPEN-CUDA-13.0-2026.05.05-0
    ```
- NVIDIA Ampere/Hopper/Blackwell A100/H100
  - Stack: CUDA 13.0
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-22.04-2026.02.28-0-DOCA-OFED-3.2.1-GPU-580-OPEN-CUDA-13.0-2026.05.05-0
    ```
- NVIDIA Ampere/Hopper/Blackwell A100/H100
  - Stack: CUDA 13.1
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-22.04-2026.02.28-0-DOCA-OFED-3.2.1-GPU-590-OPEN-CUDA-13.1-2026.05.05-0
    ```
- AMD MI300X/MI355X CX-7
  - Stack: ROCm 6.4.3
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-22.04-2026.02.28-0-DOCA-OFED-3.2.1-AMD-ROCM-643-2026.05.05-0
    ```
- AMD MI300X/MI355X CX-7
  - Stack: ROCm 7.2
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-22.04-2026.02.28-0-DOCA-OFED-3.2.1-AMD-ROCM-72-2026.05.05-0
    ```
- HPC non-GPU
  - Stack: DOCA/OFED 3.2.1
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-22.04-2026.02.28-0-DOCA-OFED-3.2.1-2026.05.05-0
    ```

##### Noble (24.04)

- NVIDIA Grace-Blackwell GB200/GB300
  - Kernel: 6.17
  - Stack: CUDA 13.0
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-24.04-aarch64-2026.02.28-0-6.17-DOCA-OFED-3.2.1-GPU-580-OPEN-CUDA-13.0-2026.05.05-0
    ```
- NVIDIA Grace-Blackwell GB200/GB300
  - Kernel: 6.8
  - Stack: CUDA 13.0
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-24.04-aarch64-2026.02.28-0-6.8-DOCA-OFED-3.2.1-GPU-580-OPEN-CUDA-13.0-2026.05.05-0
    ```
- NVIDIA Ampere/Hopper/Blackwell A100/H100
  - Kernel: 6.8
  - Stack: CUDA 13.0
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-24.04-2026.02.28-0-6.8-DOCA-OFED-3.2.1-GPU-580-OPEN-CUDA-13.0-2026.05.05-0
    ```
- NVIDIA Ampere/Hopper/Blackwell A100/H100
  - Kernel: 6.8
  - Stack: CUDA 13.1
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-24.04-2026.02.28-0-6.8-DOCA-OFED-3.2.1-GPU-590-OPEN-CUDA-13.1-2026.05.05-0
    ```
- NVIDIA Ampere/Hopper/Blackwell A100/H100
  - Kernel: 6.14
  - Stack: CUDA 13.1
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-24.04-2026.02.28-0-6.14-DOCA-OFED-3.2.1-GPU-590-OPEN-CUDA-13.1-2026.05.05-0
    ```
- AMD MI300X/MI355X CX-7
  - Kernel: 6.8
  - Stack: ROCm 6.4.3
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-24.04-2026.02.28-0-6.8-DOCA-OFED-3.2.1-AMD-ROCM-643-2026.05.05-0
    ```
- AMD MI300X/MI355X CX-7
  - Kernel: 6.8
  - Stack: ROCm 7.2
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-24.04-2026.02.28-0-6.8-DOCA-OFED-3.2.1-AMD-ROCM-72-2026.05.05-0
    ```
- AMD MI300X/MI355X CX-7
  - Kernel: 6.14
  - Stack: ROCm 7.2
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-24.04-2026.02.28-0-6.14-DOCA-OFED-3.2.1-AMD-ROCM-72-2026.05.05-0
    ```
- HPC non-GPU
  - Kernel: 6.8
  - Stack: DOCA/OFED 3.2.1
  - Image URL:

    ```text
    https://objectstorage.ca-montreal-1.oraclecloud.com/p/AIo4CP0P_DlUelDlsWgGPWmY6FcBQzJWmmFyGKdY0epkh87a9Q3ndvFYycjIxTQ9/n/idxzjcdglx2s/b/images/o/Canonical-Ubuntu-24.04-2026.02.28-0-6.8-DOCA-OFED-3.2.1-2026.05.05-0
    ```

#### Switch to patched Ubuntu Platform images

Use build 2026.04.30-1 or later.

Get the latest published images using the command below:

```bash
# Replace ocid1.compartment.oc1..111 with your compartment ID
# Update the region with the desired region

oci compute image list \
  -c ocid1.compartment.oc1..111 \
  --operating-system "Canonical Ubuntu" \
  --sort-by TIMECREATED \
  --sort-order DESC \
  --region us-ashburn-1 | grep 2026.04.30-1 -A2

# Look for images created starting 2026-05-05 (build 2026.04.30-1 or later)
```

### Mitigation

```bash
# Check if the module is loaded:
grep -qE '^algif_aead ' /proc/modules && echo "Affected module is loaded" || echo "Affected module is NOT loaded"

# Unload the kernel module:
sudo rmmod algif_aead 2>/dev/null || echo "Failed to unload the module. It may be in use."

# If it doesn't work, it may be in use. Try to stop the application which is using it or reboot the system.

# Prevent the kernel module from loading
echo "install algif_aead /bin/false" | sudo tee /etc/modprobe.d/manual-disable-algif_aead.conf
```

### References

- [Ubuntu: Copy Fail vulnerability fixes available][ubuntu-copy-fail]

## Oracle Linux

Oracle Linux has shipped an urgent fix for the CVE-2026-31431. Fixed kernel versions:

- UEK8: 6.12.0-201.74.2.2
- UEK7: 5.15.0-319.201.4.4
- UEK6: 5.4.17-2136.354.4.2

The OKE team is working on updating the OKE node images to use the patched kernels.

We are currently working on shipping kernel updates for customer environments using RHCK (see also the mitigation section below).

### Fix

#### Upgrade the kernel

```bash
dnf upgrade kernel-uek
reboot
```

#### Switch to patched Oracle Linux Platform images

Use build 2026.04.30-1 or later.

Get the latest published images using the command below:

```bash
# Replace ocid1.compartment.oc1..111 with your compartment ID
# Update the region with the desired region

oci compute image list \
  -c ocid1.compartment.oc1..111 \
  --operating-system "Oracle Linux" \
  --sort-by TIMECREATED \
  --sort-order DESC \
  --region us-ashburn-1 | grep 2026.04.30-1 -A2

# Look for images created starting 2026-05-05 (build 2026.04.30-1 or later)
```

### Mitigation

Block the vulnerable module from loading using kernel parameters:

```bash
sudo grubby --update-kernel=ALL --args="initcall_blacklist=algif_aead_init"
sudo reboot
```

### References

- [OCI CLI image list command][oci-cli-image-list]

[copy-fail]: https://copy.fail/
[ubuntu-copy-fail]: https://ubuntu.com/blog/copy-fail-vulnerability-fixes-available
[oci-cli-image-list]: https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/compute/image/list.html
