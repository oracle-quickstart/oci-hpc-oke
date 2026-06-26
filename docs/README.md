# Documentation

Guides for deploying and operating GPU and RDMA workloads on Oracle Kubernetes
Engine (OKE). For deployment and project overview, see the
[main README](../README.md).

## Cluster access and operations

- [Accessing a Private OKE Cluster via OCI Bastion Service](./accessing-private-oke-cluster-via-oci-bastion-service.md): Reach a private cluster's API server through the OCI Bastion service.
- [Adding SSH Public Keys to Worker Nodes](./adding-ssh-keys-to-worker-nodes.md): Add SSH public keys to running worker nodes.
- [Upgrading OKE Clusters](./oke-hpc-upgrade.md): Upgrade OKE HPC clusters and node pools.
- [Using Cluster Autoscaler with Cluster Networks](./using-cluster-autoscaler-with-cluster-networks.md): Autoscale node pools backed by cluster networks.
- [Replacing the Boot Volume of Self-Managed Nodes](./replacing-the-boot-volume-of-self-managed-nodes.md): Replace the boot volume of self-managed nodes.

## Running GPU and RDMA workloads

- [Running PyTorch Jobs on OKE Using Host Network with RDMA](./running-pytorch-jobs-on-oke-using-hostnetwork-with-rdma.md): Run PyTorch distributed jobs over the host network with RDMA.
- [Using RDMA Network Locality When Running Workloads on OKE](./using-rdma-network-locality-when-running-workloads-on-oke.md): Schedule workloads using RDMA network topology and locality.
- [Using Dynamic Resource Allocation (DRA) for Multi-Node NVLink](./using-dynamic-resource-allocation-for-multi-node-nvlink-imex.md): Use DRA for multi-node NVLink (IMEX).

## NCCL and RCCL

- [Recommended NCCL/RCCL Parameters by Shape](./recommended-nccl-rccl-parameters-by-shape.md): Recommended NCCL/RCCL tuning parameters per GPU shape.
- [Using the NCCL/RCCL Parameters ConfigMap in Job Manifests](./using-nccl-rccl-parameters-configmap.md): Consume the auto-generated parameters ConfigMap from job manifests.
- [Running NCCL and RCCL Tests from Slurm Operator](./running-nccl-rccl-tests-from-slurm-operator.md): Run NCCL/RCCL bandwidth tests through the Slurm operator.

## Slurm

- [Slurm User Onboarding](./slurm-operator-user-onboarding.md): Onboard users to the Slurm operator.

## Health checks and benchmarks

- [Running Active Health Checks for GPU Nodes (Preview)](./running-active-health-checks.md): Run active health checks against GPU nodes.
- [Running GPU & RDMA Health Checks with Node Problem Detector](./running-gpu-rdma-healthchecks-with-node-problem-detector.md): Continuous GPU and RDMA health checks via Node Problem Detector.
- [Running ib_write_bw Tests Between Nodes](./running-ib-write-bw-test.md): Run ib_write_bw RDMA bandwidth tests between nodes.

## Monitoring

- [Manual Deployment: Prometheus & Grafana Stack](./deploying-monitoring-stack-manually.md): Manually deploy the Prometheus and Grafana monitoring stack with dashboards and alerts.

## Images and utilities

- [Importing Container Images from OCI File Storage Service Using Skopeo](./importing-images-from-fss-skopeo.md): Import container images from OCI File Storage using Skopeo.
- [oci-hpc-oke-utils](./oci-hpc-oke-utils.md): Helper utilities for oci-hpc-oke.

## Security advisories

- [CVE-2026-31431 ("Copy Fail")](./copy-fail.md): Linux kernel local privilege-escalation advisory and OKE image guidance.
- [Dirty Frag (CVE-2026-43284, CVE-2026-43500)](./dirty-frag.md): Linux kernel xfrm-ESP and RxRPC advisory and OKE image guidance.
