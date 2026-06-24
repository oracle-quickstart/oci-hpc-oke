#!/usr/bin/env bash
# Delete all Kueue CRs before "helm uninstall" so the CRD cascade does not hang
# on resource-in-use finalizers. Best effort: never blocks the destroy.

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
  multikueueclusters
  multikueueconfigs
  workloadpriorityclasses
  provisioningrequestconfigs
)

# Delete instances while the controller can still clear finalizers.
for k in "${kinds[@]}"; do
  kubectl delete "${k}.kueue.x-k8s.io" --all --all-namespaces \
    --ignore-not-found --timeout=60s 2>/dev/null || true
done

# Force-strip finalizers on anything still stuck (controller already gone).
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
