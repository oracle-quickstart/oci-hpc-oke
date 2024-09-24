## Running `ib_write_bw` test using RDMA CM between two nodes in OKE
### 1 - Deploy the RDMA test pods
Apply the following manifest to deploy 2 test pods (`rdma-test-pod-1` & `rdma-test-pod-2`).

> [!IMPORTANT]  
> Below manifest assumes you have all your RDMA enabled nodes in the same cluster network. If you have multiple cluster networks, choose the correct `nodeSelectorTerms` accordingly.

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

```
kubectl get pods

NAME              READY   STATUS    RESTARTS   AGE
rdma-test-pod-1   1/1     Running   0          64m
rdma-test-pod-2   1/1     Running   0          64m
```

### 2 - Exec into the test pods in separate terminals
Exec into the test pods, and run the following commands to run a test with `ib_write_bw` using RDMA CM.

#### rdma-test-pod-1 
You will use this pod as the server for `ib_write_bw`.

Run the following commands. It will show the IP that you will use in the next other pod and start the `ib_write_bw` server.

```
MLX_DEVICE_NAME=$(ibdev2netdev | grep rdma0 | awk '{print $1}')
RDMA0_IP=$(ip -f inet addr show rdma0 | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')

echo -e "\nThe IP of RDMA0 is to use in rdma-test-pod-2 is: $RDMA0_IP\n"

ib_write_bw -F -x 3 --report_gbits -R -T 41 -q 4 -d $MLX_DEVICE_NAME
```
 
Example output:
```
The IP of RDMA0 is to use in rdma-test-pod-2 is: 10.224.5.57

$ ib_write_bw -F -x 3 --report_gbits -R -T 41 -q 4 -d $MLX_DEVICE_NAME

************************************
* Waiting for client to connect... *
************************************
```

#### rdma-test-pod-2
You will use this pod as the client for `ib_write_bw`.

Run the following commands to start the test. Make sure you change the first command with the IP you have from the above step.

```
RDMA0_IP_OF_POD1=<ENTER THE IP FROM THE PREVIOUS STEP>

MLX_DEVICE_NAME=$(ibdev2netdev | grep rdma0 | awk '{print $1}')

ib_write_bw -F -x 3 --report_gbits -R -T 41 -q 4 -d $MLX_DEVICE_NAME $RDMA0_IP_OF_POD1
```

Example output:
```
$ RDMA0_IP_OF_POD1=10.224.5.57
$ MLX_DEVICE_NAME=$(ibdev2netdev | grep rdma0 | awk '{print $1}')

$ ib_write_bw -F -x 3 --report_gbits -R -T 41 -q 4 -d $MLX_DEVICE_NAME $RDMA0_IP_OF_POD1
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
