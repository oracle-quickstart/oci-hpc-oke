# Adding SSH Public Keys to Worker Nodes

When you create worker nodes with the OCI Resource Manager stack, a single SSH public key is added by default. You may need to add additional SSH keys for team access, automation, or administrative purposes. This guide explains how to add multiple SSH keys to your worker nodes using Kubernetes resources.

## Prerequisites

- Access to your OKE cluster
- kubectl configured and authenticated
- SSH public keys that you want to add to the worker nodes

## Procedure

### Step 1: Create a ConfigMap for SSH Keys

Create a `ConfigMap` containing the SSH public keys you want to add to the worker nodes:

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

Apply the ConfigMap:

```sh
kubectl apply -f configmap.yaml
```

### Step 2: Deploy the DaemonSet

Deploy a `DaemonSet` to automatically distribute and manage the SSH keys across all worker nodes:

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

Apply the DaemonSet:

```sh
kubectl apply -f daemonset.yaml
```

The DaemonSet will automatically:
- Deploy a pod on each worker node
- Read SSH keys from the ConfigMap
- Update the `authorized_keys` file on each node at pod startup
- Work with both Ubuntu (user: `ubuntu`) and Oracle Linux (user: `opc`) nodes

> [!NOTE]
> The keys are applied when the DaemonSet pods start. To update keys after the initial deployment, you will need to restart the pods (see "Adding or Updating Keys" section below).

## Verification

To verify that the SSH keys have been successfully added:

1. Check that the DaemonSet pods are running on all nodes:

```sh
kubectl get pods -n kube-system -l app=authorized-ssh-keys -o wide
```

2. Check the logs of a DaemonSet pod to confirm key updates:

```sh
kubectl logs -n kube-system -l app=authorized-ssh-keys --tail=20
```

## Adding or Updating Keys

To add or update SSH keys after the initial deployment:

1. Edit the ConfigMap to add or modify keys:

```sh
kubectl edit configmap authorized-ssh-keys -n kube-system
```

2. Restart the DaemonSet pods to apply the changes:

```sh
kubectl rollout restart daemonset/authorized-ssh-keys -n kube-system
```

The pods will be restarted with a rolling update strategy, ensuring continuous availability while applying the new keys across all nodes.

## Removing Keys

To remove an SSH key:

1. Delete the key entry from the ConfigMap:

```sh
kubectl edit configmap authorized-ssh-keys -n kube-system
```

2. Remove the specific key line from the `data` section and save.

3. Restart the DaemonSet pods to apply the changes:

```sh
kubectl rollout restart daemonset/authorized-ssh-keys -n kube-system
```

The key will be removed from all worker nodes as the pods restart.
