# Boot Volume Replacement Script

## Introduction

Node Boot Volume Replacement brings significant operational benefits when managing bare metal worker nodes in OKE. It enables updates to key node attributes (like Kubernetes version, host image, and SSH keys) without terminating the underlying instance, preserving the instance OCID and network identity. This is especially valuable for bare metal nodes, where replacement times are longer and shape availability can be constrained. By eliminating the need to re-provision entire instances, the process becomes faster and more resource-efficient, reducing downtime and minimizing disruption to workloads. It also supports use cases like correcting configuration drift and applying critical security updates with minimal operational complexity.

The script works on both self-managed nodes and OKE managed node pools. See the [Managed node pools](#managed-node-pools) section below for the differences.

## Script vs OKE Native BVR

The [OKE Native BVR](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/replace-boot-volume-worker-node-top.htm) doesn't support cloud-init upgrade on the self-managed nodes. This is extremely important when working with BM nodes using the RDMA network.


## How to use the script?

### Prerequisites

1. You can find the Boot Volume Replacement script [here](https://github.com/oracle-quickstart/oci-hpc-oke/blob/main/docs/files/bvr-script.py).

2. Install [uv](https://docs.astral.sh/uv/getting-started/installation/).

For macOS/Linux:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```
### Script parameters


| Argument                      | Required | Default                | Description                                                                                                                      |
|-------------------------------|----------|------------------------|----------------------------------------------------------------------------------------------------------------------------------|
| -c, --compartment-id          | Yes      |                        | Kubernetes cluster compartment OCID.                                                                                             |
| nodes                         | Yes      |                        | Name of the Kubernetes node(s) for which to execute Boot Volume Replacement. E.g. 10.10.1.1 10.10.1.2 10.10.1.3.<br>If the node name is an OCID, the node will be identified based on the OCID. (in this case, OKE drain and cordon will be skipped) |
| --ssh-authorized-keys         | No       | ""                     | SSH authorized keys to replace the existing SSH authorized keys on the node.                                                     |
| --interactive                 | No       | False                  | Enable interactive execution of the script.                                                                                      |
| --cloud-init-file             | No       | ""                     | File with new node cloud-init (text, non-base64 encoded). If not provided, the existing node cloud-init is used.                 |
| --image-ocid                  | No       | ""                     | Image OCID to use for the new BootVolume. If not provided, the current node image is used.                                       |
| -p, --parallelism             | No       | 1                      | How many nodes to upgrade in parallel. Not recommended together with --interactive.                            |
| --bv-size                     | No       | 0                      | Size of the new boot volume in GB. If not set (or 0), the size of the existing boot volume will be used.                         |
| --remove-previous-boot-volume | No       | False                  | Remove the existing boot volume after the upgrade. By default, the existing boot volume is preserved.                            |
| --node-metadata               | No       | "{}"                   | Metadata to add to the new node.                                                                                                 |
| --desired-k8s-version         | No       | ""                     | Works only with the nodes created using the standard OCI OKE HPC Module. The version should start with v. E.g. v1.33.1            |
| --timeout-seconds             | No       | 900                    | Timeout in seconds to wait for nodes to join the cluster after Boot Volume Replacement.                                          |
| --kubeconfig                  | No       | "~/.kube/config"       | Override the path to the kubeconfig file. Default is '~/.kube/config'                                                            |
| --oci-config-file             | No       | "~/.oci/config"        | Override the path to the oci_config file. Default is '~/.oci/config'                                                             |
| --oci-config-profile          | No       | "DEFAULT"              | OCI config profile to use. Default is 'DEFAULT'                                                                                  |
| --region                      | No       |                        | The region to target. Required when using auth='instance_principal'                                                              |
| --auth                        | No       |                        | Set OCI authentication method. Currently supported values: 'config_file', 'instance_principal', 'cloud_shell'                     |
| --help                        | No       |                        | Show help message and exit                                                                                                       |
| --debug                       | No       | False                  | Enable debug logging                                                                                                             |

Sample command:

```bash

k get nodes
NAME          STATUS   ROLES   AGE     VERSION
10.30.1.108   Ready    node    35d     v1.32.1
10.30.1.242   Ready    node    5m11s   v1.31.1

uv run bvr-script.py -c ocid1.compartment.oc1..aaaaaaaaqi3if6t4n24qyabx5pjzlw6xovcbgugcmatavjvapyq3jfb4diqq --auth instance_principal --region eu-frankfurt-1 10.30.1.242 --desired-k8s-version v1.32.1
```

### Managed node pools

The script also works on OKE managed node pool nodes, with two differences from self-managed nodes:

1. **Pass the OKE node name, not the IP.** Managed node pool nodes are named like `oke-cxhuk3rmsoq-nienmrznc6a-s6f372m3efa-0`, not by their IP. Use that name as the `nodes` argument. (The IP works only for self-managed nodes, whose Kubernetes node name is the IP.)

2. **Managed behavior is auto-detected.** The script detects managed nodes via the `oci.oraclecloud.com/node.info.managed=true` label and adjusts automatically:
   - It **preserves the Kubernetes Node object** (it does not delete it). The per-node `NativePodNetwork` (NPN) custom resource is owned by the Node, so deleting the Node would cascade-delete the NPN. Nothing recreates it, and the VCN-native IP CNI would then hang waiting for the NPN, leaving the node `NotReady`.
   - It **refreshes the bootstrap token.** Replacing the boot volume wipes `/var/lib/kubelet`, forcing a fresh kubelet TLS bootstrap using the token in the instance's `bootstrap-kubelet-conf` metadata. That token may have expired, so the script mints a fresh kubeadm-style bootstrap token, registers it in `kube-system`, and swaps it into the metadata before the replacement.
   - It **uncordons the node** once it rejoins (the node stays cordoned across the replacement because the Node object is preserved).

Prerequisite: the kubeconfig used must be able to create secrets in the `kube-system` namespace (the OKE operator / a cluster-admin kubeconfig can).

### Notes

If you need to execute other replacements in the existing cloud-init file, you can append new functions to the `cloud_init_change_functions` variable.

Example:

```python
    cloud_init_change_functions.append(lambda cloud_init_data: cloud_init_data.replace(
        "https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/files/oke-nvme-raid.sh",
        "https://raw.githubusercontent.com/OguzPastirmaci/misc/refs/heads/main/oke-nvme-provisioner/oke-nvme-bvr.sh")
    )
```
