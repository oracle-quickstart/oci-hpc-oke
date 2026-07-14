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
# Upgrade kmod:
sudo apt update && sudo apt install --only-upgrade kmod

# Check if the module is loaded:
grep -qE '^algif_aead ' /proc/modules && echo "Affected module is loaded" || echo "Affected module is NOT loaded"

# Unload the kernel module to apply the fix without rebooting:
sudo rmmod algif_aead 2>/dev/null || echo "Failed to unload the module. It may be in use."

# If unloading fails, the module may be in use. Stop the application using it or reboot the system.
```

#### Switch to patched Ubuntu HPC images

The Ubuntu HPC images released on 2026-05-05 or later include the fix for this CVE. See [Images to Use for Worker Nodes](./worker-node-images.md) for the latest images.

#### Switch to patched Ubuntu Platform images

Use build 2026.04.30-1 or later.

Get the latest published images using the command below:

```bash
# Replace ocid1.compartment.oc1..111 with your compartment ID
# Update the region with the desired region

oci compute image list \
    -c ocid1.compartment.oc1..abcdef \
    --operating-system "Canonical Ubuntu" \
    --sort-by TIMECREATED \
    --sort-order DESC \
    --region us-ashburn-1 \
  | jq -r '.data[]
    | select((."time-created" | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) >= ("2026-05-05T00:00:00Z" |
  fromdateiso8601))
    | [."display-name", ."time-created", .id]
    | @tsv'

# Look for images created starting 2026-05-05 (build 2026.04.30-1 or later)
```

### Mitigation

```bash
# Prevent the kernel module from loading
echo "install algif_aead /bin/false" | sudo tee /etc/modprobe.d/manual-disable-algif_aead.conf

# Check if the module is loaded:
grep -qE '^algif_aead ' /proc/modules && echo "Affected module is loaded" || echo "Affected module is NOT loaded"

# Unload the kernel module:
sudo rmmod algif_aead 2>/dev/null || echo "Failed to unload the module. It may be in use."

# If it doesn't work, it may be in use. Try to stop the application which is using it or reboot the system.
```

### References

- [Ubuntu: Copy Fail vulnerability fixes available][ubuntu-copy-fail]

## Oracle Linux

Oracle Linux has shipped an urgent fix for the CVE-2026-31431. Fixed UEK kernel versions:

| Kernel stream | Oracle Linux releases | Fixed kernel version |
| --- | --- | --- |
| UEK8 | OL9, OL10 | 6.12.0-201.74.2.2 |
| UEK7 | OL8, OL9 | 5.15.0-319.201.4.4 |
| UEK6 | OL7, OL8 | 5.4.17-2136.354.4.2 |

The OKE team is working on updating the OKE node images to use the patched kernels.

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
    -c ocid1.compartment.oc1..abcdef \
    --operating-system "Oracle Linux" \
    --sort-by TIMECREATED \
    --sort-order DESC \
    --region us-ashburn-1 \
  | jq -r '.data[]
    | select((."time-created" | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) >= ("2026-05-05T00:00:00Z" |
  fromdateiso8601))
    | [."display-name", ."time-created", .id]
    | @tsv'

# Look for images created starting 2026-05-05 (build 2026.04.30-1 or later)
```

### Mitigation

Block the vulnerable module from loading using kernel parameters and reboot the node:

```bash
sudo grubby --update-kernel=ALL --args="initcall_blacklist=algif_aead_init"
sudo reboot
```

## Oracle Linux (RHCK)

The patched RHCK kernel versions:

| Oracle Linux release | Fixed RHCK kernel version |
| --- | --- |
| OL8 | 4.18.0-553.123.1.el8_10 |
| OL9 | 5.14.0-611.54.1.el9_7 |
| OL10 | 6.12.0-124.55.1.el10_1 |

### Fix

#### Upgrade the kernel

```bash
# Check the current kernel version
uname -r

# Check the available versions for kernel upgrade
sudo dnf check-update kernel

# Confirm the version
# kernel.x86_64                          5.14.0-611.54.1.el9_7

# Upgrade the kernel to the patched version
# sudo dnf install -y kernel-5.14.0-611.54.1.el9_7
KERNEL_VERSION=5.14.0-611.54.1.el9_7
sudo dnf install -y "kernel-${KERNEL_VERSION}"


# Confirm which kernel will boot by default
sudo grubby --default-kernel

# Set a specific kernel as default
# sudo grubby --set-default /boot/vmlinuz-5.14.0-611.54.1.el9_7.x86_64
sudo grubby --set-default "/boot/vmlinuz-${KERNEL_VERSION}.x86_64"

# Reboot the node
sudo reboot
```

### Mitigation

Block the vulnerable module from loading using kernel parameters and reboot the node:

```bash
sudo grubby --update-kernel=ALL --args="initcall_blacklist=algif_aead_init"
sudo reboot
```

## Recommended approach to patch nodes in the Slurm clusters.

### Setting up ansible (optional)

If `ansible` is not available on the controller, you can execute the following commands:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env
uv tool install ansible-core
```

### Slurm clusters (v2)

To patch the nodes currently running in the slurm cluster, the recommended approach is to:
- upgrade the kmod package to the patched version (for nodes running Ubuntu)
- upgrade the kernel version to the patched version and reboot (for nodes running Oracle Linux)

```bash
wget https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/docs/files/copy-fail-patch-playbook.yml
ansible-playbook -i /etc/ansible/hosts \
  copy-fail-patch-playbook.yml
```

To ensure the new nodes spun up by the cluster-network resource use the patched image, update the instance-configuration.

```bash
wget https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/docs/files/create-instance-config.py
# replace ocid1.compartment.oc1.....abcdef with the compartment id where existing instance configuration is placed
uv run create-instance-config.py --compartment-id ocid1.compartment.oc1.....abcdef
```

### Slurm clusters (v3)

To patch the nodes **currently running** in the slurm cluster, the recommended approach is to:
- upgrade the kmod package to the patched version (for nodes running Ubuntu)
- upgrade the kernel version to the patched version and reboot (for nodes running Oracle Linux)

```bash
wget https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/docs/files/copy-fail-patch-playbook.yml -O /config/playbooks/copy-fail-patch-playbook.yml
# use the command below to get the cluster names
mgmt clusters list
# use the command below to patch the nodes in each cluster
CLUSTER_NAME="cluster-name"
mgmt nodes reconfigure --fields cluster_name=$CLUSTER_NAME --action ansible --playbook copy-fail-patch-playbook
```

To ensure the new nodes spun up by the cluster-network resource use the patched image, update the instance-configuration.

```bash
# use the command below to get the cluster names
mgmt clusters list
# use the command below to patch the nodes in each cluster
CLUSTER_NAME="cluster-name"
mgmt clusters update-instance-config --cluster-name $CLUSTER_NAME --image-id <new_image_ocid>
```


## Recommended approach to patch nodes in the OKE clusters.

To patch the **existing nodes** of the OKE cluster, the recommended approach is to apply the daemonset below:

This daemonset will run an ansible playbook on each of the node to upgrade the kernel or kmod package as needed.

  ```bash
  # download the daemonset manifest
  wget https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/docs/files/copy-fail-patch-ds.yaml

  # apply the daemonset
  kubectl apply -f copy-fail-patch-ds.yaml

  # wait for the rollout of the daemonset
  kubectl -n kube-system rollout status ds/copy-fail-patch --timeout=300s

  # confirm the pods are scheduled on all the nodes
  kubectl -n kube-system get pods -l app.kubernetes.io/name=copy-fail-patch -o wide

  # get nodes that are currently patched:
  kubectl -n kube-system logs -l app.kubernetes.io/name=copy-fail-patch --all-containers --tail=-1 | grep '^PATCH_APPLIED_NODE='

  # get nodes that require a reboot before they are patched:
  kubectl -n kube-system logs -l app.kubernetes.io/name=copy-fail-patch --all-containers --tail=-1 | grep '^PATCH_REBOOT_REQUIRED_NODE='

  # remove the daemonset once all the nodes have been upgraded:
  kubectl delete -f copy-fail-patch-ds.yaml

  # Use this command to get the list of nodes where the patch execution was successful
  kubectl get pods -n kube-system -l app.kubernetes.io/name=copy-fail-patch \
    -o jsonpath='{range .items[?(@.status.initContainerStatuses[0].state.terminated.exitCode==0)]}{.spec.nodeName}{"\n"}{end}'

  # Use this command to get the list of nodes where the patch execution failed
  kubectl get pods -n kube-system -l app.kubernetes.io/name=copy-fail-patch \
    -o custom-columns='NODE:.spec.nodeName,POD:.metadata.name,REASON:.status.initContainerStatuses[?(@.name=="patch")].state.terminated.reason,EXIT:.status.initContainerStatuses[?(@.name=="patch")].state.terminated.exitCode' \
    | awk '$4 != 0'
  ```

**Note:** Oracle Linux nodes listed under PATCH_REBOOT_REQUIRED_NODE require a reboot to apply the kernel update.


To ensure the **new nodes** use the patched image:
- for the managed nodepools, [update the nodepool configuration to use the patched image](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/update-node-pool.htm)
- for the self-managed nodes (the GPU nodes which are part of cluster-networks), use the script below to update the image_id used by the ClusterNetwork resource:

```bash
# download uv
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env

# download the script
wget https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/docs/files/create-instance-config.py

# replace ocid1.compartment.oc1.....abcdef with the compartment id of the existing instance configuration
uv run create-instance-config.py --compartment-id ocid1.compartment.oc1.....abcdef
```

## References

- [OCI CLI image list command][oci-cli-image-list]
- [Oracle Linux CVE-2026-31431 page][oracle-cve-page]

[copy-fail]: https://copy.fail/
[ubuntu-copy-fail]: https://ubuntu.com/blog/copy-fail-vulnerability-fixes-available
[oci-cli-image-list]: https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/compute/image/list.html
[oracle-cve-page]: https://linux.oracle.com/cve/CVE-2026-31431.html
