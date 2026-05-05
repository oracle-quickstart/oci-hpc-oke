# Alluxio on OKE — Quickstart

Deploy Alluxio Enterprise on an existing OKE cluster with workers (shapes having local NVMe drives), local NVMe pagestore, and OCI Object Storage (S3-compatible API) as UFS. 

> Replace all placeholder values before use.

---

## 0. Prerequisites and Topology

- Existing OKE cluster (Kubernetes 1.34+ recommended).
- Worker nodes with local NVMe.
- `kubectl`, `helm`, and `docker` (or `podman-docker`) installed on admin/operator host.
- Access to private Alluxio artifacts (image tarballs + operator helm chart + license key).

Minimum recommended production role split (not tested for large clusters like 100+ nodes):
- 1 node for coordinator
- 3 stable nodes for etcd
- N worker nodes for Alluxio workers

Example labels used in this guide:
- `alluxio-role=coordinator`
- `alluxio-role=etcd`
- `alluxio-role=worker`

---

## 1. Label Nodes by Role

Label your selected nodes:

```bash
kubectl label node <COORDINATOR_NODE> alluxio-role=coordinator --overwrite

kubectl label node <ETCD_NODE_1> alluxio-role=etcd --overwrite
kubectl label node <ETCD_NODE_2> alluxio-role=etcd --overwrite
kubectl label node <ETCD_NODE_3> alluxio-role=etcd --overwrite

kubectl label node <WORKER_NODE_1> alluxio-role=worker --overwrite
kubectl label node <WORKER_NODE_2> alluxio-role=worker --overwrite
kubectl label node <WORKER_NODE_3> alluxio-role=worker --overwrite
# Add additional worker labels as needed
```

Verify:

```bash
kubectl get nodes -L alluxio-role
```

---

## 2. Install Java 11 + etcd on Nodes (Bootstrap DaemonSet)

> IMPORTANT:
> - You can move this to cloud-init.
> - etcd should run on 3 stable dedicated nodes (not transient/busy nodes).

Apply the installer DaemonSet:

```bash
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: node-package-install-script
  namespace: kube-system
data:
  install.sh: |
    #!/usr/bin/env bash
    set -euxo pipefail

    MARKER="/var/lib/oke-node-bootstrap/java11-etcd.done"

    if chroot /host test -f "${MARKER}"; then
      echo "Marker exists on host, skipping install"
      exit 0
    fi

    chroot /host /usr/bin/env bash -lc '
      set -euxo pipefail
      export DEBIAN_FRONTEND=noninteractive

      mkdir -p /var/lib/oke-node-bootstrap

      apt-get update
      apt-get install -y software-properties-common
      add-apt-repository -y universe
      apt-get update
      apt-get install -y openjdk-11-jdk etcd-client etcd-server

      systemctl disable --now etcd || true

      java -version
      javac -version
      etcd --version
      etcdctl version

      touch /var/lib/oke-node-bootstrap/java11-etcd.done
    '

    echo "Host install complete"
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: install-java11-etcd
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: install-java11-etcd
  template:
    metadata:
      labels:
        app: install-java11-etcd
    spec:
      hostPID: true
      hostNetwork: true
      tolerations:
        - operator: Exists
      nodeSelector:
        kubernetes.io/os: linux
      containers:
        - name: installer
          image: ubuntu:24.04
          securityContext:
            privileged: true
          command:
            - /bin/bash
            - /scripts/install.sh
          volumeMounts:
            - name: script
              mountPath: /scripts
            - name: host-root
              mountPath: /host
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 512Mi
      restartPolicy: Always
      volumes:
        - name: script
          configMap:
            name: node-package-install-script
            defaultMode: 0755
        - name: host-root
          hostPath:
            path: /
            type: Directory
EOF
```

Verify completion:

```bash
kubectl -n kube-system get pods -l app=install-java11-etcd -o wide
kubectl -n kube-system logs -l app=install-java11-etcd --tail=200
```

Optional on a node:

```bash
java -version
javac -version
etcd --version
etcdctl version
```

Cleanup bootstrap resources after completion:

```bash
kubectl -n kube-system delete daemonset install-java11-etcd
kubectl -n kube-system delete configmap node-package-install-script
```

---

## 3. Prepare NVMe Drives for Worker Pagestore

> IMPORTANT: The following may format local NVMe devices. Ensure data backup before use.

Label only worker nodes for NVMe init:

```bash
kubectl label node <WORKER_NODE_1> nvme-init=true --overwrite
kubectl label node <WORKER_NODE_2> nvme-init=true --overwrite
kubectl label node <WORKER_NODE_3> nvme-init=true --overwrite
```

Deploy NVMe init DaemonSet:

```bash
kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvme-init
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: nvme-init
  template:
    metadata:
      labels:
        app: nvme-init
    spec:
      nodeSelector:
        nvme-init: "true"
      hostPID: true
      hostNetwork: true
      tolerations:
        - operator: Exists
      containers:
        - name: nvme-init
          image: ubuntu:24.04
          securityContext:
            privileged: true
          env:
            - name: DEVICE1
              value: /dev/nvme0n1
            - name: DEVICE2
              value: /dev/nvme1n1
            - name: MOUNT1
              value: /mnt/nvme0n1
            - name: MOUNT2
              value: /mnt/nvme1n1
            - name: FSTYPE
              value: xfs
          command:
            - /bin/bash
            - -lc
            - |
              set -euo pipefail
              export DEBIAN_FRONTEND=noninteractive

              apt-get update
              apt-get install -y util-linux xfsprogs e2fsprogs grep sed coreutils mount

              format_and_mount() {
                local dev="$1"
                local mnt="$2"
                local fstype="$3"

                echo "Processing ${dev} -> ${mnt}"

                if [ ! -b "${dev}" ]; then
                  echo "ERROR: device ${dev} not found"
                  exit 1
                fi

                if lsblk -n "${dev}" -o NAME,TYPE | awk '$2=="part"{found=1} END{exit found?0:1}'; then
                  echo "ERROR: ${dev} has partitions; refusing to format automatically"
                  exit 1
                fi

                existing_fs="$(blkid -o value -s TYPE "${dev}" || true)"
                if [ -z "${existing_fs}" ]; then
                  echo "No filesystem detected on ${dev}; creating ${fstype}"
                  if [ "${fstype}" = "xfs" ]; then
                    mkfs.xfs -f "${dev}"
                  elif [ "${fstype}" = "ext4" ]; then
                    mkfs.ext4 -F "${dev}"
                  else
                    echo "Unsupported filesystem: ${fstype}"
                    exit 1
                  fi
                else
                  echo "${dev} already has filesystem ${existing_fs}; not reformatting"
                fi

                mkdir -p "/host${mnt}"

                uuid="$(blkid -s UUID -o value "${dev}")"
                if [ -z "${uuid}" ]; then
                  echo "ERROR: could not determine UUID for ${dev}"
                  exit 1
                fi

                if ! grep -q "UUID=${uuid} ${mnt} " /host/etc/fstab; then
                  echo "UUID=${uuid} ${mnt} ${fstype} defaults,nofail 0 2" >> /host/etc/fstab
                  echo "Added fstab entry for ${dev}"
                else
                  echo "fstab entry already present for ${dev}"
                fi

                if ! nsenter --mount=/proc/1/ns/mnt -- mountpoint -q "${mnt}"; then
                  nsenter --mount=/proc/1/ns/mnt -- mkdir -p "${mnt}"
                  nsenter --mount=/proc/1/ns/mnt -- mount "${mnt}"
                  echo "Mounted ${mnt}"
                else
                  echo "${mnt} already mounted"
                fi

                nsenter --mount=/proc/1/ns/mnt -- mkdir -p "${mnt}/alluxio/pagestore"
              }

              format_and_mount "${DEVICE1}" "${MOUNT1}" "${FSTYPE}"
              format_and_mount "${DEVICE2}" "${MOUNT2}" "${FSTYPE}"

              echo "Done"
              sleep infinity
          volumeMounts:
            - name: host-root
              mountPath: /host
              mountPropagation: Bidirectional
      volumes:
        - name: host-root
          hostPath:
            path: /
            type: Directory
EOF
```

Verify:

```bash
kubectl -n kube-system get pods -l app=nvme-init -o wide
kubectl -n kube-system logs -l app=nvme-init --tail=200
```

On a worker node, confirm:

```bash
lsblk -f
mount | grep nvme
cat /etc/fstab | grep nvme
df -h | grep nvme
```

---

## 4. Obtain and Push Private Alluxio Images to OCIR

> IMPORTANT: Use your own private artifact links and do not share vendor-provided private URLs.

Download private artifacts (examples):

```bash
curl -L '<ALLUXIO_ENTERPRISE_IMAGE_TAR_URL>' -o alluxio-enterprise-<VERSION>-linux-amd64-docker.tar
curl -L '<ALLUXIO_OPERATOR_HELM_TGZ_URL>' -o alluxio-operator-<OPERATOR_VERSION>-helmchart.tgz
curl -L '<ALLUXIO_OPERATOR_IMAGE_TAR_URL>' -o alluxio-operator-<OPERATOR_VERSION>-linux-amd64-docker.tar
```

Login/load/tag/push:

```bash
# Optional if using podman with docker CLI compatibility
sudo apt-get update && sudo apt-get install -y podman-docker

# Login to OCIR
# username format: <TENANCY_NAMESPACE>/<OCI_USERNAME>
docker login <OCI_REGION>.ocir.io

# Load tarballs
docker load -i alluxio-enterprise-<VERSION>-linux-amd64-docker.tar
docker load -i alluxio-operator-<OPERATOR_VERSION>-linux-amd64-docker.tar

# Tag images

docker tag localhost/alluxio/alluxio-enterprise:<VERSION> \
  <OCI_REGION>.ocir.io/<TENANCY_NAMESPACE>/alluxio/alluxio-enterprise:<VERSION>

docker tag localhost/<OPERATOR_VERSION>:latest \
  <OCI_REGION>.ocir.io/<TENANCY_NAMESPACE>/alluxio/alluxio-operator:<OPERATOR_VERSION>

# Push images
docker push <OCI_REGION>.ocir.io/<TENANCY_NAMESPACE>/alluxio/alluxio-enterprise:<VERSION>
docker push <OCI_REGION>.ocir.io/<TENANCY_NAMESPACE>/alluxio/alluxio-operator:<OPERATOR_VERSION>
```

---

## 5. Install Alluxio Operator

Unpack chart and set operator image values:

```bash
tar zxf alluxio-operator-<OPERATOR_VERSION>-helmchart.tgz
cat > alluxio-operator-values.yaml << 'EOF'
global:
  image: <OCI_REGION>.ocir.io/<TENANCY_NAMESPACE>/alluxio/alluxio-operator
  imageTag: <OPERATOR_VERSION>
EOF
```

Install operator:

```bash
helm -n alluxio-operator install operator -f alluxio-operator-values.yaml --create-namespace ./alluxio-operator
```

Verify:

```bash
kubectl -n alluxio-operator get pods
```

---

## 6. Deploy Alluxio Cluster

```bash
kubectl create namespace alx-ns
```

Create cluster manifest (adjust resources/counts/sizes):

```bash
kubectl apply -f - << 'EOF'
apiVersion: k8s-operator.alluxio.com/v1
kind: AlluxioCluster
metadata:
  name: alluxio-cluster
  namespace: alx-ns
spec:
  image: <OCI_REGION>.ocir.io/<TENANCY_NAMESPACE>/alluxio/alluxio-enterprise
  imageTag: <ALLUXIO_VERSION>
  properties:
    alluxio.license: "<ALLUXIO_LICENSE_BASE64>"
  coordinator:
    nodeSelector:
      alluxio-role: coordinator
    metastore:
      type: persistentVolumeClaim
      storageClass: "oci-bv"
      size: 4Gi
    resources:
      limits:
        cpu: "8"
        memory: "16Gi"
      requests:
        cpu: "4"
        memory: "12Gi"
    jvmOptions:
      - "-Xmx8g"
      - "-Xms8g"
  worker:
    nodeSelector:
      alluxio-role: worker
    count: 3
    pagestore:
      hostPath: /mnt/nvme0n1/alluxio/pagestore,/mnt/nvme1n1/alluxio/pagestore
      size: 5000Gi,5000Gi
      reservedSize: 100Gi
    resources:
      limits:
        cpu: "8"
        memory: "24Gi"
      requests:
        cpu: "4"
        memory: "12Gi"
    jvmOptions:
      - "-Xmx12g"
      - "-Xms12g"
      - "-XX:MaxDirectMemorySize=12g"
  etcd:
    replicaCount: 3
    nodeSelector:
      alluxio-role: etcd
EOF
```

Watch rollout:

```bash
kubectl -n alx-ns get pods -w
kubectl -n alx-ns get alluxiocluster alluxio-cluster -o yaml | grep -i phase -n
```

---

## 7. Mount OCI Object Storage as UFS (Single Bucket)

```bash
kubectl apply -f - << 'EOF'
apiVersion: k8s-operator.alluxio.com/v1
kind: UnderFileSystem
metadata:
  name: alluxio-oci-s3
  namespace: alx-ns
spec:
  alluxioCluster: alluxio-cluster
  path: s3://<BUCKET_NAME>/
  mountPath: /oci
  mountOptions:
    s3a.accessKeyId: "<OCI_COMPAT_ACCESS_KEY>"
    s3a.secretKey: "<OCI_COMPAT_SECRET_KEY>"
    alluxio.underfs.s3.endpoint: "https://<TENANCY_NAMESPACE>.compat.objectstorage.<OCI_REGION>.oraclecloud.com"
    alluxio.underfs.s3.endpoint.region: "<OCI_REGION>"
    alluxio.underfs.s3.disable.dns.buckets: "true"
    alluxio.underfs.s3.inherit.acl: "false"
EOF
```

Verify UFS:

```bash
kubectl -n alx-ns get ufs
kubectl -n alx-ns exec -i alluxio-cluster-coordinator-0 -- alluxio mount list
kubectl -n alx-ns exec -i alluxio-cluster-coordinator-0 -- alluxio fs ls /oci
```

---

## 8. Mount Multiple Buckets / Multiple Regions (Optional)

Apply multiple `UnderFileSystem` resources in one manifest:

```bash
kubectl apply -f - << 'EOF'
apiVersion: k8s-operator.alluxio.com/v1
kind: UnderFileSystem
metadata:
  name: alluxio-oci-region-a-bucket-1
  namespace: alx-ns
spec:
  alluxioCluster: alluxio-cluster
  path: s3://<REGION_A_BUCKET_1>/
  mountPath: /region-a-bucket-1
  mountOptions:
    s3a.accessKeyId: "<OCI_COMPAT_ACCESS_KEY>"
    s3a.secretKey: "<OCI_COMPAT_SECRET_KEY>"
    alluxio.underfs.s3.endpoint: "https://<TENANCY_NAMESPACE>.compat.objectstorage.<REGION_A>.oraclecloud.com"
    alluxio.underfs.s3.endpoint.region: "<REGION_A>"
    alluxio.underfs.s3.disable.dns.buckets: "true"
    alluxio.underfs.s3.inherit.acl: "false"
---
apiVersion: k8s-operator.alluxio.com/v1
kind: UnderFileSystem
metadata:
  name: alluxio-oci-region-b-bucket-1
  namespace: alx-ns
spec:
  alluxioCluster: alluxio-cluster
  path: s3://<REGION_B_BUCKET_1>/
  mountPath: /region-b-bucket-1
  mountOptions:
    s3a.accessKeyId: "<OCI_COMPAT_ACCESS_KEY>"
    s3a.secretKey: "<OCI_COMPAT_SECRET_KEY>"
    alluxio.underfs.s3.endpoint: "https://<TENANCY_NAMESPACE>.compat.objectstorage.<REGION_B>.oraclecloud.com"
    alluxio.underfs.s3.endpoint.region: "<REGION_B>"
    alluxio.underfs.s3.disable.dns.buckets: "true"
    alluxio.underfs.s3.inherit.acl: "false"
EOF
```

Verify mounts:

```bash
kubectl -n alx-ns exec -i alluxio-cluster-coordinator-0 -- alluxio mount list
```

---

## 9. Add Worker Capacity (Scale Out)

Check current workers:

```bash
kubectl -n alx-ns exec -i alluxio-cluster-coordinator-0 -- alluxio info nodes
kubectl -n alx-ns exec -i alluxio-cluster-coordinator-0 -- sh -c 'alluxio info nodes | grep -c ONLINE'
```
Once the node is available in the OKE cluster, make sure you follow the steps 1 to 3 outlined above.
Increase worker count in `AlluxioCluster.spec.worker.count` and re-apply:

```bash
kubectl apply -f alluxio-cluster.yaml
kubectl -n alx-ns get pods -w
kubectl -n alx-ns exec -i alluxio-cluster-coordinator-0 -- alluxio info nodes
```

---

## 10. Remove Worker Capacity (Scale In)

10.1 Cordon the node that you want to remove from the alluxio cluster. 
```bash
kubectl cordon <node-name>
```

10.2 Get the woker pod name on the particular node that you want to remove.
```bash
kubectl -n alx-ns get pods -o wide | grep alluxio-cluster-worker
```

10.3 Delete the pod on that node.

```bash
kubectl -n alx-ns delete pod <worker-pod-on-that-node>
```

10.4 Decrease `worker.count` in `alluxio-cluster` and apply.

```bash
kubectl apply -f alluxio-cluster.yaml
```

10.5 Verify the worker pod is no longer running on the cordoned node.

```bash
kubectl -n alx-ns get pods -o wide | grep alluxio-cluster-worker
```

10.6 Deregister the worker from etcd. First, retrieve the UUID of the stopped worker from the output of alluxio info nodes (the WorkerId column for the OFFLINE entry). Then remove it:

```bash
kubectl -n alx-ns exec -i alluxio-cluster-coordinator-0 -- alluxio info nodes
```

```bash
# Remove OFFLINE worker entry. You should see: Successfully removed worker: <WORKER_UUID>
kubectl -n alx-ns exec -i alluxio-cluster-coordinator-0 -- \
  alluxio process remove-worker -n <OFFLINE_WORKER_UUID>
```

```bash
# Verify cleanup
kubectl -n alx-ns exec -i alluxio-cluster-coordinator-0 -- alluxio info nodes
```

---

## 11. Quick Verification Checklist

```bash
# Operator
kubectl -n alluxio-operator get pods

# Cluster health
kubectl -n alx-ns get pods -o wide
kubectl -n alx-ns exec -i alluxio-cluster-coordinator-0 -- alluxio info nodes

# UFS mounts
kubectl -n alx-ns get ufs
kubectl -n alx-ns exec -i alluxio-cluster-coordinator-0 -- alluxio mount list

```

---

## 12. Monitor Alluxio with a Standalone Grafana Dashboard (Outside OCI-HPC-OKE Stack)

This section sets up a standalone Grafana instance and connects it to the in-cluster Alluxio Prometheus endpoint.

> This flow is intentionally **independent** of OCI HPC OKE stack-integrated monitoring.

---

### 12.1 Prerequisites

- Alluxio cluster is running and exposing Prometheus metrics.
- In-cluster Prometheus is deployed (default port `9090`).
- Host for Grafana has Docker or Podman installed and outbound image pull access.
- SSH access to bastion and operator hosts for tunneling.

```bash
kubectl -n alx-ns get pods
kubectl get svc -A | grep -i prometheus
docker --version || podman --version
```

---

### 12.2 Create Grafana Prometheus Datasource Provisioning

```bash
mkdir -p /home/ubuntu/monitoring/grafana/provisioning/datasources
cat > /home/ubuntu/monitoring/grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    url: http://localhost:9090
    isDefault: true
    access: proxy
    editable: true
EOF
```

---

### 12.3 Start Grafana Container

Use either Podman or Docker:

```bash
podman run -d --net=host --name=grafana \
  -v /home/ubuntu/monitoring/grafana/provisioning:/etc/grafana/provisioning \
  -e GF_SECURITY_ADMIN_USER=admin \
  -e GF_SECURITY_ADMIN_PASSWORD=<GRAFANA_ADMIN_PASSWORD> \
  docker.io/grafana/grafana
```

```bash
docker run -d --net=host --name=grafana \
  -v /home/ubuntu/monitoring/grafana/provisioning:/etc/grafana/provisioning \
  -e GF_SECURITY_ADMIN_USER=admin \
  -e GF_SECURITY_ADMIN_PASSWORD=<GRAFANA_ADMIN_PASSWORD> \
  docker.io/grafana/grafana
```

Verify:

```bash
docker ps -a
```

---

### 12.4 Verify In-Cluster Prometheus Health

```bash
kubectl -n alx-ns port-forward svc/alluxio-cluster-prometheus 9091:9090 &
sleep 2
curl -s http://localhost:9091/api/v1/targets \
  | python3 -m json.tool \
  | grep -E '"health"|scrapeUrl' \
  | head -40
```

Expected: coordinator + workers + etcd + Prometheus self-scrape, all report `"health": "up"`.

Cleanup:

```bash
pkill -f "port-forward.*9091"
```

---

### 12.5 Expose Prometheus via NodePort

```bash
cat > prom-nodeport.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: alluxio-prometheus-nodeport
  namespace: alx-ns
spec:
  type: NodePort
  selector:
    app.kubernetes.io/component: prometheus
    app.kubernetes.io/instance: alluxio-cluster
    app.kubernetes.io/name: alluxio
  ports:
    - name: http
      port: 9090
      targetPort: 9090
      nodePort: 30909
EOF

kubectl apply -f prom-nodeport.yaml
kubectl -n alx-ns get svc alluxio-prometheus-nodeport
```

---

### 12.6 Open Required NSG Paths

Allow traffic from bastion NSG to operator NSG for:

#### Operator NSG ingress

- Source NSG: bastion NSG → TCP `3000`
- Source NSG: bastion NSG → TCP `9090`

#### Workers NSG ingress

- Source NSG: bastion NSG → TCP `30909` (Grafana access)
- Source NSG: operator NSG → TCP `30909` (operator-origin checks)

If bastion NSG uses restricted egress, add matching egress to bastion NSG for the same ports.

#### Bastion NSG egress

- Destination NSG: operator NSG → TCP `3000`
- Destination NSG: operator NSG → TCP `9090`
- Destination NSG: workers NSG → TCP `30909`

---

### 12.7 Verify End-to-End Connectivity

Traffic path:

- Laptop → SSH tunnel to bastion → operator:3000
- Laptop → SSH tunnel to bastion → operator:9090
- Laptop → SSH tunnel to bastion → operator:30909

Create SSH tunnel from laptop:

```bash
ssh -i <PRIVATE_KEY> \
  -L 3000:<OPERATOR_PRIVATE_IP>:3000 \
  -L 9090:<OPERATOR_PRIVATE_IP>:9090 \
  -L 30909:<OPERATOR_PRIVATE_IP>:30909 \
  ubuntu@<BASTION_PUBLIC_IP>
```

If tunnel still fails with `No route to host`, operator host firewall is likely blocking non-22 ports.

Find bastion private IP on bastion:

```bash
hostname -I
ip -4 addr
```

On operator, allow bastion IP to 3000 and 9090 if host firewall blocks access. 
Note: Allow 30909 if that is blocked too.

```bash
sudo iptables -I INPUT 4 -p tcp -s <BASTION_PRIVATE_IP>/32 --dport 3000 -j ACCEPT
sudo iptables -I INPUT 4 -p tcp -s <BASTION_PRIVATE_IP>/32 --dport 9090 -j ACCEPT
```

Test from bastion:

```bash
nc -vz <OPERATOR_PRIVATE_IP> 3000
curl -I http://<OPERATOR_PRIVATE_IP>:3000
```

Persist firewall rules:

```bash
sudo apt update
sudo apt install -y iptables-persistent
sudo netfilter-persistent save
```

From bastion, test worker NodePort:

```bash
curl -sI http://<WORKER_NODE_PRIVATE_IP>:30909/-/ready
```

Expected: `HTTP/1.1 200 OK`

---

### 12.8 Import Alluxio Dashboard into Grafana

Download dashboard template:

```bash
wget -O /tmp/alluxio-dashboard.json \
  https://alluxio-binaries.s3.amazonaws.com/artifactsBundle/ee/AI-3.8-15.1.0/alluxio-ai-dashboard-template.json
```

In Grafana (`http://localhost:3000`):

1. Login with admin credentials.
2. If Grafana runs on operator host without local Prometheus, update datasource URL to `http://<WORKER_NODE_PRIVATE_IP>:30909`.
3. Import `/tmp/alluxio-dashboard.json`.
4. Set time range to __Last 15 minutes__ and refresh.

---

## Notes

- Running Alluxio at scale was not tested. 
- Alluxio abstracts Object Storage data while caching.
