# Running GPU workloads on Oracle Cloud Infrastructure Container Engine for Kubernetes (OKE)

Oracle Cloud Infrastructure Container Engine for Kubernetes (OKE) is a fully-managed, scalable, and highly available service that you can use to deploy your containerized applications to the cloud.

Please visit OKE documentation page for more information: https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengoverview.htm

This repository will focus on two workload types using GPUs: RDMA workloads using OCI's high performance network with support for RDMA (e.g. training jobs) and non-RDMA workloads that don't need to use the RDMA network (e.g. inference jobs).

### Running RDMA workloads on OKE
[Using Nvidia A100 shapes](./docs/running-rdma-workloads-on-oke-a100.md)
[Using Nvidia H100 shapes](./docs/running-rdma-workloads-on-oke-h100.md)