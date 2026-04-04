# CI Workflow Hardening Plan

## Context

`issue_comment` triggered workflows read YAML from main, not the PR branch. Inline bash logic in workflow files can't be tested in PRs until merged -- we burned many CI runs debugging this. Additionally, an adversarial review found three security/design issues: concurrency group cancellation by unrelated comments, substring command matching, and secret exfiltration risk from external PRs.

## Goal

1. Extract inline bash from workflow YAML into scripts under `.github/scripts/` so they're testable from PR branches
2. Fix the three security issues from the adversarial review

## Scripts to Create (`.github/scripts/`)

| Script | Replaces | Used by |
|---|---|---|
| `parse-comment.sh` | Comment parsing (~25 lines x3) | ci-apply-tf, ci-apply-orm, ci-plan-orm |
| `setup-oci-credentials.sh` | OCI cred setup (~10 lines x6) | all 4 workflows |
| `build-variables-tf.sh` | TF var file building (~27 lines) | ci-apply-tf |
| `build-variables-orm.sh` | ORM var merging (~28 lines) | ci-apply-orm, ci-plan-orm, ci-plan |
| `create-orm-stack.py` | Python ORM stack creation (~30 lines x3) | ci-apply-orm, ci-plan-orm, ci-plan |
| `wait-for-orm-job.sh` | ORM job polling (~25 lines x3) | ci-apply-orm, ci-plan-orm, ci-plan |
| `assert-outputs.sh` | Output validation (~120 lines x2) | ci-apply-tf, ci-apply-orm |
| `generate-kubeconfig.sh` | Kubeconfig setup (~40 lines x2) | ci-apply-tf, ci-apply-orm |
| `check-cluster-health.sh` | Cluster health checks (~60 lines x2) | ci-apply-tf, ci-apply-orm |
| `check-network-health.sh` | Network health checks (~75 lines x2) | ci-apply-tf, ci-apply-orm |
| `check-gpu-health.sh` | GPU health checks (~28 lines x2) | ci-apply-tf, ci-apply-orm |
| `check-fss-health.sh` | FSS health checks (~130 lines x2) | ci-apply-tf, ci-apply-orm |
| `check-lustre-health.sh` | Lustre health checks (~140 lines x2) | ci-apply-tf, ci-apply-orm |
| `check-monitoring-health.sh` | Monitoring health checks (~45 lines x2) | ci-apply-tf, ci-apply-orm |
| `cleanup-test-resources.sh` | Test pod/PVC cleanup (~20 lines x2) | ci-apply-tf, ci-apply-orm |
| `teardown-bastion-tunnel.sh` | SSH tunnel teardown (~12 lines x2) | ci-apply-tf, ci-apply-orm |

### Script conventions

- `#!/usr/bin/env bash` + `set -euo pipefail`
- Receive data via env vars (already set in workflow `env:` blocks) and positional args
- Health check scripts take `$1` = state file, `$2` = state prefix ("" for TF, "outputs." for ORM)
- `parse-comment.sh` takes `$1` = command prefix, `$2` = pipe-separated valid topologies, `$3` = default topology

### What stays inline

- Simple 1-2 line commands (terraform init, pip install, ssh-keygen, zip)
- GitHub Actions `uses:` steps and `actions/github-script` blocks
- The terraform/ORM apply steps (AD retry loops are tightly coupled to the apply command)
- ci-release.yml (just dispatches other workflows)

## Security Fixes

### Fix 1: Concurrency cancellation (ci-plan-orm.yml)

Current (broken): all `issue_comment` events on a PR share one concurrency group with `cancel-in-progress: true`, so any comment cancels a running plan-orm job.

Fix: scope group to only match when the comment contains the trigger command AND is from an authorized user (matching ci-plan.yml pattern at lines 11-21):

```yaml
concurrency:
  group: >-
    ${{
      github.event_name == 'issue_comment' &&
      github.event.issue.pull_request &&
      contains(github.event.comment.body, '/ok-to-run-plan-orm') &&
      contains(fromJSON('["OguzPastirmaci","arnaudfroidmont","robo-cap"]'), github.event.comment.user.login) &&
      format('ci-plan-orm-pr-{0}', github.event.issue.number) ||
      github.event_name == 'workflow_dispatch' && format('ci-plan-orm-dispatch-{0}', inputs.topology) ||
      github.run_id
    }}
  cancel-in-progress: true
```

### Fix 2: Substring matching

Replace `contains()` with `startsWith()` in job `if:` conditions:

- ci-apply-tf.yml:67
- ci-apply-orm.yml:70
- ci-plan-orm.yml:64
- ci-plan.yml:40 (also lines 15-16 in concurrency)

### Fix 3: External PR fork check

Add a "Verify PR source is trusted" step in each `check-*-trigger` job, after the rocket reaction but before checkout. Uses `actions/github-script` to verify the PR is from the same repo or a trusted org. Fails the job if from an untrusted fork.

## Implementation Order

1. Create `.github/scripts/` with all 16 scripts (no workflow changes yet)
2. Run `shellcheck` on all scripts
3. Wire scripts into `ci-apply-tf.yml` (simplest apply workflow)
4. Wire scripts into `ci-apply-orm.yml`
5. Wire scripts into `ci-plan-orm.yml`
6. Wire scripts into `ci-plan.yml`
7. Apply all three security fixes across all workflows
8. Run `actionlint` on all workflow files
9. Open PR and test with `/ok-to-run-plan`

## Verification

- `shellcheck .github/scripts/*.sh`
- `actionlint .github/workflows/*.yml`
- Trigger `/ok-to-run-plan` on the PR -- this validates that scripts from the PR branch are used (since ci-plan.yml only has `issue_comment` trigger)
- Confirm workflow YAML line counts drop significantly (~1032 -> ~250 for ci-apply-tf.yml)

## Files Modified

- `.github/workflows/ci-apply-tf.yml`
- `.github/workflows/ci-apply-orm.yml`
- `.github/workflows/ci-plan-orm.yml`
- `.github/workflows/ci-plan.yml`
- `.github/scripts/` (16 new files)
