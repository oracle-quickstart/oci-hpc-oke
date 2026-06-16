# AIStore on OKE — Quickstart

Deploy NVIDIA AIStore on an existing OKE cluster with BM.DenseIO.E5.128 nodes (12x 5.8T NVMe each).

## 1. Label Worker Nodes

```bash
for node in $(kubectl get nodes -l node.kubernetes.io/instance-type=BM.DenseIO.E5.128 -o name); do
  kubectl label $node aistore.nvidia.com/role=proxy-target --overwrite
done
kubectl get nodes -l aistore.nvidia.com/role=proxy-target
```

## 2. Prepare NVMe Drives

Deploy a DaemonSet that automatically formats and mounts all NVMe drives on each worker node:

IMPORTANT: Running the below will erase all data on all the NVMe drives permanently. Back up data if you need to before running the below. 

```bash
kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvme-provisioner
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: nvme-provisioner
  template:
    metadata:
      labels:
        app: nvme-provisioner
    spec:
      nodeSelector:
        aistore.nvidia.com/role: proxy-target
      hostPID: true
      hostNetwork: true
      containers:
      - name: nvme-setup
        image: ubuntu:24.04
        securityContext:
          privileged: true
        command:
        - /bin/bash
        - -c
        - |
          apt-get update -qq && apt-get install -y -qq mdadm xfsprogs util-linux > /dev/null 2>&1

          set -euo pipefail
          echo "=== NVMe provisioner starting on $(hostname) ==="

          FSTAB="/host-etc/fstab"
          MDADM_CONF="/host-etc/mdadm/mdadm.conf"

          # Stop any existing RAID
          if grep -q md0 /proc/mdstat 2>/dev/null; then
            echo "Tearing down existing RAID..."
            umount /mnt/nvme 2>/dev/null || true
            mdadm --stop /dev/md0 2>/dev/null || true
            mdadm --stop --scan 2>/dev/null || true
            for dev in /dev/nvme*n1; do
              mdadm --zero-superblock $dev 2>/dev/null || true
            done
            echo "" > "${MDADM_CONF}" 2>/dev/null || true
            sed -i '/\/dev\/md0/d' "${FSTAB}"
            sed -i '/\/mnt\/nvme/d' "${FSTAB}"
          fi

          # Format and mount each NVMe drive individually
          DISKS=($(ls -1 /dev/nvme*n1 2>/dev/null | sort -V))
          echo "Found ${#DISKS[@]} NVMe drives"
          for idx in "${!DISKS[@]}"; do
            dev="${DISKS[$idx]}"
            mp="/mnt/nvme${idx}"
            if mountpoint -q "${mp}" 2>/dev/null; then
              echo "${mp} already mounted, skipping"
              continue
            fi
            echo "Setting up ${dev} -> ${mp}"
            mkdir -p "${mp}"
            wipefs -a "${dev}" 2>/dev/null || true
            mkfs.xfs -f "${dev}"
            mount -o defaults,noatime,nofail "${dev}" "${mp}"
            uuid=$(blkid -s UUID -o value "${dev}")
            sed -i "\|${mp}|d" "${FSTAB}"
            echo "UUID=${uuid} ${mp} xfs noatime,nodiratime,logbufs=8,logbsize=256k,largeio,inode64,swalloc,allocsize=131072k,nobarrier" >> "${FSTAB}"
          done

          echo "=== NVMe provisioner done ==="
          df -h | grep nvme

          # Sleep forever to keep the DaemonSet running
          sleep infinity
        volumeMounts:
        - name: host-dev
          mountPath: /dev
        - name: host-mnt
          mountPath: /mnt
          mountPropagation: Bidirectional
        - name: host-etc
          mountPath: /host-etc
        - name: host-run
          mountPath: /run/mdadm
      volumes:
      - name: host-dev
        hostPath:
          path: /dev
      - name: host-mnt
        hostPath:
          path: /mnt
      - name: host-etc
        hostPath:
          path: /etc
      - name: host-run
        hostPath:
          path: /run/mdadm
      tolerations:
      - operator: Exists
EOF
```

Wait for all pods to complete setup:

```bash
kubectl -n kube-system get pods -l app=nvme-provisioner -o wide
kubectl -n kube-system logs -l app=nvme-provisioner --tail=100
```

Verify from any worker node: `df -h | grep nvme` should show 12 drives at `/mnt/nvme0` through `/mnt/nvme11`.

## 3. Apply Network Tuning

Deploy a DaemonSet that applies sysctl tuning and open file limits tuning on all worker nodes:

```bash
kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: sysctl-tuner
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: sysctl-tuner
  template:
    metadata:
      labels:
        app: sysctl-tuner
    spec:
      nodeSelector:
        aistore.nvidia.com/role: proxy-target
      hostPID: true
      hostNetwork: true
      initContainers:
      - name: sysctl-apply
        image: ubuntu:24.04
        securityContext:
          privileged: true
        command:
        - /bin/bash
        - -c
        - |
          cat << 'SYSCTL' > /host-etc/sysctl.d/99-aistore.conf
          net.core.somaxconn=65535
          net.core.rmem_max=134217728
          net.core.wmem_max=134217728
          net.core.optmem_max=25165824
          net.core.netdev_max_backlog=250000
          net.ipv4.tcp_wmem=4096 16384 134217728
          net.ipv4.tcp_rmem=4096 262144 134217728
          net.ipv4.tcp_tw_reuse=1
          net.ipv4.ip_local_port_range=2048 65535
          net.ipv4.tcp_max_tw_buckets=1440000
          net.ipv4.tcp_max_syn_backlog=100000
          net.ipv4.tcp_mtu_probing=2
          net.ipv4.tcp_slow_start_after_idle=0
          net.ipv4.tcp_adv_win_scale=1
          SYSCTL
          sysctl -p /host-etc/sysctl.d/99-aistore.conf
          echo "=== sysctl tuning applied on $(hostname) ==="

          # root-only nofile limits
          mkdir -p /host-etc/security/limits.d
          cat << 'LIMITS' > /host-etc/security/limits.d/99-aistore-nofile.conf
          root             hard    nofile          262144
          root             soft    nofile          262144
          LIMITS
          chmod 0644 /host-etc/security/limits.d/99-aistore-nofile.conf
          echo "=== root limits tuning applied on $(hostname) ==="
        volumeMounts:
        - name: host-etc
          mountPath: /host-etc
      containers:
      - name: pause
        image: registry.k8s.io/pause:3.9
      volumes:
      - name: host-etc
        hostPath:
          path: /etc
      tolerations:
      - operator: Exists
EOF
```

Verify:

```bash
kubectl -n kube-system get pods -l app=sysctl-tuner
kubectl -n kube-system logs -l app=sysctl-tuner -c sysctl-apply
```

## 4. Install Cert-Manager (if not present)

```bash
# Check if cert-manager is already running
if kubectl get pods -n cert-manager 2>/dev/null | grep -q Running; then
  echo "cert-manager already running, skipping"
else
  # Install cert-manager
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.crds.yaml
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=120s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=120s
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=120s
fi
```

## 5. Install AIStore Operator

```bash
kubectl create namespace ais
helm repo add ais https://nvidia.github.io/ais-k8s/charts
helm repo update
helm upgrade --install ais-operator ais/ais-operator --namespace ais

# Service account
kubectl -n ais create serviceaccount ais-sa
kubectl create clusterrolebinding ais-sa-cluster-admin \
  --clusterrole=cluster-admin --serviceaccount=ais:ais-sa

# Verify
kubectl get pods -n ais
kubectl get crd | grep ais
```

## 6. Policies for using Instance Principal for authentication
Create a Dynamic Group named instance_principal:
```bash
All {instance.compartment.id = 'ocid1.compartment.oc1..aaaXXXX'}
```

Either add the below policy (broader access)
```bash
Allow dynamic-group instance_principal to manage all-resources in compartment compartmentName
```
Or

Add the below policies
```bash
Allow dynamic-group instance_principal to read objectstorage-namespaces in tenancy
Allow dynamic-group instance_principal to manage object-family in compartment compartmentName
```

In order for the AIStore cluster to work, add the below policies. Whether you are using Security List or Network Security Groups, add the ingress and egress rules at the appropriate place.

1. Allow all TCP traffic between operator (consumers) and workers
2. Allow all TCP traffic between operator (consumers) and pods

If you have deployed the OKE cluster using the Oracle Stack at https://github.com/oracle-quickstart/oci-hpc-oke, then add the below Security Rules in the following Network Security Groups (NSG).

### In workers NSG

Direction: Ingress
Stateless: No
Source Type: NSG
Source: operator NSG
Destination Type:
Destination:
Protocol: TCP
Source Port Range: All
Destination Port Range: All
Type and Code: 
Allow: TCP traffic
Description: AIStore

### In pods NSG

Direction: Ingress
Stateless: No
Source Type: NSG
Source: operator NSG
Destination Type:
Destination:
Protocol: TCP
Source Port Range: All
Destination Port Range: All
Type and Code: 
Allow: TCP traffic
Description: AIStore

### In operator NSG

Direction: Ingress
Stateless: No
Source Type: NSG
Source: workers NSG
Destination Type:
Destination:
Protocol: TCP
Source Port Range: All
Destination Port Range: All
Type and Code: 
Allow: TCP traffic
Description: AIStore

Direction: Ingress
Stateless: No
Source Type: NSG
Source: pods NSG
Destination Type:
Destination:
Protocol: TCP
Source Port Range: All
Destination Port Range: All
Type and Code: 
Allow: TCP traffic
Description: AIStore

## 7. Create secret

We are using the aisnode image that authenticates with OCI Object Storage using Instance Principal. The requirement is that the AIStore version needs to be v1.4.4 or higher. Please make sure you have a dynamic group and its related policies created as mentioned above. We need to still create an empty secret as below and use it. 

```bash
kubectl create secret generic oci-inst-prncpl -n ais --from-literal=config=config
```

## 8. Deploy AIStore with OCI Object Storage as the backend

Update the OCI_COMPARTMENT_OCID, OCI_REGION, and size below for both proxySpec and targetSpec as required. 

```bash
kubectl apply -f - << 'EOF'
apiVersion: ais.nvidia.com/v1beta1
kind: AIStore
metadata:
  name: ais
  namespace: ais
spec:
  hostpathPrefix: "/etc/ais"
  logsDir: "/var/log/ais"
  nodeImage: "fra.ocir.io/idxzjcdglx2s/temp:aisnode-oci-ip-20260402-amd64-v2"
  initImage: "fra.ocir.io/idxzjcdglx2s/temp:aisinit_v5"
  enableExternalLB: false
  ociSecretName: oci-inst-prncpl
  proxySpec:
    env:
    - name: OCI_INSTANCE_PRINCIPAL_AUTH
      value: "true"
    - name: OCI_COMPARTMENT_OCID
      value: ocid1.compartment.oc1..aaaaXXXX
    - name: OCI_REGION
      value: ap-osaka-1
    size: 6
    servicePort: 51080
    portPublic: 51080
    portIntraControl: 51082
    portIntraData: 51083
    nodeSelector:
      aistore.nvidia.com/role: proxy-target
  targetSpec:
    env:
    - name: OCI_INSTANCE_PRINCIPAL_AUTH
      value: "true"
    - name: OCI_COMPARTMENT_OCID
      value: ocid1.compartment.oc1..aaaaXXXX
    - name: OCI_REGION
      value: ap-osaka-1
    size: 6
    hostNetwork: true
    hostPort: 51081
    servicePort: 51081
    portPublic: 51081
    portIntraControl: 51082
    portIntraData: 51083
    nodeSelector:
      aistore.nvidia.com/role: proxy-target
    mounts:
    - path: "/mnt/nvme0"
      useHostPath: true
      size: 5Ti
      label: "nvme"
    - path: "/mnt/nvme1"
      useHostPath: true
      size: 5Ti
      label: "nvme"
    - path: "/mnt/nvme2"
      useHostPath: true
      size: 5Ti
      label: "nvme"
    - path: "/mnt/nvme3"
      useHostPath: true
      size: 5Ti
      label: "nvme"
    - path: "/mnt/nvme4"
      useHostPath: true
      size: 5Ti
      label: "nvme"
    - path: "/mnt/nvme5"
      useHostPath: true
      size: 5Ti
      label: "nvme"
    - path: "/mnt/nvme6"
      useHostPath: true
      size: 5Ti
      label: "nvme"
    - path: "/mnt/nvme7"
      useHostPath: true
      size: 5Ti
      label: "nvme"
    - path: "/mnt/nvme8"
      useHostPath: true
      size: 5Ti
      label: "nvme"
    - path: "/mnt/nvme9"
      useHostPath: true
      size: 5Ti
      label: "nvme"
    - path: "/mnt/nvme10"
      useHostPath: true
      size: 5Ti
      label: "nvme"
    - path: "/mnt/nvme11"
      useHostPath: true
      size: 5Ti
      label: "nvme"
EOF
```

Wait for pods:

```bash
kubectl -n ais get pods -w
# Wait until all proxy and target pods are Running
kubectl -n ais get sts
```

## 9. Create Load Balancer Service

```bash
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: ais-proxy-lb
  namespace: ais
  annotations:
    service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
    service.beta.kubernetes.io/oci-load-balancer-internal: "true"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "100"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "8000"
    oci.oraclecloud.com/node-label-selector: aistore.nvidia.com/role=proxy-target
spec:
  type: LoadBalancer
  selector:
    app: ais
    component: proxy
  ports:
  - name: pub
    protocol: TCP
    port: 51080
    targetPort: 51080
EOF

# Wait for external IP
kubectl get svc -n ais ais-proxy-lb -w
```

## 10. Install AIS CLI and Test

This is currently testing creating buckets, objects and getting buckets, objects locally from NVMe using AIStore.

```bash
# Install Go 1.26+ and build tools (system Go is typically too old)
sudo apt-get update && sudo apt-get install -y make
sudo rm -rf /usr/local/go
curl -fsSL https://go.dev/dl/go1.26.1.linux-amd64.tar.gz | sudo tar -C /usr/local -xz
export PATH=/usr/local/go/bin:$PATH
echo 'export PATH=/usr/local/go/bin:$PATH' >> ~/.bashrc
go version

# Build aisloader from source
export GOPATH=$HOME/go
mkdir -p $GOPATH/src/github.com/NVIDIA
cd $GOPATH/src/github.com/NVIDIA
git clone https://github.com/NVIDIA/aistore.git
cd aistore
make aisloader
sudo cp $GOPATH/bin/aisloader /usr/local/bin/

# Download the ais from the below link. 
cd ~
wget https://idxzjcdglx2s.objectstorage.ap-osaka-1.oci.customer-oci.com/p/rfK6qyXJxVOHhWU1lyypazeSBwLYBiMhmbMlQlm1qadX97TY8sbr_Ug0tpu4f3vJ/n/idxzjcdglx2s/b/ais/o/ais
chmod +x ais
sudo mv ~/ais /usr/local/bin/
ais version

# Set endpoint (auto-detect LB IP)
export AIS_ENDPOINT=http://$(kubectl get svc -n ais ais-proxy-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):51080

# Verify
ais show cluster

# Smoke test
ais create ais://test-bucket
echo "Hello from AIStore" > /tmp/test.txt
ais put /tmp/test.txt ais://test-bucket/test.txt
ais get ais://test-bucket/test.txt /tmp/test-out.txt
cat /tmp/test-out.txt

# List all buckets from Object Storage
ais ls oc:// --all

# List all objects in a bucket
ais ls oc://bucket-name --all

# Get a specific object
ais get oc://bucket-name/object-name /tmp/object-name

# Put an object into a bucket
ais put /tmp/object-name oc://bucket-name/object-name
```

## 11. Run Benchmark

This is currently running benchmarks locally from data on NVMe using AIStore.

```bash
# Tune sysctl on the machine running aisloader to avoid port exhaustion
sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535"
sudo sysctl -w net.ipv4.tcp_tw_reuse=1

export AIS_ENDPOINT=http://$(kubectl get svc -n ais ais-proxy-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):51080

# Pre-create bucket
ais create ais://bench

# Write (32 workers, 1MB objects, 1 min)
aisloader -bucket=ais://bench -duration=1m -numworkers=32 \
  -minsize=1MB -maxsize=1MB -pctput=100 -cleanup=false

# Read
aisloader -bucket=ais://bench -duration=1m -numworkers=32 \
  -minsize=1MB -maxsize=1MB -pctput=0 -cleanup=false
```

For aggregate throughput, deploy a benchmark DaemonSet that runs aisloader from all worker nodes in parallel:

```bash
# Pre-create the bucket
ais create ais://ds-bench 2>/dev/null || true

# Deploy benchmark DaemonSet
LB_IP=$(kubectl get svc -n ais ais-proxy-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

kubectl apply -f - << EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ais-bench
  namespace: ais
spec:
  selector:
    matchLabels:
      app: ais-bench
  template:
    metadata:
      labels:
        app: ais-bench
    spec:
      nodeSelector:
        aistore.nvidia.com/role: proxy-target
      hostNetwork: true
      containers:
      - name: bench
        image: aistorage/ais-util:latest
        command: ["/bin/bash", "-c"]
        args:
        - |
          /usr/bin/aisloader \
            -bucket=ais://ds-bench \
            -duration=2m \
            -numworkers=64 \
            -minsize=1MB \
            -maxsize=1MB \
            -pctput=100 \
            -cleanup=false \
            -ip=\${LB_IP} \
            -port=51080
          echo "=== Benchmark complete on \$(hostname) ==="
          sleep infinity
        env:
        - name: LB_IP
          value: "${LB_IP}"
      tolerations:
      - operator: Exists
      restartPolicy: Always
EOF

# Watch progress
sleep 10
kubectl -n ais logs -l app=ais-bench --tail=3

# View results per pod (pods sleep after completion)
for pod in $(kubectl get pods -n ais -l app=ais-bench -o name); do
  NODE=$(kubectl get -n ais $pod -o jsonpath='{.spec.nodeName}')
  echo "$NODE: $(kubectl logs -n ais $pod | grep -E '^[0-9].*PUT.*GiB/s' | tail -1)"
done

# Cleanup write benchmark
kubectl delete ds ais-bench -n ais
```

### Read Benchmark DaemonSet

Run after the write benchmark (reads the objects written above):

```bash
LB_IP=$(kubectl get svc -n ais ais-proxy-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

kubectl apply -f - << EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ais-bench-read
  namespace: ais
spec:
  selector:
    matchLabels:
      app: ais-bench-read
  template:
    metadata:
      labels:
        app: ais-bench-read
    spec:
      nodeSelector:
        aistore.nvidia.com/role: proxy-target
      hostNetwork: true
      containers:
      - name: bench
        image: aistorage/ais-util:latest
        command: ["/bin/bash", "-c"]
        args:
        - |
          /usr/bin/aisloader \
            -bucket=ais://ds-bench \
            -duration=2m \
            -numworkers=64 \
            -minsize=1MB \
            -maxsize=1MB \
            -pctput=0 \
            -cleanup=false \
            -ip=\${LB_IP} \
            -port=51080
          echo "=== Read benchmark complete on \$(hostname) ==="
          sleep infinity
        env:
        - name: LB_IP
          value: "${LB_IP}"
      tolerations:
      - operator: Exists
      restartPolicy: Always
EOF

# View results
sleep 150
for pod in $(kubectl get pods -n ais -l app=ais-bench-read -o name); do
  NODE=$(kubectl get -n ais $pod -o jsonpath='{.spec.nodeName}')
  echo "$NODE: $(kubectl logs -n ais $pod | grep -E '^[0-9].*GET.*GiB/s' | tail -1)"
done

# Cleanup
kubectl delete ds ais-bench-read -n ais
```

## 12. Access objects from multiple regions

Even if your AIStore cluster is set up in one particular region, you can access objects from other regions as well. There is no limit to the number of regions you can access. 

IMPORTANT: To use this feature, the AIStore version needs to be v1.4.4 or higher. 

In the below example, we will be listing objects from three different regions. Kindly note, the AIStore cluster is in a different region than the regions below. 

Register existing OCI Buckets.

BUCKET_PHX=aistore-phx
BUCKET_YYZ=aistore-yyz
BUCKET_FRA=aistore-fra

```bash
ais create oc://#phx/$BUCKET_PHX --props='extra.oci.region=us-phoenix-1'
ais bucket props show oc://#phx/$BUCKET_PHX extra
ais create oc://#yyz/$BUCKET_YYZ --props='extra.oci.region=ca-toronto-1'
ais bucket props show oc://#yyz/$BUCKET_YYZ extra
ais create oc://#fra/$BUCKET_FRA --props='extra.oci.region=eu-frankfurt-1'
ais bucket props show oc://#fra/$BUCKET_FRA extra
```

List the Buckets:

```bash
ais ls oc://#phx/$BUCKET_PHX
ais ls oc://#yyz/$BUCKET_YYZ
ais ls oc://#fra/$BUCKET_FRA
```

Upload objects:

```bash
ais put ./file.txt oc://#phx/$BUCKET_PHX/file.txt
```

Similarly, you can upload objects to other regions. 

Download specific objects:

```bash
# Discards the client-side output
ais get oc://#fra/$BUCKET_FRA/obj /dev/null

# Save the retrieved bytes
ais get oc://#fra/$BUCKET_FRA/obj /tmp/obj
```

Similarly, you can download objects from buckets in other regions. 

## 13. Add a Node to an Existing AIStore Cluster

Use this section when the AIStore cluster is already running and you want to add one more OKE worker node to the AIStore deployment.

This procedure assumes:

- The AIStore namespace is `ais`.
- The AIStore custom resource name is `ais`.
- AIStore worker nodes are selected using the label `aistore.nvidia.com/role=proxy-target`.
- The cluster uses the AIStore operator.
- The AIStore targets use local NVMe host paths such as `/mnt/nvme0` through `/mnt/nvme11`.

Set common variables:

    export NS=ais
    export AIS=ais
    export NEW_NODE=<new-worker-node-name>
    export NEW_SIZE=<new-ai-store-size>

Example:

    export NS=ais
    export AIS=ais
    export NEW_NODE=10.140.71.151
    export NEW_SIZE=7

### 13.1 Add or identify the new OKE worker node

Add a worker node to the OKE node pool, or identify an existing node that you want to dedicate to AIStore.

Verify that the node is ready:

    kubectl get nodes -o wide
    kubectl get node ${NEW_NODE}

The node must show `Ready` before continuing.

### 13.2 Label the node for AIStore

IMPORTANT: If the `nvme-provisioner` DaemonSet from this guide is still running, labeling the node will cause it to run on the new node. That DaemonSet formats and mounts local NVMe devices. Do not label the node until you are ready for the node-local NVMe setup to run.

Add the AIStore placement label:

    kubectl label node ${NEW_NODE} aistore.nvidia.com/role=proxy-target --overwrite

Verify:

    kubectl get nodes -L aistore.nvidia.com/role
    kubectl get nodes -l aistore.nvidia.com/role=proxy-target -o wide

### 13.3 Wait for NVMe and host tuning DaemonSets

If you used the `nvme-provisioner` and `sysctl-tuner` DaemonSets from this guide, verify that both have run on the new node:

    kubectl -n kube-system get pods -l app=nvme-provisioner -o wide | grep ${NEW_NODE}
    kubectl -n kube-system get pods -l app=sysctl-tuner -o wide | grep ${NEW_NODE}

Check recent logs:

    kubectl -n kube-system logs -l app=nvme-provisioner --tail=100
    kubectl -n kube-system logs -l app=sysctl-tuner -c sysctl-apply --tail=100

Verify the NVMe mount paths from the node, or with a privileged debug pod:

    df -h | grep nvme
    mount | grep nvme

Expected result: the new node has the same mount layout as the existing AIStore nodes, for example `/mnt/nvme0` through `/mnt/nvme11`.

### 13.4 Check current AIStore state before scaling

    kubectl get aistore -n ${NS}
    kubectl get sts -n ${NS}
    kubectl get pods -n ${NS} -o wide

Expected starting state:

    ais          Ready
    ais-proxy    N/N
    ais-target   N/N

Do not scale up while the cluster is already stuck in `Upgrading` or while existing targets are in `CrashLoopBackOff`.

### 13.5 Increase proxy and target size in the AIStore custom resource

This guide deploys AIStore using `proxySpec.size` and `targetSpec.size`, so update both values.

Example: scale to `${NEW_SIZE}` proxies and `${NEW_SIZE}` targets:

    kubectl patch aistore ${AIS} -n ${NS} --type merge \
      -p "{\"spec\":{\"proxySpec\":{\"size\":${NEW_SIZE}},\"targetSpec\":{\"size\":${NEW_SIZE}}}}"

If your AIStore custom resource uses a top-level `spec.size` instead of per-role sizes, use this form instead:

    kubectl patch aistore ${AIS} -n ${NS} --type merge \
      -p "{\"spec\":{\"size\":${NEW_SIZE}}}"

### 13.6 Watch the operator create the new pods

Watch pods:

    kubectl get pods -n ${NS} -o wide -w

In another terminal, watch the operator logs:

    kubectl logs -n ${NS} deploy/ais-operator-controller-manager --since=10m -f

Expected result:

- A new proxy pod is created, for example `ais-proxy-6`.
- A new target pod is created, for example `ais-target-6`.
- The new target lands on the newly labeled node if there are no other eligible empty AIStore nodes.
- `kubectl get aistore -n ais` eventually returns `Ready`.

### 13.7 Verify final state

    kubectl get aistore -n ${NS}
    kubectl get sts -n ${NS}
    kubectl get pods -n ${NS} -o wide

Expected result:

    ais          Ready
    ais-proxy    ${NEW_SIZE}/${NEW_SIZE}
    ais-target   ${NEW_SIZE}/${NEW_SIZE}

If an AIStore admin client is deployed, verify from the AIS CLI as well:

    kubectl get deploy -n ${NS} | grep client

    export AIS_CLIENT=$(kubectl get deploy -n ${NS} -o name | grep client | head -1)
    kubectl exec -n ${NS} ${AIS_CLIENT} -- ais show cluster

If no admin client exists, run the AIS CLI from a host where `AIS_ENDPOINT` points to the AIStore proxy load balancer:

    export AIS_ENDPOINT=http://$(kubectl get svc -n ais ais-proxy-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):51080
    ais show cluster

---

## 14. Remove a Node from an Existing AIStore Cluster

There are multiple valid removal workflows. Pick the scenario that matches the operation you are performing.

### 14.1 Scenario selection

| Scenario | Use when | Main action |
|---|---|---|
| Generic scale-down | You only need fewer AIStore nodes and do not care which Kubernetes node is removed | Patch the AIStore CR size down |
| Remove a specific node with no spare capacity | You need to repair one exact node and cannot reschedule the pods elsewhere | Cordon/unlabel the node, scale the AIStore CR down, and remove only pods that are outside the desired replica range |
| Remove a specific node with spare capacity | You have another prepared AIStore node available and want to keep the same AIStore size | Cordon/unlabel the repair node and delete the AIS pods on that node so Kubernetes recreates them elsewhere |
| Temporary AIS lifecycle operation | You want to put an AIS node in maintenance without changing Kubernetes capacity | Use `ais cluster add-remove-nodes start-maintenance` from the AIS CLI |
| Break-glass recovery | The operator is stuck in `Upgrading` after the CR already has the desired smaller size | Scale the StatefulSets only after confirming the CR already matches the intended final size |

### 14.2 Common pre-checks before any node removal

Set variables:

    export NS=ais
    export AIS=ais
    export NODE_TO_REPAIR=<node-name-or-node-ip>
    export OLD_SIZE=<current-ai-store-size>
    export NEW_SIZE=<desired-ai-store-size-after-removal>

Example:

    export NS=ais
    export AIS=ais
    export NODE_TO_REPAIR=10.140.71.151
    export OLD_SIZE=6
    export NEW_SIZE=5

Stop benchmark or load-generator DaemonSets before changing cluster size:

    kubectl delete daemonset -n ${NS} ais-bench --ignore-not-found
    kubectl delete daemonset -n ${NS} ais-bench-read --ignore-not-found

Check for benchmark Jobs:

    kubectl get jobs -n ${NS}

Check AIStore health:

    kubectl get aistore -n ${NS}
    kubectl get sts -n ${NS}
    kubectl get pods -n ${NS} -o wide

If an AIS CLI client is available:

    export AIS_CLIENT=$(kubectl get deploy -n ${NS} -o name | grep client | head -1)
    kubectl exec -n ${NS} ${AIS_CLIENT} -- ais show cluster

Expected healthy state before a planned removal:

    ais          Ready
    ais-proxy    ${OLD_SIZE}/${OLD_SIZE}
    ais-target   ${OLD_SIZE}/${OLD_SIZE}

---

## 14.3 Scenario A: Generic scale-down

Use this when you want to reduce cluster size and do not care which Kubernetes node loses AIStore pods.

### 14.3.1 Patch the AIStore custom resource

This guide uses per-role sizes:

    kubectl patch aistore ${AIS} -n ${NS} --type merge \
      -p "{\"spec\":{\"proxySpec\":{\"size\":${NEW_SIZE}},\"targetSpec\":{\"size\":${NEW_SIZE}}}}"

If your CR uses top-level `spec.size`:

    kubectl patch aistore ${AIS} -n ${NS} --type merge \
      -p "{\"spec\":{\"size\":${NEW_SIZE}}}"

### 14.3.2 Watch decommission and reconciliation

    kubectl get pods -n ${NS} -o wide -w

In another terminal:

    kubectl logs -n ${NS} deploy/ais-operator-controller-manager --since=10m -f

Expected behavior:

- AIStore enters `Upgrading`.
- Extra proxy pods are removed.
- Extra target pods enter decommission/maintenance flow.
- Rebalance runs if required.
- The StatefulSets shrink to `${NEW_SIZE}`.
- The AIStore CR returns to `Ready`.

### 14.3.3 Verify

    kubectl get aistore -n ${NS}
    kubectl get sts -n ${NS}
    kubectl get pods -n ${NS} -o wide

Expected result:

    ais          Ready
    ais-proxy    ${NEW_SIZE}/${NEW_SIZE}
    ais-target   ${NEW_SIZE}/${NEW_SIZE}

---

## 14.4 Scenario B: Remove a specific node with no spare capacity

Use this when there is no extra AIStore-capable node available. Since there is no spare capacity, the AIStore cluster must shrink by one before the node can be repaired.

IMPORTANT: Kubernetes StatefulSets scale by ordinal, not by arbitrary node name. If the node you want to repair does not host the highest proxy and target ordinals, a normal scale-down may remove different pods first. In that case, either repair the node that owns the highest ordinals, scale down further, or add a temporary replacement node first.

### 14.4.1 Identify AIS pods on the node

    kubectl get pods -n ${NS} -o wide | grep ${NODE_TO_REPAIR}

Example output:

    ais-proxy-5    1/1 Running ... 10.140.71.151
    ais-target-5   1/1 Running ... 10.140.71.151

Check all AIS pods and ordinals:

    kubectl get pods -n ${NS} -o wide | egrep 'ais-proxy|ais-target'

If the node hosts the highest proxy and target ordinals, it is a good scale-down candidate.

### 14.4.2 Cordon the node

Prevent new pods from being scheduled to the node:

    kubectl cordon ${NODE_TO_REPAIR}

### 14.4.3 Remove the AIStore scheduling label

Remove the label so future AIS pods do not land on this node:

    kubectl label node ${NODE_TO_REPAIR} aistore.nvidia.com/role-

Verify:

    kubectl get nodes -L aistore.nvidia.com/role

### 14.4.4 Scale the AIStore CR down

Patch both proxy and target sizes:

    kubectl patch aistore ${AIS} -n ${NS} --type merge \
      -p "{\"spec\":{\"proxySpec\":{\"size\":${NEW_SIZE}},\"targetSpec\":{\"size\":${NEW_SIZE}}}}"

If your CR uses top-level `spec.size`:

    kubectl patch aistore ${AIS} -n ${NS} --type merge \
      -p "{\"spec\":{\"size\":${NEW_SIZE}}}"

### 14.4.5 Watch reconciliation

    kubectl get pods -n ${NS} -o wide -w

In another terminal:

    kubectl logs -n ${NS} deploy/ais-operator-controller-manager --since=10m -f

### 14.4.6 Remove leftover pods only if they are outside the desired replica range

After scaling from 6 to 5, ordinals `0` through `4` are still inside the desired StatefulSet range. Ordinal `5` is outside the desired range.

Safe to delete after scale-down:

    ais-proxy-5
    ais-target-5

Not safe to delete just to empty the node if `${NEW_SIZE}=5`:

    ais-proxy-0 through ais-proxy-4
    ais-target-0 through ais-target-4

If a pod outside the desired range is stuck, delete it:

    kubectl delete pod -n ${NS} <proxy-pod-outside-desired-range> <target-pod-outside-desired-range>

### 14.4.7 Verify the node is empty of AIS pods

    kubectl get pods -n ${NS} -o wide | grep ${NODE_TO_REPAIR} || true

Verify AIStore state:

    kubectl get aistore -n ${NS}
    kubectl get sts -n ${NS}

Expected result:

    ais          Ready
    ais-proxy    ${NEW_SIZE}/${NEW_SIZE}
    ais-target   ${NEW_SIZE}/${NEW_SIZE}

### 14.4.8 Drain or repair the node

Once no AIS proxy or target pods remain on the node:

    kubectl drain ${NODE_TO_REPAIR} --ignore-daemonsets --delete-emptydir-data

Proceed with the node repair or OKE node replacement.

---

## 14.5 Scenario C: Remove a specific node when spare capacity exists

Use this when you want to keep the AIStore cluster at the same size and you have another prepared, labeled AIStore node available.

This workflow is best for remote-backed or cache-heavy AIStore deployments, such as OCI Object Storage-backed buckets, where objects can be refetched if local cached copies are lost. If you store durable user data only in local AIS buckets without mirror or EC protection, do not use this workflow without a data-protection plan.

### 14.5.1 Prepare the replacement node

Follow Section 13 to add and prepare a new AIStore-capable node, but do not increase the AIStore size if you only want to move pods off the repair node.

Verify the replacement node is labeled and ready:

    kubectl get nodes -L aistore.nvidia.com/role
    kubectl get nodes -l aistore.nvidia.com/role=proxy-target -o wide

Verify the replacement node has NVMe mounts:

    df -h | grep nvme
    mount | grep nvme

### 14.5.2 Cordon and unlabel the repair node

    kubectl cordon ${NODE_TO_REPAIR}
    kubectl label node ${NODE_TO_REPAIR} aistore.nvidia.com/role-

### 14.5.3 Identify AIS pods on the repair node

    kubectl get pods -n ${NS} -o wide | grep ${NODE_TO_REPAIR}

Example:

    ais-proxy-2    1/1 Running ... 10.140.71.151
    ais-target-2   1/1 Running ... 10.140.71.151

### 14.5.4 Delete the AIS pods on the repair node

Because the AIStore CR size is unchanged, Kubernetes will recreate the pods on another eligible node. Since the repair node is cordoned and no longer has the AIStore label, replacement pods should land on the spare AIStore node.

    kubectl delete pod -n ${NS} <proxy-pod-on-repair-node> <target-pod-on-repair-node>

Watch placement:

    kubectl get pods -n ${NS} -o wide -w

### 14.5.5 Verify

    kubectl get pods -n ${NS} -o wide | grep ${NODE_TO_REPAIR} || true
    kubectl get aistore -n ${NS}
    kubectl get sts -n ${NS}

If an AIS CLI client is available:

    kubectl exec -n ${NS} ${AIS_CLIENT} -- ais show cluster

Expected result:

- The repair node has no AIS proxy or target pods.
- The replacement node has the recreated pods.
- AIStore returns to `Ready`.

---

## 14.6 Scenario D: Temporary AIS maintenance using AIS CLI

Use AIS CLI lifecycle commands when you want to temporarily remove an AIS node from service at the AIS layer. This does not remove the Kubernetes pod and does not change the StatefulSet size.

This is useful for short AIS-level maintenance, but it is not a substitute for changing the Kubernetes AIStore custom resource when you need to add or remove Kubernetes capacity.

### 14.6.1 Show AIS node IDs

From the AIStore admin client:

    export AIS_CLIENT=$(kubectl get deploy -n ${NS} -o name | grep client | head -1)
    kubectl exec -n ${NS} ${AIS_CLIENT} -- ais show cluster
    kubectl exec -n ${NS} ${AIS_CLIENT} -- ais show cluster target

Identify the proxy or target node ID that corresponds to the pod or node you are maintaining.

### 14.6.2 Put a target in maintenance

    kubectl exec -n ${NS} ${AIS_CLIENT} -- \
      ais cluster add-remove-nodes start-maintenance <TARGET_NODE_ID>

Watch rebalance:

    kubectl exec -n ${NS} ${AIS_CLIENT} -- ais show cluster target
    kubectl exec -n ${NS} ${AIS_CLIENT} -- ais show job

### 14.6.3 Return the node from maintenance

After the node is ready to serve traffic again:

    kubectl exec -n ${NS} ${AIS_CLIENT} -- \
      ais cluster add-remove-nodes stop-maintenance <TARGET_NODE_ID>

Verify:

    kubectl exec -n ${NS} ${AIS_CLIENT} -- ais show cluster target

### 14.6.4 Permanently decommission a node with AIS CLI

Use this only when you understand how it interacts with the operator. The operator will still reconcile Kubernetes resources according to the AIStore CR sizes.

    kubectl exec -n ${NS} ${AIS_CLIENT} -- \
      ais cluster add-remove-nodes decommission <NODE_ID>

In operator-managed Kubernetes deployments, prefer changing the AIStore CR size for normal scale-down operations.

---

## 14.7 Break-glass recovery when scale-down gets stuck

Use this only if the AIStore CR already shows the intended smaller size, but the operator is stuck and the StatefulSets did not finish reconciling.

Symptoms:

    kubectl get aistore -n ${NS}

shows:

    ais    Upgrading

and operator logs show messages like:

    Target pod is in CrashLoopBackOff, skipping decommission
    waiting for target <pod> to register in smap
    Delaying scaling. Target still in decommissioning state

Check logs:

    kubectl logs -n ${NS} deploy/ais-operator-controller-manager --since=10m
    kubectl logs -n ${NS} <stuck-target-pod> -c ais-node --previous --tail=200
    kubectl logs -n ${NS} <stuck-target-pod> -c ais-node --tail=200

Confirm the AIStore CR desired size:

    kubectl describe aistore ${AIS} -n ${NS}

If the CR already has the desired smaller size, but the StatefulSets are still larger, force the StatefulSets down to the same size:

    kubectl scale sts ais-target -n ${NS} --replicas=${NEW_SIZE}
    kubectl scale sts ais-proxy -n ${NS} --replicas=${NEW_SIZE}

Watch:

    kubectl get pods -n ${NS} -o wide -w

Verify:

    kubectl get aistore -n ${NS}
    kubectl get sts -n ${NS}
    kubectl get pods -n ${NS} -o wide

Expected result:

    ais          Ready
    ais-proxy    ${NEW_SIZE}/${NEW_SIZE}
    ais-target   ${NEW_SIZE}/${NEW_SIZE}

This recovery path should not be the normal scale-down method. It is only for cases where the operator accepted the smaller desired size but was blocked by a broken or stuck extra pod.

---

## 14.8 Re-add a repaired node

After the repaired node is ready:

    export NODE_TO_REPAIR=<node-name-or-node-ip>
    export RETURN_SIZE=<desired-ai-store-size-after-adding-back>

Restore the AIStore label:

    kubectl label node ${NODE_TO_REPAIR} aistore.nvidia.com/role=proxy-target --overwrite

Uncordon the node:

    kubectl uncordon ${NODE_TO_REPAIR}

Verify:

    kubectl get nodes -L aistore.nvidia.com/role
    kubectl get nodes -l aistore.nvidia.com/role=proxy-target -o wide

If the cluster was scaled down for the repair, scale AIStore back up:

    kubectl patch aistore ${AIS} -n ${NS} --type merge \
      -p "{\"spec\":{\"proxySpec\":{\"size\":${RETURN_SIZE}},\"targetSpec\":{\"size\":${RETURN_SIZE}}}}"

If your CR uses top-level `spec.size`:

    kubectl patch aistore ${AIS} -n ${NS} --type merge \
      -p "{\"spec\":{\"size\":${RETURN_SIZE}}}"

Watch and verify:

    kubectl get pods -n ${NS} -o wide -w
    kubectl get aistore -n ${NS}
    kubectl get sts -n ${NS}

---

## 14.9 Quick reference

### Add one node

    export NS=ais
    export AIS=ais
    export NEW_NODE=<new-node>
    export NEW_SIZE=<old-size-plus-one>

    kubectl label node ${NEW_NODE} aistore.nvidia.com/role=proxy-target --overwrite

    kubectl -n kube-system get pods -l app=nvme-provisioner -o wide | grep ${NEW_NODE}
    kubectl -n kube-system get pods -l app=sysctl-tuner -o wide | grep ${NEW_NODE}

    kubectl patch aistore ${AIS} -n ${NS} --type merge \
      -p "{\"spec\":{\"proxySpec\":{\"size\":${NEW_SIZE}},\"targetSpec\":{\"size\":${NEW_SIZE}}}}"

    kubectl get pods -n ${NS} -o wide -w
    kubectl get aistore -n ${NS}
    kubectl get sts -n ${NS}

### Generic scale-down

    export NS=ais
    export AIS=ais
    export NEW_SIZE=<old-size-minus-one>

    kubectl delete daemonset -n ${NS} ais-bench --ignore-not-found
    kubectl delete daemonset -n ${NS} ais-bench-read --ignore-not-found

    kubectl patch aistore ${AIS} -n ${NS} --type merge \
      -p "{\"spec\":{\"proxySpec\":{\"size\":${NEW_SIZE}},\"targetSpec\":{\"size\":${NEW_SIZE}}}}"

    kubectl get pods -n ${NS} -o wide -w

### Remove a specific node with no spare capacity

    export NS=ais
    export AIS=ais
    export NODE_TO_REPAIR=<node-to-repair>
    export NEW_SIZE=<old-size-minus-one>

    kubectl delete daemonset -n ${NS} ais-bench --ignore-not-found
    kubectl delete daemonset -n ${NS} ais-bench-read --ignore-not-found

    kubectl get pods -n ${NS} -o wide | grep ${NODE_TO_REPAIR}

    kubectl cordon ${NODE_TO_REPAIR}
    kubectl label node ${NODE_TO_REPAIR} aistore.nvidia.com/role-

    kubectl patch aistore ${AIS} -n ${NS} --type merge \
      -p "{\"spec\":{\"proxySpec\":{\"size\":${NEW_SIZE}},\"targetSpec\":{\"size\":${NEW_SIZE}}}}"

    kubectl get pods -n ${NS} -o wide -w

### Verify after any operation

    kubectl get aistore -n ais
    kubectl get sts -n ais
    kubectl get pods -n ais -o wide
    kubectl logs -n ais deploy/ais-operator-controller-manager --since=5m
