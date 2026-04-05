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

echo "Health check: Lustre OS-level mount (fs type + hostPath write+read)"
LUSTRE_MOUNT_PATH=$(jq -r ".${PREFIX}lustre_mount_path.value // \"/mnt/oci-lustre\"" "$STATE_FILE")
echo "  host mount path: $LUSTRE_MOUNT_PATH"
# Verify the path is actually a Lustre mount, then write and read via it.
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
    command: ["sh", "-c"]
    args:
    - |
      FS_TYPE_NAME="\$(df -T /mnt/lustre-host 2>/dev/null | tail -1 | awk '{print \$2}')"
      FS_TYPE_HEX_RAW="\$(stat -f -c %t /mnt/lustre-host 2>/dev/null || echo unknown)"
      FS_TYPE_HEX="\${FS_TYPE_HEX_RAW#0x}"
      FS_TYPE_HEX="\${FS_TYPE_HEX#0X}"
      FS_TYPE_HEX_LC="\$(printf '%s' "\${FS_TYPE_HEX}" | tr 'A-F' 'a-f')"
      FS_TYPE_HEX_CANON="\${FS_TYPE_HEX_LC}"
      if [ "\${#FS_TYPE_HEX_CANON}" -eq 7 ]; then
        FS_TYPE_HEX_CANON="0\${FS_TYPE_HEX_CANON}"
      fi
      echo "fs_type=\${FS_TYPE_NAME:-none}"
      echo "fs_magic=0x\${FS_TYPE_HEX_CANON}"
      if [ "\${FS_TYPE_NAME:-none}" != "lustre" ] && [ "\${FS_TYPE_HEX_CANON}" != "0bd00bd0" ]; then
        echo "FAIL: expected Lustre filesystem (type=lustre or magic=0x0bd00bd0), got type=\${FS_TYPE_NAME:-none} magic=0x\${FS_TYPE_HEX_CANON}"
        exit 1
      fi
      echo 'hostpath-test-content' > /mnt/lustre-host/hostpath-testfile.txt
      sync
      cat /mnt/lustre-host/hostpath-testfile.txt
    volumeMounts:
    - name: lustre-host
      mountPath: /mnt/lustre-host
  volumes:
  - name: lustre-host
    hostPath:
      path: ${LUSTRE_MOUNT_PATH}
      type: Directory
EOF
if ! kubectl wait --for='jsonpath={.status.phase}=Succeeded' pod/lustre-hostpath-reader --timeout=120s; then
  echo "FAIL: timed out waiting for pod/lustre-hostpath-reader to reach Succeeded"
  kubectl get pod lustre-hostpath-reader -o wide || true
  kubectl describe pod lustre-hostpath-reader || true
  kubectl logs lustre-hostpath-reader || true
  exit 1
fi
HOST_CONTENT=$(kubectl logs lustre-hostpath-reader)
if [[ "$HOST_CONTENT" != *"fs_type=lustre"* && "$HOST_CONTENT" != *"fs_magic=0x0bd00bd0"* && "$HOST_CONTENT" != *"fs_magic=0x0BD00BD0"* ]]; then
  echo "FAIL: hostPath is not backed by Lustre filesystem:"
  echo "$HOST_CONTENT"
  exit 1
fi
if [[ "$HOST_CONTENT" != *"hostpath-test-content"* ]]; then
  echo "FAIL: Lustre hostPath output does not contain expected content: $HOST_CONTENT"
  exit 1
fi
echo "OK:   Lustre hostPath filesystem type verified and content correct"
echo "Health check: all Lustre health checks passed"
