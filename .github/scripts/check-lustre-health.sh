#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${1:?Usage: $0 <state-file> <prefix>}"
PREFIX="${2:-}"

echo "Health check: PVC binding"
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: lustre-test-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 50Gi
  volumeName: lustre-pv
EOF

kubectl wait --for='jsonpath={.status.phase}=Bound' pvc/lustre-test-pvc --timeout=120s
echo "OK:   Lustre PVC bound"

echo "Health check: Lustre write"
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: lustre-writer
  labels:
    app.kubernetes.io/name: lustre-test
    app.kubernetes.io/component: writer
spec:
  restartPolicy: Never
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
  - key: amd.com/gpu
    operator: Exists
  containers:
  - name: writer
    image: busybox
    command: ["sh", "-c", "echo 'lustre-test-content' > /mnt/lustre/testfile.txt && sync"]
    volumeMounts:
    - name: lustre
      mountPath: /mnt/lustre
  volumes:
  - name: lustre
    persistentVolumeClaim:
      claimName: lustre-test-pvc
EOF

kubectl wait --for='jsonpath={.status.phase}=Succeeded' pod/lustre-writer --timeout=120s
LUSTRE_WRITER_NODE=$(kubectl get pod lustre-writer -o jsonpath='{.spec.nodeName}')
echo "OK:   Lustre writer pod completed (node: $LUSTRE_WRITER_NODE)"

echo "Health check: Lustre read"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: lustre-reader
  labels:
    app.kubernetes.io/name: lustre-test
    app.kubernetes.io/component: reader
spec:
  restartPolicy: Never
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: lustre-test
            app.kubernetes.io/component: writer
        topologyKey: kubernetes.io/hostname
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
  - key: amd.com/gpu
    operator: Exists
  containers:
  - name: reader
    image: busybox
    command: ["sh", "-c", "cat /mnt/lustre/testfile.txt"]
    volumeMounts:
    - name: lustre
      mountPath: /mnt/lustre
  volumes:
  - name: lustre
    persistentVolumeClaim:
      claimName: lustre-test-pvc
EOF

kubectl wait --for='jsonpath={.status.phase}=Succeeded' pod/lustre-reader --timeout=120s
CONTENT=$(kubectl logs lustre-reader)
if [[ "$CONTENT" != *"lustre-test-content"* ]]; then
  echo "FAIL: reader pod output does not contain expected content: $CONTENT"
  exit 1
fi
echo "OK:   Lustre reader output: $CONTENT"

echo "Health check: Lustre OS-level mount (hostPath write+read)"
LUSTRE_MOUNT_PATH=$(jq -r ".${PREFIX}lustre_mount_path.value // \"/mnt/oci-lustre\"" "$STATE_FILE")
echo "  host mount path: $LUSTRE_MOUNT_PATH"
# Write and read via the host mount to verify it works end-to-end.
# No mount wait needed -- kubelet runs in the host mount namespace and
# can see the cloud-init Lustre mount. Pods can't see it in their own
# /proc/mounts due to mount namespace isolation, but hostPath works.
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: lustre-hostpath-reader
spec:
  restartPolicy: Never
  nodeName: ${LUSTRE_WRITER_NODE}
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
  - key: amd.com/gpu
    operator: Exists
  containers:
  - name: rw
    image: busybox
    command: ["sh", "-c", "echo 'hostpath-test-content' > /mnt/lustre-host/hostpath-testfile.txt && sync && cat /mnt/lustre-host/hostpath-testfile.txt"]
    volumeMounts:
    - name: lustre-host
      mountPath: /mnt/lustre-host
  volumes:
  - name: lustre-host
    hostPath:
      path: ${LUSTRE_MOUNT_PATH}
      type: Directory
EOF
kubectl wait --for='jsonpath={.status.phase}=Succeeded' pod/lustre-hostpath-reader --timeout=120s
HOST_CONTENT=$(kubectl logs lustre-hostpath-reader)
if [[ "$HOST_CONTENT" != *"hostpath-test-content"* ]]; then
  echo "FAIL: Lustre hostPath output does not contain expected content: $HOST_CONTENT"
  exit 1
fi
echo "OK:   Lustre hostPath output: $HOST_CONTENT"
echo "Health check: all Lustre health checks passed"
