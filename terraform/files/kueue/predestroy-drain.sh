#!/usr/bin/env bash
#
# Drain all Kueue custom resources before the Kueue Helm chart is uninstalled.
#
# The Kueue chart templates its CRDs (under templates/crd/), so "helm uninstall"
# deletes the CRDs and cascade-deletes every CR instance. An instance still
# carrying the kueue.x-k8s.io/resource-in-use finalizer cannot be cleared once
# the Kueue controller is gone, so the CRD deletion blocks and the uninstall
# hits its --wait timeout ("context deadline exceeded"), failing the destroy.
#
# This runs while the controller is still up: it deletes all Kueue CRs (including
# ad-hoc ones Terraform does not manage, such as test ResourceFlavors/Workloads)
# so the controller drains their finalizers, then force-clears any finalizers
# left behind (for example on a retried destroy where the controller is already
# gone). Best effort: every step tolerates errors so it never blocks the destroy.

set -uo pipefail

if ! kubectl get crd 2>/dev/null | grep -q 'kueue.x-k8s.io'; then
  echo "No Kueue CRDs present; nothing to drain."
  exit 0
fi

kinds=(
  workloads
  localqueues
  clusterqueues
  resourceflavors
  topologies
  admissionchecks
  cohorts
  multikueueconfigs
  workloadpriorityclasses
  provisioningrequestconfigs
)

# Pass 1: delete every instance while the controller can still remove the
# resource-in-use finalizers cleanly.
for k in "${kinds[@]}"; do
  kubectl delete "${k}.kueue.x-k8s.io" --all --all-namespaces \
    --ignore-not-found --timeout=60s 2>/dev/null || true
done

# Pass 2: anything still stuck (controller already gone) gets its finalizers
# stripped directly so the cascade can complete. namespace|name handles both
# cluster-scoped (empty namespace) and namespaced resources.
for k in "${kinds[@]}"; do
  while IFS='|' read -r ns name; do
    [ -z "${name:-}" ] && continue
    if [ -n "${ns:-}" ]; then
      kubectl patch "${k}.kueue.x-k8s.io" "$name" -n "$ns" \
        --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    else
      kubectl patch "${k}.kueue.x-k8s.io" "$name" \
        --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    fi
  done < <(kubectl get "${k}.kueue.x-k8s.io" -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"\n"}{end}' 2>/dev/null)
done

echo "Kueue CR drain complete."
exit 0
