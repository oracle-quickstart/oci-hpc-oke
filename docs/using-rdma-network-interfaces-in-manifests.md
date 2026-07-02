# Using RDMA Network Interfaces in Manifests

## Using `hostNetwork`

To use the host's RDMA interfaces in your pods, include the following sections in your manifests:

```yaml
spec:
  hostNetwork: true
  dnsPolicy: ClusterFirstWithHostNet
  volumes:
  - { name: devinf, hostPath: { path: /dev/infiniband }}
  - { name: shm, emptyDir: { medium: Memory, sizeLimit: 32Gi }}
```

```yaml
    securityContext:
      privileged: true
      capabilities:
        add: [ "IPC_LOCK" ]
```

```yaml
    volumeMounts:
    - { mountPath: /dev/infiniband, name: devinf }
    - { mountPath: /dev/shm, name: shm }
```

For complete examples, see the NCCL and RCCL test manifests in [manifests/nccl-tests/kueue](../manifests/nccl-tests/kueue/) and [manifests/rccl-tests/kueue](../manifests/rccl-tests/kueue/).

Here's the worker template from the [BM.GPU.H100.8 NCCL test manifest](../manifests/nccl-tests/kueue/BM.GPU.H100.8.yaml):

```yaml
    Worker:
      replicas: 2
      template:
        metadata:
          labels:
            nccl-test-replica: mpi-worker
        spec:
          hostNetwork: true
          dnsPolicy: ClusterFirstWithHostNet
          nodeSelector:
            node.kubernetes.io/instance-type: BM.GPU.H100.8
          volumes:
          - { name: devinf, hostPath: { path: /dev/infiniband }}
          - { name: shm, emptyDir: { medium: Memory, sizeLimit: 32Gi }}
          containers:
          - name: mpi-worker
            ports:
            - { name: mpijob-port, containerPort: 2222, protocol: TCP }
            volumeMounts:
            - { mountPath: /dev/infiniband, name: devinf }
            - { mountPath: /dev/shm, name: shm }
            securityContext:
              privileged: true
              capabilities:
                add: ["IPC_LOCK"]
            image: iad.ocir.io/idxzjcdglx2s/nccl-tests:cuda-13.1.1-ubuntu-24.04-nccl-2.29.3-020926.1
            command:
              - /bin/bash
              - -c
              - mkdir -p /var/run/sshd; /usr/sbin/sshd -D -p 2222;
            resources:
              limits:
                nvidia.com/gpu: 8
```

## Using SR-IOV Virtual Functions

If the cluster is deployed with the NVIDIA Network Operator (`deploy_nvidia_network_operator = true` in the stack), the RDMA interfaces are also available as SR-IOV Virtual Functions (VFs). Each pod gets its own VF interfaces, so `hostNetwork: true` and `dnsPolicy: ClusterFirstWithHostNet` are not needed.

Instead of the `hostNetwork` settings above, include the following in your manifests:

- A `k8s.v1.cni.cncf.io/networks` annotation with one `rdma-vf` entry per requested VF
- An `nvidia.com/rdma-vf` resource limit set to the number of VFs you request
- The `/dev/infiniband` and `/dev/shm` mounts and the `IPC_LOCK` capability, the same as with `hostNetwork`

Nodes advertise one VF per RDMA physical function: 16 on dual-port shapes (BM.GPU4.8, BM.GPU.A100-v2.8, BM.GPU.B4.8, BM.GPU.H100.8, BM.GPU.B300.8) and 8 on single-port shapes (BM.GPU.B200.8, BM.GPU.H200.8, BM.GPU.MI300X.8, BM.GPU.MI355X-v1.8). Requesting more VFs than the node advertises leaves the pod unschedulable.

> [!NOTE]
> The `rdma-vf` network attachment is created in the `default` namespace. For pods in other namespaces, use `default/rdma-vf` in the annotation.

For complete examples, see the NCCL and RCCL test manifests using virtual functions in [manifests/nccl-tests/kueue/virtual-functions](../manifests/nccl-tests/kueue/virtual-functions/) and [manifests/rccl-tests/kueue/virtual-functions](../manifests/rccl-tests/kueue/virtual-functions/).

Here's the worker template from the [BM.GPU.H100.8 NCCL test manifest with virtual functions](../manifests/nccl-tests/kueue/virtual-functions/BM.GPU.H100.8.yaml), which requests 16 VFs:

```yaml
    Worker:
      replicas: 2
      template:
        metadata:
          labels:
            nccl-test-replica: mpi-worker
          annotations:
            k8s.v1.cni.cncf.io/networks: rdma-vf,rdma-vf,rdma-vf,rdma-vf,rdma-vf,rdma-vf,rdma-vf,rdma-vf,rdma-vf,rdma-vf,rdma-vf,rdma-vf,rdma-vf,rdma-vf,rdma-vf,rdma-vf
        spec:
          nodeSelector:
            node.kubernetes.io/instance-type: BM.GPU.H100.8
          volumes:
          - { name: devinf, hostPath: { path: /dev/infiniband }}
          - { name: shm, emptyDir: { medium: Memory, sizeLimit: 32Gi }}
          containers:
          - name: mpi-worker
            volumeMounts:
            - { mountPath: /dev/infiniband, name: devinf }
            - { mountPath: /dev/shm, name: shm }
            securityContext:
              privileged: true
              capabilities:
                add: ["IPC_LOCK"]
            image: iad.ocir.io/idxzjcdglx2s/nccl-tests:cuda-13.1.1-ubuntu-24.04-nccl-2.29.3-020926.1
            command:
              - /bin/bash
              - -c
              - mkdir -p /var/run/sshd; /usr/sbin/sshd -D;
            resources:
              limits:
                nvidia.com/gpu: 8
                nvidia.com/rdma-vf: 16
```
