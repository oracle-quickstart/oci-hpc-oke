# Deploying the Slurm Operator Full Suite

The Terraform stack can also deploy a Slurm-on-OKE environment with Slinky:

- Slinky Slurm Operator and a Slurm cluster
- HA OpenLDAP in Kubernetes with one writable primary and read-only replicas
- SSSD/NSS integration for the controller, login pod, and worker pods
- FSS-backed `/home` through the `fss-pv` PersistentVolume
- MariaDB-backed Slurm accounting
- A LoadBalancer-backed login pod
- A shape-specific worker nodeset using `AutoDetect=rsmi` for AMD GPU shapes and `AutoDetect=nvml` for NVIDIA GPU shapes

Enable it with:

```hcl
create_bastion       = true
create_operator      = true
create_fss           = true
worker_rdma_enabled  = true
install_slinky       = true
```

The full-suite deployment currently runs from the operator host so it can perform the ordered Helm, Kubernetes, and LDAP post-configuration steps. For non-disposable deployments, override the OpenLDAP passwords before applying. Create Slurm users, home directories, SSH keys, and accounting associations manually after deployment.

## Slinky Worker Networking

Slinky workers are rendered as a `DaemonSet` by default, one Slurm worker pod per matching GPU/RDMA node. The generated NodeSet explicitly sets the worker replica count to the selected worker pool size because the Slinky Helm chart still renders `replicas` in DaemonSet mode.

The worker network mode is controlled by `slinky_worker_network_mode`:

- `hostNetwork` (default): worker pods use the node network namespace with `hostNetwork: true` and `dnsPolicy: ClusterFirstWithHostNet`. This mode does not request SR-IOV VF resources or add Multus network annotations. It mounts `/dev/infiniband` and raises the live `slurmd` memlock limit at pod startup so NCCL/RCCL RDMA jobs can register memory.
- `virtualFunctions`: worker pods keep pod networking and request SR-IOV RDMA VF resources. The generated values add the Multus `k8s.v1.cni.cncf.io/networks` annotation once per requested VF and request `slinky_worker_rdma_resource`.

Example virtual-functions override:

```hcl
slinky_worker_network_mode      = "virtualFunctions"
slinky_worker_rdma_network      = "default/sriov-rdma-vf"
slinky_worker_rdma_resource     = "nvidia.com/sriov-rdma-vf"
slinky_worker_rdma_vfs_per_node = 16
```

HostNetwork on OKE also requires stable Slurm node names. The deploy script annotates matching Kubernetes nodes with `nodeset.slinky.slurm.net/hostname-override`, and the worker pod gets `SLURM_NODE_NAME` from the Slinky `nodeset.slinky.slurm.net/pod-hostname` label. Use a Slinky operator build that honors that annotation; otherwise IP-named OKE nodes can collapse to invalid pod hostnames such as `10`.

Until that operator behavior is in the default chart image, provide a patched operator image with `slinky_operator_values_override`:

```hcl
slinky_operator_values_override = <<-YAML
operator:
  image:
    repository: <registry>/<repo>/slurm-operator
    tag: <tag-with-oke-hostname-override-support>
YAML
```

Pyxis/enroot container jobs require a Pyxis-capable login and worker image plus a Slurm plugstack config mounted into the controller, login, and worker pods. Keep that as a `slinky_slurm_values_override` until those images are the default for the stack. The validated setup used `PlugStackConfig=/opt/slurm/plugstack/plugstack.conf`, a `plugstack.conf` containing `include /usr/share/pyxis/*`, and mounted that file from a ConfigMap at `/opt/slurm/plugstack`.
