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

Pyxis/enroot container jobs are supported by default on the GPU NodeSets, so no `slinky_slurm_values_override` is needed for the default shapes. Three pieces make this work:

- The default GPU worker images are the Pyxis variants (`slurmd-nvml-nccl-pyxis` for NVIDIA, `slurmd-rocm-rccl-...-pyxis` for AMD), so `enroot` and the Pyxis SPANK plugin are present on the worker.
- The Slurm chart renders `plugstack.conf` with `include /usr/share/pyxis/*` through `configFiles`. The glob is loaded only by the login and worker pods that ship the Pyxis libraries, so it is a no-op in `slurmctld`.
- The GPU NodeSet mounts a tmpfs `/tmp` (`enroot-tmp`). Enroot writes its image-import scratch under `/tmp` and creates OverlayFS whiteouts (device nodes) while flattening layers; the pod overlay rootfs rejects `mknod` even for root, so `/tmp` must be a tmpfs.

For AMD GPU shapes, container jobs must also bind the AMD GPU and RDMA device nodes (`/dev/kfd`, `/dev/dri`, `/dev/infiniband`) with `srun --container-mounts`, because enroot has no AMD hook. The Slurm cgroup (`ConstrainDevices=yes`) still restricts the container to the GPUs allocated by `--gres`.
