
# Running RDMA GPU workloads on OKE with the GPU Operator

The deployment uses the [GPU Operator](https://github.com/NVIDIA/gpu-operator) for deploying the GPU driver and other components.

### What is NVIDIA GPU Operator?
Kubernetes provides access to special hardware resources such as NVIDIA GPUs, NICs, Infiniband adapters and other devices through the device plugin framework. However, configuring and managing nodes with these hardware resources requires configuration of multiple software components such as drivers, container runtimes or other libraries which are difficult and prone to errors. The NVIDIA GPU Operator uses the operator framework within Kubernetes to automate the management of all NVIDIA software components needed to provision GPU. These components include the NVIDIA drivers (to enable CUDA), Kubernetes device plugin for GPUs, the NVIDIA Container Runtime, automatic node labelling, DCGM based monitoring and others.

### What is NVIDIA Network Operator?
NVIDIA Network Operator leverages Kubernetes CRDs and Operator SDK to manage Networking related Components in order to enable Fast networking, RDMA and GPUDirect for workloads in a Kubernetes cluster.

The Goal of Network Operator is to manage all networking related components to enable execution of RDMA and GPUDirect RDMA workloads in a kubernetes cluster including:

- Mellanox Networking drivers to enable advanced features
- Kubernetes device plugins to provide hardware resources for fast network
- Kubernetes secondary network for Network intensive workloads

### Deploy the cluster using the Terraform template
You can find the template in the [terraform directory](../terraform/rdma/).

Make sure to update the image IDs in the `worker pools` blocks.

You can find more information on setting up Terraform for OCI [here](https://docs.oracle.com/en-us/iaas/developer-tutorials/tutorials/tf-provider/01-summary.htm).

The template will deploy a `bastion` instance and an `operator` instance. The `operator` instance will have access to the OKE cluster. You can connect to the `operator` instance via SSH with `ssh -J opc@<bastion IP> opc@<operator IP>`.

### Get the latest Helm 3 version
```sh
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

### Add Helm repos for Network Operator and GPU Operator
```sh
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### Deploy GPU Operator

You can change the `driver.version` in the Helm command below if you need to use a different version. Check [here](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html#gpu-operator-component-matrix) for supported versions.

```
helm install --wait \
  -n gpu-operator --create-namespace \
  gpu-operator nvidia/gpu-operator \
  --version v23.9.1 \
  --set operator.defaultRuntime=crio \
  --set driver.version=535.154.05
```

Wait until all network operator pods are running with `kubectl get pods -n gpu-operator`.

### Deploy Network Operator

```
helm install --wait \
  -n network-operator --create-namespace \
  network-operator nvidia/network-operator \
  --version v23.10.0 \
  --set deployCR=true \
  --set nfd.enabled=false \
  --set rdmaSharedDevicePlugin.deploy=false \
  --set nvPeerDriver.deploy=true \
  --set sriovDevicePlugin.deploy=true \
  --set secondaryNetwork.ipamPlugin.deploy=false \
  --set nvIpam.deploy=true \
  --set-json sriovDevicePlugin.resources='[{"name": "sriov_rdma_vf", "drivers": ["mlx5_core"], "devices": ["101a"], "isRdma": [true]}]'
```

Wait until all network operator pods are running with `kubectl get pods -n network-operator`.

### Deploy SR-IOV CNI
```
[kubectl apply -f https://raw.githubusercontent.com/openshift/sriov-cni/master/images/k8s-v1.16/sriov-cni-daemonset.yaml](https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/sriov-cni-daemonset.yaml)
```

### Deploy RDMA CNI
```
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/rdma-cni/master/deployment/rdma-cni-daemonset.yaml
```

### Deploy VF Configuration daemonset
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/vf-config.yaml
```

### Confirm that the GPUs are VFs are correctly exposed
```
kubectl get nodes -l 'node.kubernetes.io/instance-type in (BM.GPU.H100.8, BM.GPU.A100-v2.8, BM.GPU4.8, BM.GPU.B4.8)' --sort-by=.status.capacity."nvidia\.com/sriov_rdma_vf" -o=custom-columns='NODE:metadata.name,GPUs:status.allocatable.nvidia\.com/gpu,RDMA-VFs:status.allocatable.nvidia\.com/sriov_rdma_vf'

NODE            GPUs   RDMA-VFs
10.79.148.115   8      16
10.79.151.167   8      16
10.79.156.205   8      16
```

### Create Network Attachment Definition

```sh
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/network-attachment-definition.yaml
```

### Create the IP Pool for Nvidia IPAM
```
kubectl apply -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/ubuntu/manifests/ip-pool.yaml
```

### Deploy Volcano
```
helm repo add volcano-sh https://volcano-sh.github.io/helm-charts
helm install volcano volcano-sh/volcano -n volcano-system --create-namespace
```
### Create the service accounts for Volcano
```
kubectl create serviceaccount -n default mpi-worker-view
kubectl create rolebinding default-view --namespace default --serviceaccount default:mpi-worker-view --clusterrole view
```

### Run the NCCL test
```
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: nccl-allreduce-job0
spec:
  minAvailable: 1
  schedulerName: volcano
  plugins:
    ssh: []
    svc: []
  queue: default
  tasks:
    - replicas: 1
      name: mpimaster
      policies:
        - event: TaskCompleted
          action: CompleteJob
      template:
        spec:
          volumes:
            - name: topo
              configMap:
                name: topology-h100
                items:
                - key: topo.xml
                  path: topo.xml
            - name: root
              hostPath:
                path: /
                type: Directory
          initContainers:
            - command:
                - /bin/bash
                - -c
                - |
                  until [[ "$(kubectl get pod -l volcano.sh/job-name=nccl-allreduce-job0,volcano.sh/task-spec=mpiworker -o json | jq '.items | length')" != 0 ]]; do
                    echo "Waiting for MPI worker pods..."
                    sleep 3
                  done
                  echo "Waiting for MPI worker pods to be ready..."
                  kubectl wait pod -l volcano.sh/job-name=nccl-allreduce-job0,volcano.sh/task-spec=mpiworker --for=condition=Ready --timeout=600s && sleep 2
              image: aga.ocir.io/hpc_limited_availability/oke/kubectl:latest
              name: wait-for-workers
          serviceAccount: mpi-worker-view
          terminationGracePeriodSeconds: 2
          tolerations:
            - key: nvidia.com/gpu
              operator: Exists
          containers:
            - command:
                - /bin/bash
                - -c
                - |
                  MPI_HOST=$(cat /etc/volcano/mpiworker.host | tr "\n" ",")
                  mkdir -p /var/run/sshd; /usr/sbin/sshd
                  mpirun --allow-run-as-root \
                    -mca coll ^hcoll \
                    -np 24 -npernode 8 --bind-to numa --map-by ppr:8:node \
                    -hostfile /etc/volcano/mpiworker.host \
                    -x NCCL_CROSS_NIC=0 \
                    -x NCCL_SOCKET_NTHREADS=16 \
                    -x NCCL_DEBUG=WARN \
                    -x NCCL_CUMEM_ENABLE=0 \
                    -x NCCL_IB_SPLIT_DATA_ON_QPS=0 \
                    -x NCCL_IB_QPS_PER_CONNECTION=16 \
                    -x NCCL_IB_GID_INDEX=3 \
                    -x NCCL_IB_TC=41 \
                    -x NCCL_IB_SL=0 \
                    -x NCCL_IB_TIMEOUT=22 \
                    -x NCCL_NET_PLUGIN=none \
                    -x HCOLL_ENABLE_MCAST_ALL=0 \
                    -x coll_hcoll_enable=0 \
                    -x UCX_TLS=tcp \
                    -x UCX_NET_DEVICES=eth0 \
                    -x RX_QUEUE_LEN=8192 \
                    -x IB_RX_QUEUE_LEN=8192 \
                    -x NCCL_SOCKET_IFNAME=eth0 \
                    -x NCCL_ALGO=auto \
                    -x NCCL_IGNORE_CPU_AFFINITY=1 \
                    -x NCCL_TOPO_FILE=/h100/topo.xml \
                    -mca coll_hcoll_enable 0 \
                    /workspace/nccl-tests/build/all_reduce_perf -b 8 -f 2 -g 1 -e 8G -c 1; sleep 3600
              image: iad.ocir.io/hpc_limited_availability/nccl-tests:pytorch-23.10-nccl-2.19.3-1
              volumeMounts:
              - { mountPath: /h100, name: topo }
              - { mountPath: /host, name: root }
              securityContext:
                capabilities:
                  add: ["IPC_LOCK"]
              name: mpimaster
              ports:
                - containerPort: 22
                  name: mpijob-port
              workingDir: /workspace
              resources:
                requests:
                  cpu: 1
          restartPolicy: OnFailure
    - replicas: 3
      minAvailable: 3
      name: mpiworker
      template:
        metadata:
          annotations:
            k8s.v1.cni.cncf.io/networks: oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov,oci-rdma-sriov
        spec:
          containers:
            - name: mpiworker
              command:
                - /bin/bash
                - -c
                - mkdir -p /var/run/sshd; /usr/sbin/sshd -D;
              image: iad.ocir.io/hpc_limited_availability/nccl-tests:pytorch-23.10-nccl-2.19.3-1
              securityContext:
                capabilities:
                  add: ["IPC_LOCK"]
              ports:
                - containerPort: 22
                  name: mpijob-port
              workingDir: /workspace
              resources:
                requests:
                  nvidia.com/gpu: 8
                  nvidia.com/sriov_rdma_vf: 16
                  ephemeral-storage: 1Gi
                limits:
                  nvidia.com/gpu: 8
                  nvidia.com/sriov_rdma_vf: 16
                  ephemeral-storage: 1Gi
              volumeMounts:
              - { mountPath: /h100, name: topo }
              - mountPath: /dev/shm
                name: shm
          restartPolicy: OnFailure
          terminationGracePeriodSeconds: 15
          tolerations:
            - key: nvidia.com/gpu
              operator: Exists
          volumes:
          - name: topo
            configMap:
              name: topology-h100
              items:
              - key: topo.xml
                path: topo.xml
          - name: root
            hostPath:
              path: /
              type: Directory
          - name: shm
            emptyDir:
              medium: Memory
              sizeLimit: 8Gi
```
