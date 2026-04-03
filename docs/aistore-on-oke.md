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

We are using the aisnode image that authenticates with OCI Object Storage using Instance Principal. Please make sure you have a dynamic group and its related policies created as mentioned above. We need to still create an empty secret as below and use it. 

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
