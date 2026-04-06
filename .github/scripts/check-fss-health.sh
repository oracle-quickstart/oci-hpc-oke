#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${1:?Usage: $0 <state-file> <prefix>}"
PREFIX="${2:-}"

echo "Health check: PVC binding"
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fss-test-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 50Gi
  volumeName: fss-pv
EOF

kubectl wait --for='jsonpath={.status.phase}=Bound' pvc/fss-test-pvc --timeout=120s
echo "OK:   FSS PVC bound"

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: fss-writer
  labels:
    app.kubernetes.io/name: fss-test
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
    command: ["sh", "-c", "echo 'fss-test-content' > /mnt/fss/testfile.txt"]
    volumeMounts:
    - name: fss
      mountPath: /mnt/fss
  volumes:
  - name: fss
    persistentVolumeClaim:
      claimName: fss-test-pvc
EOF

kubectl wait --for='jsonpath={.status.phase}=Succeeded' pod/fss-writer --timeout=120s
FSS_WRITER_NODE=$(kubectl get pod fss-writer -o jsonpath='{.spec.nodeName}')
echo "  writer ran on node: $FSS_WRITER_NODE"

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: fss-reader
  labels:
    app.kubernetes.io/name: fss-test
    app.kubernetes.io/component: reader
spec:
  restartPolicy: Never
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: fss-test
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
    command: ["sh", "-c", "cat /mnt/fss/testfile.txt"]
    volumeMounts:
    - name: fss
      mountPath: /mnt/fss
  volumes:
  - name: fss
    persistentVolumeClaim:
      claimName: fss-test-pvc
EOF

kubectl wait --for='jsonpath={.status.phase}=Succeeded' pod/fss-reader --timeout=120s
CONTENT=$(kubectl logs fss-reader)
if [[ "$CONTENT" != *"fss-test-content"* ]]; then
  echo "FAIL: reader pod output does not contain expected content: $CONTENT"
  exit 1
fi
echo "OK:   FSS reader output: $CONTENT"

echo "Health check: FSS OS-level mount (hostPath)"
FSS_MOUNT_PATH=$(jq -r ".${PREFIX}fss_mount_path.value // \"/mnt/oci-fss\"" "$STATE_FILE")
echo "  host mount path: $FSS_MOUNT_PATH"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: fss-hostpath-reader
spec:
  restartPolicy: Never
  nodeName: ${FSS_WRITER_NODE}
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
  - key: amd.com/gpu
    operator: Exists
  containers:
  - name: reader
    image: busybox
    command: ["sh", "-c", "cat /mnt/fss-host/testfile.txt"]
    volumeMounts:
    - name: fss-host
      mountPath: /mnt/fss-host
  volumes:
  - name: fss-host
    hostPath:
      path: ${FSS_MOUNT_PATH}
      type: Directory
EOF
kubectl wait --for='jsonpath={.status.phase}=Succeeded' pod/fss-hostpath-reader --timeout=120s
HOST_CONTENT=$(kubectl logs fss-hostpath-reader)
if [[ "$HOST_CONTENT" != *"fss-test-content"* ]]; then
  echo "FAIL: FSS hostPath reader output does not contain expected content: $HOST_CONTENT"
  exit 1
fi
echo "OK:   FSS hostPath reader output: $HOST_CONTENT"
echo "Health check: all FSS health checks passed"
