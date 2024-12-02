Running PyTorch jobs on OKE using host network with RDMA
=========

To enable RDMA with OKE, we use the host network to attach the RDMA interfaces on the node to the pod (`hostNetwork: true` and `dnsPolicy: ClusterFirstWithHostNet`). This means the pod will have the hostname of the node it's running on. Because Pytorch relies on using hostnames to discover workers, there are some additional information we need to use in the manifests.

In this guide, we will use [yolov5](https://github.com/ultralytics/yolov5) as the example workload.

> [!IMPORTANT]
> To use the RDMA interfaces on the host in your pods, you should have the below sections in your manifests. The example manifests below will have these sections.

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

Table of Contents
=================

   * [Volcano](#volcano)
      * [Using c10d as the backend](#using-c10d-as-the-backend)
      * [Using etcd as the backend](#using-etcd-as-the-backend)
   * [Training Operator](#training-operator)
      * [Using c10d as the backend](#using-c10d-as-the-backend-1)
      * [Using etcd as the backend](#using-etcd-as-the-backend-1)

## Volcano
With Volcano, we recommend not using the [Pytorch plugin](https://github.com/volcano-sh/volcano/blob/master/docs/user-guide/how_to_use_pytorch_plugin.md) because it's based on the old master/worker design instead of Torch Elastic.

### Using `c10d` as the backend

1. Install Volcano.

```sh
helm repo add volcano-sh https://volcano-sh.github.io/helm-charts
helm install volcano volcano-sh/volcano -n volcano-system --create-namespace
```

2. Add an environment varible for the job ID to your PyTorch job manifest.

```yaml
- name: JOB_ID
  valueFrom:
    fieldRef:
      fieldPath: metadata.annotations['scheduling.k8s.io/group-name']  
```                

3. Add the following to your `torchrun` command:

```sh
--rdzv-id=$JOB_ID
--rdzv-endpoint=$(IFS=',' read -ra workers <<< "$VC_WORKER_HOSTS"; echo "${workers[0]}"):23456
--rdzv-conf=is_host=$(if [ $VC_TASK_INDEX == 0 ]; then echo "true"; else echo "false"; fi)
--local_addr=$(IFS=',' read -ra workers <<< "$VC_WORKER_HOSTS"; echo "${workers[VC_TASK_INDEX]}")
--nnodes=$VC_WORKER_NUM
```            

Explanation of the above parameters:

| Parameter        | Explanation                                                                                                                                                                                               |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| \--rdzv-id       | Use the JOB_ID env var as the unique ID for Rendezvous.                                                                                                                                                   |
| \--rdzv-endpoint | Volcano adds the `VC_WORKER_HOSTS` variable, which has the comma separated list of all hosts in the job. We are using the first node in the list as the Rendezvous endpoint.                              |
| \--rdzv-conf     | Volcano adds the `VC_TASK_INDEX` variable, which is the sequence number of a job container for multi-node training. The value of the first pod is 0. We tell `torchrun` to use the first pod as the host. |
| \--local_addr    | Volcano adds the `VC_WORKER_HOSTS` and `VC_TASK_INDEX` variables. We tell `torchrun` to use the pod's FQDN as the local address.                                                                          |
| \--nnodes        | Volcano adds the `VC_WORKER_NUM`, which is the number of workers in the job.                                                                                                                              |


4. Here's an example with `yolov5` and Volcano. Note that the NCCL environment variables are for the `BM.GPU.B4.8` A100 shape. Change them depending on the shape you have.

```yaml
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  annotations:
  name: yolov5-job
spec:
  minAvailable: 0
  plugins:
    env: []
    svc: ["--publish-not-ready-addresses=true"]
  queue: default
  schedulerName: volcano
  tasks:
  - name: worker
    replicas: 2
    template:
      metadata:
      spec:
        containers:
        - command:
          - /bin/bash
          - -c
          - |
            torchrun \
            --rdzv-id=$JOB_ID \
            --rdzv-backend=c10d \
            --rdzv-endpoint=$(IFS=',' read -ra workers <<< "$VC_WORKER_HOSTS"; echo "${workers[0]}"):23456 \
            --rdzv-conf=is_host=$(if [ $VC_TASK_INDEX == 0 ]; then echo "true"; else echo "false"; fi) \
            --local_addr=$(IFS=',' read -ra workers <<< "$VC_WORKER_HOSTS"; echo "${workers[VC_TASK_INDEX]}") \
            --nproc_per_node=1 \
            --nnodes=$VC_WORKER_NUM \
            /usr/src/app/train.py \
            --batch-size=32 \
            --epochs=100 \
            --data=coco128.yaml \
            --weights=datasets/weights/yolov5s.pt  
          image: ultralytics/yolov5:latest
          name: worker
          ports:
          - containerPort: 23456
            name: c10d
            protocol: TCP
          env:
          - name: LOGLEVEL
            value: DEBUG
          - name: NCCL_DEBUG
            value: INFO
          - name: NCCL_IB_SPLIT_DATA_ON_QPS
            value: "0"
          - name: NCCL_IB_QPS_PER_CONNECTION
            value: "4"
          - name: NCCL_IB_GID_INDEX
            value: "3"
          - name: NCCL_IB_HCA
            value: "=mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_14,mlx5_15,mlx5_16,mlx5_17,mlx5_9,mlx5_10,mlx5_11,mlx5_12"
          - name: NCCL_IB_TC
            value: "41"
          - name: NCCL_IB_SL
            value: "0"
          - name: NCCL_IB_TIMEOUT
            value: "22"
          - name: JOB_ID
            valueFrom:
              fieldRef:
                fieldPath: metadata.annotations['scheduling.k8s.io/group-name']       
          resources:
            limits:
              ephemeral-storage: 32Gi
              nvidia.com/gpu: 1
            requests:
              cpu: 64
              ephemeral-storage: 32Gi
              memory: 512Gi
              nvidia.com/gpu: 1
          securityContext:
            privileged: true
            capabilities:
              add:
              - IPC_LOCK
              - CAP_SYS_ADMIN
          volumeMounts:
          - { mountPath: /dev/infiniband, name: devinf }
          - { mountPath: /dev/shm, name: shm }
          workingDir: /workspace
        dnsPolicy: ClusterFirstWithHostNet
        hostNetwork: true
        restartPolicy: OnFailure
        terminationGracePeriodSeconds: 15
        tolerations:
        - { operator: Exists }
        volumes:
        - { name: devinf, hostPath: { path: /dev/infiniband }}
        - { name: shm, emptyDir: { medium: Memory, sizeLimit: 32Gi }}
```

### Using `etcd` as the backend

1. Install Volcano.

```sh
helm repo add volcano-sh https://volcano-sh.github.io/helm-charts
helm install volcano volcano-sh/volcano -n volcano-system --create-namespace
```

2. Create an `etcd` pod and related services.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: etcd-client
spec:
  ports:
    - name: etcd-client-port
      port: 2379
      protocol: TCP
      targetPort: 2379
  selector:
    app: etcd

---
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: etcd
    etcd_node: etcd-server
  name: etcd-server
spec:
  containers:
    - command:
        - /usr/local/bin/etcd
        - --data-dir
        - /var/lib/etcd
        - --enable-v2
        - --name
        - etcd-server
        - --initial-advertise-peer-urls
        - http://etcd-server:2380
        - --listen-peer-urls
        - http://0.0.0.0:2380
        - --listen-client-urls
        - http://0.0.0.0:2379
        - --advertise-client-urls
        - http://etcd-server:2379
        - --initial-cluster
        - etcd-server=http://etcd-server:2380
        - --initial-cluster-state
        - new
      image: quay.io/coreos/etcd:latest
      name: etcd-server
      ports:
        - containerPort: 2379
          name: client
          protocol: TCP
        - containerPort: 2380
          name: server
          protocol: TCP
  restartPolicy: Always

---
apiVersion: v1
kind: Service
metadata:
  labels:
    etcd_node: etcd-server
  name: etcd-server
spec:
  ports:
    - name: client
      port: 2379
      protocol: TCP
      targetPort: 2379
    - name: server
      port: 2380
      protocol: TCP
      targetPort: 2380
  selector:
    etcd_node: etcd-server
---
apiVersion: v1
kind: Service
metadata:
  labels:
    etcd_node: etcd-server-headless
  name: etcd-server-headless
spec:
  clusterIP: None
  ports:
    - name: client
      port: 2379
      protocol: TCP
      targetPort: 2379
    - name: server
      port: 2380
      protocol: TCP
      targetPort: 2380
  selector:
    etcd_node: etcd-server
```

3. Add an environment varible for the job ID to your PyTorch job manifest.

```yaml
- name: JOB_ID
  valueFrom:
    fieldRef:
      fieldPath: metadata.annotations['scheduling.k8s.io/group-name']  
```      

4. Add the following to your `torchrun` command:
```sh
--rdzv-id=$JOB_ID
--rdzv-backend=etcd-v2
--rdzv-endpoint=etcd-server-headless:2379
--local_addr=$(IFS=',' read -ra workers <<< "$VC_WORKER_HOSTS"; echo "${workers[VC_TASK_INDEX]}")
--nnodes=$VC_WORKER_NUM
```

Explanation of the above parameters:

| Parameter        | Explanation                                                                                                                      |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| \--rdzv-id       | Use the JOB_ID env var as the unique ID for Rendezvous.                                                                          |
| \--rdzv-backend  | Use `etcd-v2` instead of `c10d` as the backend.                                                                                  |
| \--rdzv-endpoint | Use the headless service of etcd as the Rendezvous endpoint.                                                                     |
| \--local_addr    | Volcano adds the `VC_WORKER_HOSTS` and `VC_TASK_INDEX` variables. We tell `torchrun` to use the pod's FQDN as the local address. |
| \--nnodes        | Volcano adds the `VC_WORKER_NUM`, which is the number of workers in the job.                                                     |

5. Here's an example with `yolov5` and Volcano. Note that the NCCL environment variables are for the `BM.GPU.B4.8` A100 shape. Change them depending on the shape you have.

```yaml
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  annotations:
  name: yolov5-job
spec:
  minAvailable: 0
  plugins:
    env: []
    svc: ["--publish-not-ready-addresses=true"]
  queue: default
  schedulerName: volcano
  tasks:
  - name: worker
    replicas: 2
    template:
      metadata:
      spec:
        containers:
        - command:
          - /bin/bash
          - -c
          - |
            torchrun \
            --rdzv-id=$JOB_ID \
            --rdzv-backend=etcd-v2 \
            --rdzv-endpoint=etcd-server-headless:2379 \
            --local_addr=$(IFS=',' read -ra workers <<< "$VC_WORKER_HOSTS"; echo "${workers[VC_TASK_INDEX]}") \
            --nproc_per_node=1 \
            --nnodes=$VC_WORKER_NUM \
            /usr/src/app/train.py \
            --batch-size=32 \
            --epochs=100 \
            --data=coco128.yaml \
            --weights=datasets/weights/yolov5s.pt        
          image: ultralytics/yolov5:latest
          name: worker
          ports:
          - containerPort: 2379
            name: etcd
            protocol: TCP
          env:
          - name: LOGLEVEL
            value: DEBUG
          - name: NCCL_DEBUG
            value: INFO
          - name: NCCL_IB_SPLIT_DATA_ON_QPS
            value: "0"
          - name: NCCL_IB_QPS_PER_CONNECTION
            value: "4"
          - name: NCCL_IB_GID_INDEX
            value: "3"
          - name: NCCL_IB_HCA
            value: "=mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_14,mlx5_15,mlx5_16,mlx5_17,mlx5_9,mlx5_10,mlx5_11,mlx5_12"
          - name: NCCL_IB_TC
            value: "41"
          - name: NCCL_IB_SL
            value: "0"
          - name: NCCL_IB_TIMEOUT
            value: "22"
          - name: JOB_ID
            valueFrom:
              fieldRef:
                fieldPath: metadata.annotations['scheduling.k8s.io/group-name']       
          resources:
            limits:
              ephemeral-storage: 32Gi
              nvidia.com/gpu: 1
            requests:
              cpu: 64
              ephemeral-storage: 32Gi
              memory: 512Gi
              nvidia.com/gpu: 1
          securityContext:
            privileged: true
            capabilities:
              add:
              - IPC_LOCK
              - CAP_SYS_ADMIN
          volumeMounts:
          - { mountPath: /dev/infiniband, name: devinf }
          - { mountPath: /dev/shm, name: shm }
          workingDir: /workspace
        dnsPolicy: ClusterFirstWithHostNet
        hostNetwork: true
        restartPolicy: OnFailure
        terminationGracePeriodSeconds: 15
        tolerations:
        - { operator: Exists }
        volumes:
        - { name: devinf, hostPath: { path: /dev/infiniband }}
        - { name: shm, emptyDir: { medium: Memory, sizeLimit: 32Gi }}
```        

## Training Operator

### Using `c10d` as the backend

1. Install the Training Operator.
```sh
kubectl apply -k "github.com/kubeflow/training-operator.git/manifests/overlays/standalone?ref=v1.8.1"
```

2. Add environment varibles for the pod name and the replica index to your PyTorch job manifest.

```yaml
- name: REPLICA_INDEX
  valueFrom:
    fieldRef:
      fieldPath: metadata.labels['training.kubeflow.org/replica-index']
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
```                    

3. Add the following to your `torchrun` command.

```sh
PET_RDZV_CONF=is_host=$(if [ $REPLICA_INDEX == 0 ]; then echo "true"; else echo "false"; fi)
--rdzv-conf=$PET_RDZV_CONF
--local_addr=$POD_NAME
```

Explanation of the above parameters:

| Parameter     | Explanation                                                                                                                                                                                           |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| \--rdzv-conf  | We added the `REPLICA_INDEX` variable, which is the sequence number of a job container for multi-node training. The value of the first pod is 0. We tell `torchrun` to use the first pod as the host. |
| \--local_addr | We added the `POD_NAME` variable, and we tell `torchrun` to use it as the local address of the pod.                                                                                                   |

4. Here's an example with `yolov5` and Training Operator. Note that the NCCL environment variables are for the `BM.GPU.B4.8` A100 shape. Change them depending on the shape you have.

```yaml
apiVersion: "kubeflow.org/v1"
kind: PyTorchJob
metadata:
  name: yolov5-training
spec:
  elasticPolicy:
    rdzvBackend: c10d
    minReplicas: 1
    maxReplicas: 8
    maxRestarts: 100
  pytorchReplicaSpecs:
    Worker:
      replicas: 2
      restartPolicy: OnFailure
      template:
        spec:
          hostNetwork: true
          hostIPC: true
          dnsPolicy: ClusterFirstWithHostNet
          containers:
            - name: pytorch
              image: ultralytics/yolov5:latest
              imagePullPolicy: Always
              env:
              - name: LOGLEVEL
                value: DEBUG
              - name: NCCL_DEBUG
                value: INFO
              - name: NCCL_IB_SPLIT_DATA_ON_QPS
                value: "0"
              - name: NCCL_IB_QPS_PER_CONNECTION
                value: "4"
              - name: NCCL_IB_GID_INDEX
                value: "3"
              - name: NCCL_IB_HCA
                value: "=mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_14,mlx5_15,mlx5_16,mlx5_17,mlx5_9,mlx5_10,mlx5_11,mlx5_12"
              - name: NCCL_IB_TC
                value: "41"
              - name: NCCL_IB_SL
                value: "0"
              - name: NCCL_IB_TIMEOUT
                value: "22"
              - name: REPLICA_INDEX
                valueFrom:
                  fieldRef:
                    fieldPath: metadata.labels['training.kubeflow.org/replica-index']
              - name: POD_NAME
                valueFrom:
                  fieldRef:
                    fieldPath: metadata.name
              command: ["/bin/bash"]
              args:
                - "-c"
                - |
                  export PET_RDZV_CONF=is_host=$(if [ $REPLICA_INDEX == 0 ]; then echo "true"; else echo "false"; fi)
                  torchrun \
                  --local_addr=$POD_NAME \
                  --nproc_per_node=1 \
                  --rdzv-conf=$PET_RDZV_CONF \
                  train.py \
                  --batch-size=32 \
                  --epochs=100 \
                  --data=coco128.yaml \
                  --weights=datasets/weights/yolov5s.pt
              resources:
               requests:
                  nvidia.com/gpu: 1
               limits:
                  nvidia.com/gpu: 1
              volumeMounts:
                - mountPath: /dev/shm
                  name: dshm
                - mountPath: /dev/infiniband
                  name: devinf
              securityContext:
                  privileged: true
                  capabilities:
                    add:
                    - IPC_LOCK
                    - CAP_SYS_ADMIN
          volumes:
          - emptyDir:
              medium: Memory
            name: dshm
          - name: devinf
            hostPath:
              path: /dev/infiniband
```

### Using `etcd` as the backend

1. Install the Training Operator
```sh
kubectl apply -k "github.com/kubeflow/training-operator.git/manifests/overlays/standalone?ref=v1.8.1"
```

2. Create an `etcd` pod and related services.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: etcd-client
spec:
  ports:
    - name: etcd-client-port
      port: 2379
      protocol: TCP
      targetPort: 2379
  selector:
    app: etcd

---
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: etcd
    etcd_node: etcd-server
  name: etcd-server
spec:
  containers:
    - command:
        - /usr/local/bin/etcd
        - --data-dir
        - /var/lib/etcd
        - --enable-v2
        - --name
        - etcd-server
        - --initial-advertise-peer-urls
        - http://etcd-server:2380
        - --listen-peer-urls
        - http://0.0.0.0:2380
        - --listen-client-urls
        - http://0.0.0.0:2379
        - --advertise-client-urls
        - http://etcd-server:2379
        - --initial-cluster
        - etcd-server=http://etcd-server:2380
        - --initial-cluster-state
        - new
      image: quay.io/coreos/etcd:latest
      name: etcd-server
      ports:
        - containerPort: 2379
          name: client
          protocol: TCP
        - containerPort: 2380
          name: server
          protocol: TCP
  restartPolicy: Always

---
apiVersion: v1
kind: Service
metadata:
  labels:
    etcd_node: etcd-server
  name: etcd-server
spec:
  ports:
    - name: client
      port: 2379
      protocol: TCP
      targetPort: 2379
    - name: server
      port: 2380
      protocol: TCP
      targetPort: 2380
  selector:
    etcd_node: etcd-server
---
apiVersion: v1
kind: Service
metadata:
  labels:
    etcd_node: etcd-server-headless
  name: etcd-server-headless
spec:
  clusterIP: None
  ports:
    - name: client
      port: 2379
      protocol: TCP
      targetPort: 2379
    - name: server
      port: 2380
      protocol: TCP
      targetPort: 2380
  selector:
    etcd_node: etcd-server
```

3.  In your PyTorch job manifest, use the headless service you created in the previous step as the `rendezvous` host.

```yaml
spec:
  elasticPolicy:
    rdzvBackend: etcd-v2
    rdzvHost: etcd-server-headless
    rdzvPort: 2379
```

4. Add an environment variable for the names of the Pytorch pods.

```yaml
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
```

5. Add the following to your `torchrun` command:
```sh
--local_addr=$POD_NAME
```

Explanation of the above parameters:

| Parameter     | Explanation                                                                                         |
| ------------- | --------------------------------------------------------------------------------------------------- |
| \--local_addr | We added the `POD_NAME` variable, and we tell `torchrun` to use it as the local address of the pod. |

6. Here's an example with `yolov5` and Training Operator. Note that the NCCL environment variables are for the `BM.GPU.B4.8` A100 shape. Change them depending on the shape you have.

```yaml
apiVersion: "kubeflow.org/v1"
kind: PyTorchJob
metadata:
  name: yolov5-training
spec:
  elasticPolicy:
    rdzvBackend: etcd-v2
    rdzvHost: etcd-server-headless
    rdzvPort: 2379
    minReplicas: 1
    maxReplicas: 8
    maxRestarts: 100
  pytorchReplicaSpecs:
    Worker:
      replicas: 1
      restartPolicy: OnFailure
      template:
        spec:
          hostNetwork: true
          hostIPC: true
          dnsPolicy: ClusterFirstWithHostNet
          containers:
            - name: pytorch
              image: ultralytics/yolov5:latest
              imagePullPolicy: Always
              env:
              - name: LOGLEVEL
                value: DEBUG
              - name: NCCL_DEBUG
                value: INFO
              - name: NCCL_IB_SPLIT_DATA_ON_QPS
                value: "0"
              - name: NCCL_IB_QPS_PER_CONNECTION
                value: "4"
              - name: NCCL_IB_GID_INDEX
                value: "3"
              - name: NCCL_IB_HCA
                value: "=mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_14,mlx5_15,mlx5_16,mlx5_17,mlx5_9,mlx5_10,mlx5_11,mlx5_12"
              - name: NCCL_IB_TC
                value: "41"
              - name: NCCL_IB_SL
                value: "0"
              - name: NCCL_IB_TIMEOUT
                value: "22"
              - name: POD_NAME
                valueFrom:
                  fieldRef:
                    fieldPath: metadata.name
              command: ["/bin/bash"]
              args:
                - "-c"
                - |
                  torchrun \
                  --nproc_per_node=1 \
                  --local_addr=$POD_NAME \
                  --nproc_per_node=1 \
                  train.py \
                  --batch-size=32 \
                  --epochs=100 \
                  --data=coco128.yaml \
                  --weights=datasets/weights/yolov5s.pt
              resources:
               requests:
                  nvidia.com/gpu: 1
               limits:
                  nvidia.com/gpu: 1
              volumeMounts:
                - mountPath: /dev/shm
                  name: dshm
                - mountPath: /dev/infiniband
                  name: devinf
              securityContext:
                  privileged: true
                  capabilities:
                    add:
                    - IPC_LOCK
                    - CAP_SYS_ADMIN
          volumes:
          - emptyDir:
              medium: Memory
            name: dshm
          - name: devinf
            hostPath:
              path: /dev/infiniband          
```
