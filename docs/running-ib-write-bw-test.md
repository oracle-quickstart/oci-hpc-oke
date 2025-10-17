# Running ib_write_bw Tests Between Nodes

This guide demonstrates how to test RDMA connectivity between two OKE nodes using `ib_write_bw`, a bandwidth test tool from the Mellanox OFED `perftest` package. This test validates RDMA performance and connectivity using RDMA Connection Manager (RDMA CM).

## Overview

The `ib_write_bw` tool measures RDMA write bandwidth between two nodes. Running this test helps verify:
- RDMA connectivity is properly configured
- Network performance meets expectations
- InfiniBand/RoCE adapters are functioning correctly
- No network bottlenecks are present

## Prerequisites

- OKE cluster with RDMA-enabled nodes in a Cluster Network
- kubectl configured with cluster access
- At least two available worker nodes with RDMA capability
- Nodes must be in the same Cluster Network

## Procedure

### Step 1: Deploy RDMA Test Pods

Apply the following manifest to deploy two test pods (`rdma-test-pod-1` and `rdma-test-pod-2`):

> [!IMPORTANT]  
> This manifest assumes all RDMA-enabled nodes are in the same Cluster Network. If you have multiple Cluster Networks, adjust the `nodeSelectorTerms` accordingly.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rdma-test-pod-1
  labels:
    app: rdma-test-pods
spec:
  hostNetwork: true
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node.kubernetes.io/instance-type
            operator: In
            values:
            - BM.GPU.A100-v2.8
            - BM.GPU.B4.8
            - BM.GPU4.8
            - BM.GPU.H100.8
            - BM.Optimized3.36
            - BM.HPC.E5.144
            - BM.HPC2.36
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app: rdma-test-pods
  dnsPolicy: ClusterFirstWithHostNet
  volumes:
  - { name: devinf, hostPath: { path: /dev/infiniband }}
  - { name: shm, emptyDir: { medium: Memory, sizeLimit: 32Gi }}
  restartPolicy: OnFailure
  containers:
  - image: oguzpastirmaci/mofed-perftest:5.4-3.6.8.1-ubuntu20.04-amd64
    name: mofed-test-ctr
    securityContext:
      privileged: true
      capabilities:
        add: [ "IPC_LOCK" ]
    volumeMounts:
    - { mountPath: /dev/infiniband, name: devinf }
    - { mountPath: /dev/shm, name: shm }
    resources:
      requests:
        cpu: 8
        ephemeral-storage: 32Gi
        memory: 2Gi
    command:
    - sh
    - -c
    - |
      ls -l /dev/infiniband /sys/class/net
      sleep 1000000
---
apiVersion: v1
kind: Pod
metadata:
  name: rdma-test-pod-2
  labels:
    app: rdma-test-pods
spec:
  hostNetwork: true
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists  
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node.kubernetes.io/instance-type
            operator: In
            values:
            - BM.GPU.A100-v2.8
            - BM.GPU.B4.8
            - BM.GPU4.8
            - BM.GPU.H100.8
            - BM.Optimized3.36
            - BM.HPC.E5.144
            - BM.HPC2.36
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app: rdma-test-pods
  dnsPolicy: ClusterFirstWithHostNet
  volumes:
  - { name: devinf, hostPath: { path: /dev/infiniband }}
  - { name: shm, emptyDir: { medium: Memory, sizeLimit: 32Gi }}
  restartPolicy: OnFailure
  containers:
  - image: oguzpastirmaci/mofed-perftest:5.4-3.6.8.1-ubuntu20.04-amd64
    name: mofed-test-ctr
    securityContext:
      privileged: true
      capabilities:
        add: [ "IPC_LOCK" ]
    volumeMounts:
    - { mountPath: /dev/infiniband, name: devinf }
    - { mountPath: /dev/shm, name: shm }
    resources:
      requests:
        cpu: 8
        ephemeral-storage: 32Gi
        memory: 2Gi
    command:
    - sh
    - -c
    - |
      ls -l /dev/infiniband /sys/class/net
      sleep 1000000
```

Save the manifest to a file (e.g., `rdma-test-pods.yaml`) and apply it:

```bash
kubectl apply -f rdma-test-pods.yaml
```

### Step 2: Verify Pod Deployment

Check that both pods are running on different nodes:

```bash
kubectl get pods -o wide
```

**Example output:**

```
NAME              READY   STATUS    RESTARTS   AGE   NODE
rdma-test-pod-1   1/1     Running   0          2m    10.0.1.10
rdma-test-pod-2   1/1     Running   0          2m    10.0.1.20
```

Ensure the pods are scheduled on different nodes. The `topologySpreadConstraints` in the manifest ensures this distribution.

### Step 3: Run the Bandwidth Test

You will need two terminal windows to run the test - one for the server (rdma-test-pod-1) and one for the client (rdma-test-pod-2).

#### Server Side (rdma-test-pod-1)

Open the first terminal and execute into the server pod:

```bash
kubectl exec -it rdma-test-pod-1 -- bash
```

Run the following commands to start the `ib_write_bw` server and display the RDMA interface IP:

```bash
MLX_DEVICE_NAME=$(ibdev2netdev | grep rdma0 | awk '{print $1}')
RDMA0_IP=$(ip -f inet addr show rdma0 | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')

echo -e "\nThe IP of RDMA0 is to use in rdma-test-pod-2 is: $RDMA0_IP\n"

ib_write_bw -F -x 3 --report_gbits -R -T 41 -q 4 -d $MLX_DEVICE_NAME
```

**Example output:**

```
The IP of RDMA0 to use in rdma-test-pod-2 is: 10.224.5.57

************************************
* Waiting for client to connect... *
************************************
```

Note the IP address displayed (e.g., `10.224.5.57`). You will need this for the client connection.

The server is now waiting for a client connection. Keep this terminal open.

#### Client Side (rdma-test-pod-2)

Open a second terminal and execute into the client pod:

```bash
kubectl exec -it rdma-test-pod-2 -- bash
```

Run the following commands to start the bandwidth test. Replace `<SERVER_IP>` with the IP address from the server output:

```bash
RDMA0_IP_OF_POD1=<ENTER THE IP FROM THE PREVIOUS STEP>

MLX_DEVICE_NAME=$(ibdev2netdev | grep rdma0 | awk '{print $1}')

ib_write_bw -F -x 3 --report_gbits -R -T 41 -q 4 -d $MLX_DEVICE_NAME $RDMA0_IP_OF_POD1
```

For example, if the server IP is `10.224.5.57`:

```bash
RDMA0_IP_OF_POD1=10.224.5.57
MLX_DEVICE_NAME=$(ibdev2netdev | grep rdma0 | awk '{print $1}')
ib_write_bw -F -x 3 --report_gbits -R -T 41 -q 4 -d $MLX_DEVICE_NAME $RDMA0_IP_OF_POD1
```

### Step 4: Review Test Results

The test will run and display bandwidth results. **Example output:**

```
---------------------------------------------------------------------------------------
                    RDMA_Write BW Test
 Dual-port       : OFF		Device         : mlx5_5
 Number of qps   : 4		Transport type : IB
 Connection type : RC		Using SRQ      : OFF
 TX depth        : 128
 CQ Moderation   : 100
 Mtu             : 4096[B]
 Link type       : Ethernet
 GID index       : 3
 Max inline data : 0[B]
 rdma_cm QPs	 : ON
 Data ex. method : rdma_cm 	TOS    : 41
---------------------------------------------------------------------------------------
 local address: LID 0000 QPN 0x0093 PSN 0xbf9bfe
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:224:04:233
 local address: LID 0000 QPN 0x0094 PSN 0xab0910
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:224:04:233
 local address: LID 0000 QPN 0x0095 PSN 0x28bd1a
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:224:04:233
 local address: LID 0000 QPN 0x0096 PSN 0x5c7f61
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:224:04:233
 remote address: LID 0000 QPN 0x0093 PSN 0x62655e
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:224:05:57
 remote address: LID 0000 QPN 0x0094 PSN 0x6706f0
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:224:05:57
 remote address: LID 0000 QPN 0x0095 PSN 0xcb157a
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:224:05:57
 remote address: LID 0000 QPN 0x0096 PSN 0x626041
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:224:05:57
---------------------------------------------------------------------------------------
 #bytes     #iterations    BW peak[Gb/sec]    BW average[Gb/sec]   MsgRate[Mpps]
 65536      20000            98.01              98.01  		   0.186932
---------------------------------------------------------------------------------------
```
