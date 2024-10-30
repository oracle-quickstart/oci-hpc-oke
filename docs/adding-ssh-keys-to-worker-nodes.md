### Adding SSH public keys to worker nodes
When you create worker nodes with the stack, it adds one SSH public key. If you need to add other SSH keys to the worker nodes, you can use the following manifest.

1 - Create a `ConfigMap` for the keys you want to add

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: authorized-ssh-keys
  namespace: kube-system
data:
  key1.pub: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC....'
  key2.pub: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD....'
```

2 - Use the below `DaemonSet` to add the keys in the ConfigMap to nodes.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: authorized-ssh-keys
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: authorized-ssh-keys
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 0
      maxUnavailable: 100%
  template:
    metadata:
      labels:
        app: authorized-ssh-keys
    spec:
      dnsPolicy: ClusterFirst
      hostNetwork: true
      priorityClassName: system-node-critical
      restartPolicy: Always
      terminationGracePeriodSeconds: 0
      tolerations: [{ operator: Exists }]
      volumes:
      - { name: root, hostPath: { path: / }}
      - { name: authorized-ssh-keys, configMap: { name: authorized-ssh-keys }}
      containers:
      - command:
        - /usr/bin/bash
        - -c
        - |
          set -e -o pipefail; trap 'exit=1; echo "Exit signal" >&2' SIGINT SIGTERM
          homepath=/host/home/ubuntu; if [[ ! -e /host/home/ubuntu ]]; then homepath=/host/home/opc; fi
          current=$(cat "$homepath"/.ssh/authorized_keys | sort -u)
          current_hash=$(echo "$current" | md5sum | awk '{print $1}')
          latest=$(awk 1 /authorized/*.pub | sort -u)
          latest_hash=$(echo "$latest" | md5sum | awk '{print $1}')
          keys=$(echo "$latest" | wc -l)
          if [[ $current_hash != $latest_hash ]] && [ "$keys" -gt 0 ]; then
            echo "$latest" > "$homepath"/.ssh/authorized_keys.tmp
            echo "$(date) Updating $keys keys ($current_hash -> $latest_hash)" >&2
            echo "$latest" | tee "$homepath"/.ssh/authorized_keys
          fi
          while :; do [[ "$exit" -gt 0 ]] && break; sleep 1; done
        image: oraclelinux:9
        name: authorized-ssh-keys
        resources:
          requests:
            cpu: 0m
            ephemeral-storage: 10Mi
            memory: 64Mi
          limits:
            cpu: 100m
            ephemeral-storage: 10Mi
            memory: 64Mi
        securityContext:
          privileged: true
        volumeMounts:
        - { name: root, mountPath: /host }
        - { name: authorized-ssh-keys, mountPath: /authorized }
```
