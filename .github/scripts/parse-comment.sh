#!/usr/bin/env bash
set -euo pipefail

cmd_line=$(echo "$COMMENT" | grep -oP "${1}.*" | head -1 || true)
read -ra words <<< "$cmd_line"
topology="${words[1]:-$3}"

# validate topology against $2 (split on |)
IFS='|' read -ra valid_topologies <<< "$2"
valid=false
for t in "${valid_topologies[@]}"; do
  if [[ "$topology" == "$t" ]]; then valid=true; break; fi
done
if [[ "$valid" != "true" ]]; then
  echo "Unsupported topology: $topology"
  exit 1
fi

overrides='{}'
for word in "${words[@]:2}"; do
  if [[ "$word" =~ ^[a-zA-Z_][a-zA-Z0-9_]*=.+$ ]]; then
    key="${word%%=*}"
    val="${word#*=}"
    overrides=$(jq -cn --argjson base "$overrides" --arg k "$key" --arg v "$val" '$base + {($k): $v}')
  fi
done

echo "topology=$topology" >> "$GITHUB_OUTPUT"
echo "overrides=$overrides" >> "$GITHUB_OUTPUT"
