# Using network locality when running workloads on OKE

> [!IMPORTANT]  
> To use the instructions in this guide, you must have a dedicated capacity pool and you must create a capacity topology. Otherwise, `rdmaTopologyData` in instance metadata service and related node labels in OKE will not be available.

## What is network locality?
Generative AI workloads drive a different set of engineering tradeoffs than traditional cloud workloads. So, we designed a purpose-built GenAI network tailored to the needs of the best-of-breed Generative AI workloads.

When possible, running a job using the nodes in the same Local Block will provide the best performance. Because the number of nodes in a Local Block is limited; depending on the number of nodes you have, the number of your concurrent jobs running, and the size of your jobs, you might need to use the nodes from another Local Block in the same Network Block or from another Network Block.

Local Block is the first latency band (Tier-0), Network Block is the second latency band (Tier-1), and HPC Island is the third latency band (Tier-2) in OCI's RDMA networks. You can read [this blog post](https://blogs.oracle.com/cloud-infrastructure/post/first-principles-zettascale-oci-superclusters) and watch the [YouTube video](https://www.youtube.com/watch?v=cZy22n5Ih78) for learning more about OCI's RDMA network design.

![OCI Cluster Network Fabric](./tiers.png)

## What type of network tier information will I have?
When you have a dedicated capacity pool and a capacity topology created for the availability domain, the following information will be available in the instance metadata service for bare metal GPU shapes:

```
curl -H 'Authorization: Bearer Oracle' http://169.254.169.254/opc/v2/host/rdmaTopologyData

{
  "customerHPCIslandId": "ocid1.hpcisland.oc1.iad.anuwcljrg5pyaeycajoqlss...",
  "customerHostId": "ocid1.computebaremetalhost.oc1.iad.anuwcljrg5pyaeycu...",
  "customerLocalBlock": "ocid1.computelocalblock.oc1.iad.anuwcljrg5pyaeyc...",
  "customerNetworkBlock": "ocid1.computenetworkblock.oc1.iad.anuwclddsdef..."
```

## Which shapes are supported?
**H100, H200, B200, MI300x**
- Kubernetes Node Affinity
- Kubernetes Pod Affinity
- Kueue
- Node Ordering script as Init Container

**A100**
- Node Ordering script as Init Container

## How do I use network locality information when running workloads on OKE?
When the locality information is available in the instance metadata service, OKE will add the following labels to your nodes during bootstrapping:

```
oci.oraclecloud.com/rdma.host_id
oci.oraclecloud.com/rdma.hpc_island_id
oci.oraclecloud.com/rdma.local_block_id
oci.oraclecloud.com/rdma.network_block_id
```
The values of the labels are hashes of the information available in instance metadata and they will be different than the OCIDs above.

Example:
```
oci.oraclecloud.com/rdma.host_id=ab3zs7y7v7q
oci.oraclecloud.com/rdma.hpc_island_id=af7ubvouuyq
oci.oraclecloud.com/rdma.local_block_id=4tjxbt4s6ua
oci.oraclecloud.com/rdma.network_block_id=7xmzl4p4wba
```

### Using Kubernetes node affinity
You can use the labels explained above to create affinity rules for your workloads. Visit [this link](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) if you want to learn more about using affinity rules on Kubernetes.

Note that because we're using soft rules (`preferredDuringSchedulingIgnoredDuringExecution`), the scheduler will try to find a node that meets the rules. If a matching node is not available, the scheduler will still schedule the pod.

You can use hard rules instead (`requiredDuringSchedulingIgnoredDuringExecution`), but that means the scheduler can't schedule the pod unless the rules are met. So your jobs might not start depending on node availability.

When using node affinity, you will need to provide the values of the `oci.oraclecloud.com/rdma.local_block_id`, `oci.oraclecloud.com/rdma.network_block_id`, and `oci.oraclecloud.com/rdma.hpc_island_id` labels. Instead of hardcoding them, you can use tools like `sed` or `yq` to change them when you're scheduling jobs. Or if you're using Helm, you can templatize those values.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: node-affinity-example
spec:
  replicas: 3
  selector:
    matchLabels:
      app: node-affinity-app
  template:
    metadata:
      labels:
        app: node-affinity-app
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: oci.oraclecloud.com/rdma.local_block_id
                    operator: In
                    values:
                      - 5tjxbt5s6ua
            - weight: 50
              preference:
                matchExpressions:
                  - key: oci.oraclecloud.com/rdma.network_block_id
                    operator: In
                    values:
                      - 7xmzl5p5wba
            - weight: 25
              preference:
                matchExpressions:
                  - key: oci.oraclecloud.com/rdma.hpc_island_id
                    operator: In
                    values:
                      - af7ubvouuyq      
      containers:
        - name: nginx
          image: nginx
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
```

### Using Kubernetes pod affinity
You can use the labels explained above to create affinity rules for your workloads. Visit [this link](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) if you want to learn more about using affinity rules on Kubernetes.

Note that because we're using soft rules (`preferredDuringSchedulingIgnoredDuringExecution`), the scheduler will try to find a node that meets the rules. If a matching node is not available, the scheduler will still schedule the pod.

You can use hard rules instead (`requiredDuringSchedulingIgnoredDuringExecution`), but that means the scheduler can't schedule the pod unless the rules are met. So your jobs might not start depending on node availability.

When using pod affinity, because you're relying on the `topologyKey` instead of node labels, you don't need to provide the values for the `oci.oraclecloud.com/rdma.local_block_id`, `oci.oraclecloud.com/rdma.network_block_id`, and `oci.oraclecloud.com/rdma.hpc_island_id` labels.

> [!NOTE]  
> Inter-pod affinity and anti-affinity require substantial amounts of processing which can slow down scheduling in large clusters significantly. We do not recommend using them in clusters larger than several hundred nodes.
> Pod anti-affinity requires nodes to be consistently labeled, in other words, every node in the cluster must have an appropriate label matching topologyKey. If some or all nodes are missing the specified topologyKey label, it can lead to unintended behavior.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pod-affinity-example
spec:
  replicas: 3
  selector:
    matchLabels:
      app: pod-affinity-app
  template:
    metadata:
      labels:
        app: pod-affinity-app
    spec:
      affinity:
        podAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - pod-affinity-app
                topologyKey: oci.oraclecloud.com/rdma.local_block_id
            - weight: 50
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - pod-affinity-app
                topologyKey: oci.oraclecloud.com/rdma.network_block_id
            - weight: 25
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - pod-affinity-app
                topologyKey: oci.oraclecloud.com/rdma.hpc_island_id                
      containers:
        - name: nginx
          image: nginx
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"

```

### Using Kueue
You will need to [enable the feature gate](https://kueue.sigs.k8s.io/docs/installation/#change-the-feature-gates-configuration) for [Topology Aware Scheduling (TAS)](https://kueue.sigs.k8s.io/docs/concepts/topology_aware_scheduling) in Kueue. Topology Aware Scheduling is currently in alpha state since Kueue v0.9.

The following example uses `node.kubernetes.io/instance-type: "BM.GPU.H100.8"` to select H100s, but you can use any label that exists on all your nodes that you're targeting with the Resource Flavor.

#### Create a Topology
```yaml
apiVersion: kueue.x-k8s.io/v1alpha1
kind: Topology
metadata:
  name: "oci-topology"
spec:
  levels:
  - nodeLabel: "oci.oraclecloud.com/rdma.hpc_island_id"
  - nodeLabel: "oci.oraclecloud.com/rdma.network_block_id"
  - nodeLabel: "oci.oraclecloud.com/rdma.local_block_id"
  - nodeLabel: "kubernetes.io/hostname"
```

#### Create a Resource Flavor
```yaml
kind: ResourceFlavor
apiVersion: kueue.x-k8s.io/v1beta1
metadata:
  name: "tas-flavor"
spec:
  nodeLabels:
    node.kubernetes.io/instance-type: "BM.GPU.H100.8"
  topologyName: "oci-topology"
```

#### Create a Cluster Queue
```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: "tas-cluster-queue"
spec:
  namespaceSelector: {}
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: "tas-flavor"
      resources:
      - name: "cpu"
        nominalQuota: 100
      - name: "memory"
        nominalQuota: 100Gi
```

#### Create a Local Queue
```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: tas-user-queue
spec:
  clusterQueue: tas-cluster-queue
```

#### Run example job
`kueue.x-k8s.io/podset-preferred-topology` indicates that a PodSet requires Topology Aware Scheduling, but scheduling all pods within pods on nodes within the same topology domain is a preference rather than requirement. The levels are evaluated one-by-one going up from the level indicated by the annotation. If the PodSet cannot fit within a given topology domain then the next topology level up is considered. If the PodSet cannot fit at the highest topology level, then it gets admitted as distributed among multiple topology domains.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  generateName: tas-sample-preferred
  labels:
    kueue.x-k8s.io/queue-name: tas-user-queue
spec:
  parallelism: 2
  completions: 2
  completionMode: Indexed
  template:
    metadata:
      annotations:
        kueue.x-k8s.io/podset-preferred-topology: "oci.oraclecloud.com/rdma.local_block_id"
    spec:
      containers:
      - name: dummy-job
        image: registry.k8s.io/e2e-test-images/agnhost:2.53
        args: ["pause"]
        resources:
          requests:
            cpu: "1"
            memory: "200Mi"
      restartPolicy: Never
```

### Using Node Ordering script as an Init Container
If your workload can use an ordered hostfile or a rankfile (e.g. `mpirun`), you can use the [Node Ordering script](../docker/node-ordering/node_ordering.py) to generate the ordered hostfile/rankfile using an Init Container and then use the generated hostlist/rankfile in your job.

The script creates the files using the same `customerLocalBlock` information available in instance metadata service.

Here's an example for running the RCCL tests with [MPI Operator](https://github.com/kubeflow/mpi-operator):

```yaml
apiVersion: kubeflow.org/v2beta1
kind: MPIJob
metadata:
  name: rccl-tests
spec:
  slotsPerWorker: 8
  runPolicy:
    cleanPodPolicy: Running
  mpiReplicaSpecs:
    Launcher:
      replicas: 1
      template:
          spec:
            initContainers:
            - name: node-ordering
              image: iad.ocir.io/hpc_limited_availability/node-ordering:mpi-operator-port-2222-v0.1
              volumeMounts:
              - name: node-ordering
                mountPath: "/node-ordering"
              - name: mpi-job-config
                mountPath: /etc/mpi
              - name: ssh-auth
                mountPath: /root/.ssh
            volumes:
            - name: node-ordering
              emptyDir: {}
            containers:
            - image: iad.ocir.io/hpc_limited_availability/oke/rccl-tests:rocm-6.3.2-OFED-24.10-1.1.4.0
              name: nccl-tests
              volumeMounts:
              - name: node-ordering
                mountPath: "/node-ordering"
              env:
              - name: OMPI_ALLOW_RUN_AS_ROOT
                value: "1"
              - name: OMPI_ALLOW_RUN_AS_ROOT_CONFIRM
                value: "1"
              command:
              - /bin/bash
              - -c
              - |
               sysctl --system
               NUM_GPUS=8
               NUM_HOSTS=$(cat /node-ordering/ordered_hostfile | wc -l)
               NP=$(($NUM_HOSTS*$NUM_GPUS))
               mpirun --allow-run-as-root \
               -mca plm_rsh_args "-p 2222" \
               --bind-to numa \
               --mca oob_tcp_if_exclude docker,lo \
               --mca btl ^openib \
               -x NCCL_DEBUG=VERSION \
               -x NCCL_IB_HCA==mlx5_0,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_7,mlx5_8,mlx5_9 \
               -x NCCL_SOCKET_IFNAME=eth0 \
               -x NCCL_IB_TC=41 \
               -x NCCL_IB_SL=0 \
               -x NCCL_IB_GID_INDEX=3 \
               -x NCCL_IB_QPS=2 \
               -x NCCL_IB_SPLIT_DATA_ON_QPS=4 \
               -x NCCL_ALGO=Ring \
               -hostfile /node-ordering/ordered_hostfile \
               -N 8 -np $NP \
               /workspace/rccl-tests/build/all_reduce_perf -b 1G -e 16G -f 2 -g 1
              resources:
                requests:
                  cpu: 2
                  memory: 128Mi
    Worker:
      replicas: 2
      template:
        metadata:
        spec:
          dnsPolicy: ClusterFirstWithHostNet
          hostNetwork: true
          containers:
          - image: iad.ocir.io/hpc_limited_availability/oke/rccl-tests:rocm-6.3.2-OFED-24.10-1.1.4.0
            securityContext:
              privileged: true
              capabilities:
                add: [IPC_LOCK, SYS_PTRACE]
            name: nccl
            command:
            - /bin/bash
            - -c
            - mkdir -p /var/run/sshd; /usr/sbin/sshd -D -p 2222 || sleep 999999999;
            ports:
            - { name: mpijob-port, containerPort: 2222, protocol: TCP }
            resources:
              requests:
                cpu: 100
                memory: 750Gi
                amd.com/gpu: 8
              limits:
                amd.com/gpu: 8
            volumeMounts:
              - mountPath: /dev/shm
                name: dshm
          volumes:
            - emptyDir:
                medium: Memory
              name: dshm
```                

### Using Volcano
Volcano added the [Network Topology Aware Scheduling](https://volcano.sh/en/docs/network_topology_aware_scheduling/) feature in v1.11.0. The feature currently requires you to create the topology information manually. Once the functionality to [support identifying network topology from node labels and converted into hyperNode resources](https://github.com/volcano-sh/volcano/pull/4146) is added to Volcano, this section of the guide will be updated with the instructions.

