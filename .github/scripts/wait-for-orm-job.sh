#!/usr/bin/env bash
set -euo pipefail

# Wait for an ORM job to complete.
# Usage: wait-for-orm-job.sh <job-id> [max-polls] [interval-seconds]

JOB_ID="${1:?Usage: $0 <job-id> [max-polls] [interval-seconds]}"
MAX_POLLS="${2:-120}"
INTERVAL="${3:-30}"

echo "Waiting for ORM job $JOB_ID..."
POLL=0
while true; do
  POLL=$((POLL + 1))
  if [ "$POLL" -gt "$MAX_POLLS" ]; then
    echo "Timed out waiting for job after $MAX_POLLS polls"
    exit 1
  fi
  STATUS=$(oci resource-manager job get \
    --job-id "$JOB_ID" \
    --query 'data."lifecycle-state"' \
    --raw-output)
  echo "  [$POLL/$MAX_POLLS] Status: $STATUS"
  case "$STATUS" in
    SUCCEEDED) echo "Job succeeded."; break ;;
    FAILED|CANCELING|CANCELED)
      oci resource-manager job get-job-logs \
        --job-id "$JOB_ID" \
        --query 'data[*].message' --raw-output 2>/dev/null | tail -50 || true
      echo "Job failed with status: $STATUS"
      exit 1 ;;
  esac
  sleep "$INTERVAL"
done
