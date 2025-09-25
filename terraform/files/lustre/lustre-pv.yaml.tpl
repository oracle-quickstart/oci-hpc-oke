---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: lustre-pv
spec:
  capacity:
    storage: ${lustre_storage_size}Ti
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  csi:
    driver: lustre.csi.oraclecloud.com
    volumeHandle: "${lustre_ip}@tcp:/${lustre_fs_name}"
    fsType: lustre
    volumeAttributes:
      setupLnet: "true"
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: oci.oraclecloud.com/lustre-client-configured
          operator: In
          values:
          - "true"