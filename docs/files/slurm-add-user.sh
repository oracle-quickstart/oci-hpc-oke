#!/usr/bin/env bash
#
# slurm-add-user.sh - onboard a Slurm user (LDAP user, home dir, association)
# from a username + SSH public key, then validate. Idempotent.
#
# Run from the operator node or any shell with kubectl access to the cluster.
#
set -euo pipefail

# ---- defaults (override via env vars of the same name) ----
: "${IDENTITY_NAMESPACE:=identity}"
: "${SLURM_NAMESPACE:=slurm}"
: "${OPENLDAP_POD:=openldap-0}"
: "${OPENLDAP_CONTAINER:=openldap-stack-ha}"
: "${OPENLDAP_SECRET:=openldap}"
: "${LDAP_BASE:=dc=example,dc=org}"
: "${LDAP_URI:=ldap://127.0.0.1:1389}"
: "${HOME_PVC:=slurm-home}"
: "${HOME_ROOT:=/home}"
: "${HOME_IMAGE:=docker.io/library/ubuntu:24.04}"
: "${LOGIN_SERVICE:=slurm-login-slinky}"
: "${LOGIN_CONTAINER:=login}"
: "${CONTROLLER_POD:=slurm-controller-0}"
: "${CONTROLLER_CONTAINER:=slurmctld}"
: "${WORKER_CONTAINER:=slurmd}"
: "${DEFAULT_ACCOUNT:=users}"
: "${UID_MIN:=12000}"
# Project/account group GIDs live well above the user UID/GID range so a per-user
# group (gidNumber == uidNumber) never collides with a project group GID.
: "${PROJECT_GID_MIN:=100000}"
: "${LOGIN_SHELL:=/bin/bash}"

LDAP_PEOPLE_OU="ou=People,${LDAP_BASE}"
LDAP_GROUPS_OU="ou=Groups,${LDAP_BASE}"
LDAP_ADMIN_DN="cn=admin,${LDAP_BASE}"

readonly EXIT_USAGE=2 EXIT_PRECONDITION=3 EXIT_ROOT_SQUASH=4 EXIT_VALIDATION=5

# ---- logging ----
log()  { printf '==> %s\n' "$*" >&2; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
err()  { printf 'ERROR: %s\n' "$*" >&2; }

usage() {
  cat >&2 <<'USAGE'
Usage: slurm-add-user.sh <username> (--ssh-key <key> | --ssh-key-file <path> | --ssh-key-stdin) [options]

Options:
  --account <name>      Slurm account / LDAP project group (default: users)
  --full-name <string>  cn for the LDAP entry (default: derived from username)
  --kube-context <name> kubectl context (default: current)
  --dry-run             print intended changes without modifying anything
  -h, --help            show this help
USAGE
}

# ---- pure helpers ----
validate_username() { [[ "${1:-}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }

validate_ssh_key() {
  local key="${1:-}"
  [[ "$key" == *PRIVATE* ]] && return 1
  # structural check: <type> <base64 material (>= 40 chars)> [comment]
  [[ "$key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-[a-z0-9-]+)[[:space:]]+[A-Za-z0-9+/]{40,}=*([[:space:]].*)?$ ]] || return 1
  # when available, let ssh-keygen validate the key material authoritatively
  if command -v ssh-keygen >/dev/null 2>&1; then
    ssh-keygen -l -f <(printf '%s\n' "$key") >/dev/null 2>&1 || return 1
  fi
  return 0
}

derive_full_name() {
  local u="${1:-}"
  printf '%s%s' "$(printf '%s' "${u:0:1}" | tr '[:lower:]' '[:upper:]')" "${u:1}"
}

# next_free_id <floor>: read used numeric ids (one per line) on stdin,
# print the smallest integer >= floor not in the list.
next_free_id() {
  local floor="$1"
  awk -v floor="$floor" '
    /^[0-9]+$/ { used[$1]=1 }
    END { id=floor; while (used[id]) id++; print id }
  '
}

parse_args() {
  USERNAME=""; SSH_KEY=""; ACCOUNT="$DEFAULT_ACCOUNT"; FULL_NAME=""
  KUBE_CONTEXT=""; DRY_RUN=false
  local key_source="" key_file="" key_stdin=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --ssh-key) key_source="$2"; shift 2 ;;
      --ssh-key-file) key_file="$2"; shift 2 ;;
      --ssh-key-stdin) key_stdin=true; shift ;;
      --account) ACCOUNT="$2"; shift 2 ;;
      --full-name) FULL_NAME="$2"; shift 2 ;;
      --kube-context) KUBE_CONTEXT="$2"; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      -*) err "unknown option: $1"; usage; exit "$EXIT_USAGE" ;;
      *) if [[ -z "$USERNAME" ]]; then USERNAME="$1"; shift
         else err "unexpected argument: $1"; usage; exit "$EXIT_USAGE"; fi ;;
    esac
  done

  [[ -n "$USERNAME" ]] || { err "username is required"; usage; exit "$EXIT_USAGE"; }
  validate_username "$USERNAME" || { err "invalid username: $USERNAME"; exit "$EXIT_USAGE"; }

  if [[ -n "$key_source" ]]; then SSH_KEY="$key_source"
  elif [[ -n "$key_file" ]]; then SSH_KEY="$(cat "$key_file")"
  elif [[ "$key_stdin" == true ]]; then SSH_KEY="$(cat)"
  else err "an SSH key is required (--ssh-key / --ssh-key-file / --ssh-key-stdin)"; usage; exit "$EXIT_USAGE"; fi

  SSH_KEY="${SSH_KEY%%$'\n'*}"   # first line only
  validate_ssh_key "$SSH_KEY" || { err "value does not look like an SSH public key"; exit "$EXIT_USAGE"; }
  [[ -n "$FULL_NAME" ]] || FULL_NAME="$(derive_full_name "$USERNAME")"
}

# ---- cluster access wrappers ----
kc() { kubectl ${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"} "$@"; }

run() {
  if [[ "${DRY_RUN:-false}" == true ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

get_admin_password() {
  kc -n "$IDENTITY_NAMESPACE" get secret "$OPENLDAP_SECRET" \
    -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' | base64 -d
}

ldap_search() {
  # -o ldif-wrap=no keeps long values (e.g. sshPublicKey) on a single line so
  # callers can read them with a simple sed; default output folds at 76 columns.
  kc -n "$IDENTITY_NAMESPACE" exec "$OPENLDAP_POD" -c "$OPENLDAP_CONTAINER" -- \
    /opt/bitnami/openldap/bin/ldapsearch -x -H "$LDAP_URI" -o ldif-wrap=no \
    -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" "$@"
}

# ldap_add / ldap_modify read an LDIF on stdin. In dry-run they print the LDIF
# instead of applying it, so the preview shows exactly what would change.
ldap_add() {
  if [[ "${DRY_RUN:-false}" == true ]]; then
    { printf '[dry-run] ldapadd <<EOF\n'; cat; printf 'EOF\n'; }
    return 0
  fi
  kc -n "$IDENTITY_NAMESPACE" exec -i "$OPENLDAP_POD" -c "$OPENLDAP_CONTAINER" -- \
    /opt/bitnami/openldap/bin/ldapadd -x -H "$LDAP_URI" \
    -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD"
}

ldap_modify() {
  if [[ "${DRY_RUN:-false}" == true ]]; then
    { printf '[dry-run] ldapmodify <<EOF\n'; cat; printf 'EOF\n'; }
    return 0
  fi
  kc -n "$IDENTITY_NAMESPACE" exec -i "$OPENLDAP_POD" -c "$OPENLDAP_CONTAINER" -- \
    /opt/bitnami/openldap/bin/ldapmodify -x -H "$LDAP_URI" \
    -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD"
}

ldap_entry_exists() { ldap_search -LLL -b "$1" -s base dn >/dev/null 2>&1; }

slurm_ctl() {
  kc -n "$SLURM_NAMESPACE" exec "$CONTROLLER_POD" -c "$CONTROLLER_CONTAINER" -- "$@"
}

# print every numeric value of an LDAP attribute across an OU (one per line).
# Always returns 0 so it is safe inside command substitution under set -e.
ldap_attr_values() {
  local ou="$1" attr="$2"
  ldap_search -LLL -b "$ou" "($attr=*)" "$attr" 2>/dev/null \
    | awk -v a="$attr" 'tolower($1)==tolower(a":"){print $2}' || true
}

# print the max numeric value of an LDAP attribute across an OU, or empty.
ldap_max_attr() {
  ldap_attr_values "$1" "$2" | sort -n | tail -1 || true
}

# ---- steps ----
check_preconditions() {
  kc version --request-timeout=10s >/dev/null 2>&1 || {
    err "cannot reach the cluster with kubectl"; exit "$EXIT_PRECONDITION"; }
  kc -n "$IDENTITY_NAMESPACE" get pod "$OPENLDAP_POD" >/dev/null 2>&1 || {
    err "openldap pod $OPENLDAP_POD not found in $IDENTITY_NAMESPACE"; exit "$EXIT_PRECONDITION"; }
  kc -n "$SLURM_NAMESPACE" get pod "$CONTROLLER_POD" >/dev/null 2>&1 || {
    err "controller pod $CONTROLLER_POD not found in $SLURM_NAMESPACE"; exit "$EXIT_PRECONDITION"; }
}

ensure_account() {
  local account="$1" gid
  if ! ldap_entry_exists "cn=${account},${LDAP_GROUPS_OU}"; then
    gid="$( { ldap_max_attr "$LDAP_GROUPS_OU" gidNumber; printf '%s\n' "$((PROJECT_GID_MIN-1))"; } \
            | sort -n | tail -1 )"; gid=$((gid+1))
    (( gid < PROJECT_GID_MIN )) && gid="$PROJECT_GID_MIN"
    log "creating LDAP project group $account (gid $gid)"
    ldap_add <<EOF
dn: cn=${account},${LDAP_GROUPS_OU}
objectClass: top
objectClass: posixGroup
cn: ${account}
gidNumber: ${gid}
EOF
  fi
  if ! slurm_ctl sacctmgr -nP show account "$account" format=Account 2>/dev/null | grep -qx "$account"; then
    log "creating Slurm account $account"
    run slurm_ctl sacctmgr -i add account "$account" Organization="$account"
  fi
}

allocate_ids() {
  local username="$1" existing pg_gid
  existing="$(ldap_search -LLL -b "uid=${username},${LDAP_PEOPLE_OU}" -s base uidNumber gidNumber 2>/dev/null || true)"
  if [[ -n "$existing" ]]; then
    USER_UID="$(awk '/^uidNumber:/{print $2}' <<<"$existing")"
    USER_GID="$(awk '/^gidNumber:/{print $2}' <<<"$existing")"
    log "user $username exists; reusing uid=$USER_UID gid=$USER_GID"
    return 0
  fi
  # If a prior run already created this user's primary group but died before the
  # user entry, reuse the group's gidNumber so the repaired user matches it.
  pg_gid="$(ldap_search -LLL -b "cn=${username},${LDAP_GROUPS_OU}" -s base gidNumber 2>/dev/null \
            | awk '/^gidNumber:/{print $2}' | head -1 || true)"
  if [[ -n "$pg_gid" ]]; then
    USER_UID="$pg_gid"; USER_GID="$pg_gid"
    log "reusing existing primary group gid=$pg_gid for $username"
    return 0
  fi
  # Pick the next free id not used by any existing People uidNumber or Groups
  # gidNumber, so the per-user group (gid == uid) cannot collide with an existing
  # group (including project groups).
  USER_UID="$( { ldap_attr_values "$LDAP_PEOPLE_OU" uidNumber
                 ldap_attr_values "$LDAP_GROUPS_OU" gidNumber; } | next_free_id "$UID_MIN")"
  USER_GID="$USER_UID"
  log "allocated uid=$USER_UID gid=$USER_GID for $username"
}

create_ldap_user() {
  local username="$1" cur
  if ! ldap_entry_exists "cn=${username},${LDAP_GROUPS_OU}"; then
    log "creating primary group $username (gid $USER_GID)"
    ldap_add <<EOF
dn: cn=${username},${LDAP_GROUPS_OU}
objectClass: top
objectClass: posixGroup
cn: ${username}
gidNumber: ${USER_GID}
memberUid: ${username}
EOF
  fi
  if ! ldap_entry_exists "uid=${username},${LDAP_PEOPLE_OU}"; then
    log "creating LDAP user $username"
    ldap_add <<EOF
dn: uid=${username},${LDAP_PEOPLE_OU}
objectClass: top
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: ldapPublicKey
cn: ${FULL_NAME}
sn: ${FULL_NAME##* }
uid: ${username}
uidNumber: ${USER_UID}
gidNumber: ${USER_GID}
homeDirectory: ${HOME_ROOT}/${username}
loginShell: ${LOGIN_SHELL}
sshPublicKey: ${SSH_KEY}
EOF
  else
    cur="$(ldap_search -LLL -b "uid=${username},${LDAP_PEOPLE_OU}" -s base sshPublicKey 2>/dev/null \
           | sed -n 's/^sshPublicKey: //p' | head -1 || true)"
    if [[ "$cur" != "$SSH_KEY" ]]; then
      log "rotating sshPublicKey for $username"
      ldap_modify <<EOF
dn: uid=${username},${LDAP_PEOPLE_OU}
changetype: modify
replace: sshPublicKey
sshPublicKey: ${SSH_KEY}
EOF
    fi
  fi
  if ! ldap_search -LLL -b "cn=${ACCOUNT},${LDAP_GROUPS_OU}" memberUid 2>/dev/null \
       | grep -qx "memberUid: ${username}"; then
    log "adding $username to project group $ACCOUNT"
    ldap_modify <<EOF
dn: cn=${ACCOUNT},${LDAP_GROUPS_OU}
changetype: modify
add: memberUid
memberUid: ${username}
EOF
  fi
}

create_association() {
  local username="$1" account="$2"
  if ! slurm_ctl sacctmgr -nP show assoc user="$username" account="$account" format=User,Account 2>/dev/null \
       | grep -qx "${username}|${account}"; then
    log "creating Slurm association $username -> $account"
    run slurm_ctl sacctmgr -i add user name="$username" account="$account" defaultaccount="$account"
  fi
}

_home_admin_overrides() {
  cat <<EOF
{"spec":{"containers":[{"name":"home-admin","image":"${HOME_IMAGE}","command":["sleep","infinity"],"volumeMounts":[{"name":"home","mountPath":"${HOME_ROOT}"}]}],"volumes":[{"name":"home","persistentVolumeClaim":{"claimName":"${HOME_PVC}"}}]}}
EOF
}

_delete_home_admin() {
  kc -n "$SLURM_NAMESPACE" delete pod home-admin --ignore-not-found --wait=true >/dev/null 2>&1 || true
}

create_home_dir() {
  local username="$1"
  local target="${HOME_ROOT}/${username}"
  if [[ "${DRY_RUN:-false}" == true ]]; then
    printf '[dry-run] run home-admin pod (pvc=%s) and install -d -o %s -g %s -m 0700 %s\n' \
      "$HOME_PVC" "$USER_UID" "$USER_GID" "$target"
    return 0
  fi

  _delete_home_admin
  # Clean up the pod on any exit, including a set -e failure or the root-squash
  # exit below. A RETURN trap would not fire on exit, leaving the pod running.
  trap _delete_home_admin EXIT

  log "starting home-admin pod"
  kc -n "$SLURM_NAMESPACE" run home-admin --image="$HOME_IMAGE" --restart=Never \
     --overrides="$(_home_admin_overrides)" >/dev/null
  kc -n "$SLURM_NAMESPACE" wait --for=condition=Ready pod/home-admin --timeout=120s >/dev/null

  # If the home already exists with the right owner and mode, there is nothing to
  # do. This is what makes the root-squash recovery work: after the storage admin
  # creates the directory, a re-run detects it here and skips the probe below.
  if [[ "$(kc -n "$SLURM_NAMESPACE" exec home-admin -- stat -c '%u %g %a' "$target" 2>/dev/null)" \
        == "${USER_UID} ${USER_GID} 700" ]]; then
    log "home directory $target already present with correct ownership"
    trap - EXIT; _delete_home_admin
    return 0
  fi

  # root-squash probe: can root set ownership on the mounted FSS?
  if ! kc -n "$SLURM_NAMESPACE" exec home-admin -- \
       sh -c "install -d -o ${USER_UID} -g ${USER_GID} -m 0700 ${HOME_ROOT}/.squash-probe-$$ \
              && rmdir ${HOME_ROOT}/.squash-probe-$$" >/dev/null 2>&1; then
    err "cannot set ownership on $HOME_PVC (root squash?). Create $target with owner ${USER_UID}:${USER_GID} mode 0700 via the storage admin path, then re-run."
    exit "$EXIT_ROOT_SQUASH"
  fi

  kc -n "$SLURM_NAMESPACE" exec home-admin -- install -d -m 0711 "$HOME_ROOT"
  kc -n "$SLURM_NAMESPACE" exec home-admin -- \
     install -d -o "$USER_UID" -g "$USER_GID" -m 0700 "$target"
  kc -n "$SLURM_NAMESPACE" exec home-admin -- ls -ld "$target" >&2
  log "home directory $target ready"
  trap - EXIT; _delete_home_admin
}

# Print "<name> <Ready-status>" per pod so callers can pick a Ready one.
_pods_with_ready() {
  kc -n "$SLURM_NAMESPACE" get pods "$@" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null
}
# first Ready login pod, or empty
_login_pod() {
  _pods_with_ready | awk -v p="^${LOGIN_SERVICE}-" '$1 ~ p && $2=="True"{print $1; exit}'
}
# first Ready worker pod, or empty (a Pending/NotReady worker is skipped, not failed)
_worker_pod() {
  _pods_with_ready -l app.kubernetes.io/name=slurmd,app.kubernetes.io/component=worker \
    | awk '$2=="True"{print $1; exit}'
}

validate_user() {
  local username="$1" rc=0 login worker out t want
  login="$(_login_pod || true)"; worker="$(_worker_pod || true)"
  # the requested key without its comment field (type + base64 only)
  want="$(awk '{print $1" "$2}' <<<"$SSH_KEY")"

  _check() {  # _check <label> <cmd...>; pass if cmd succeeds AND stdout non-empty
    local label="$1"; shift
    if out="$("$@" 2>/dev/null)" && [[ -n "$out" ]]; then
      printf 'PASS - %s\n' "$label" >&2
    else
      printf 'FAIL - %s\n' "$label" >&2; rc=1
    fi
  }

  _check_contains() {  # _check_contains <label> <needle> <cmd...>; pass if cmd output contains needle
    local label="$1" needle="$2"; shift 2
    if out="$("$@" 2>/dev/null)" && grep -qF "$needle" <<<"$out"; then
      printf 'PASS - %s\n' "$label" >&2
    else
      printf 'FAIL - %s\n' "$label" >&2; rc=1
    fi
  }

  # clear SSSD cache where available
  for t in "$CONTROLLER_POD:$CONTROLLER_CONTAINER" "${login:+$login:$LOGIN_CONTAINER}" "${worker:+$worker:$WORKER_CONTAINER}"; do
    [[ -z "$t" ]] && continue
    kc -n "$SLURM_NAMESPACE" exec "${t%%:*}" -c "${t##*:}" -- \
      sh -c 'command -v sss_cache >/dev/null 2>&1 && sss_cache -u '"$username"' || true' >/dev/null 2>&1 || true
  done

  _check "controller resolves $username" \
    kc -n "$SLURM_NAMESPACE" exec "$CONTROLLER_POD" -c "$CONTROLLER_CONTAINER" -- getent passwd "$username"
  if [[ -n "$login" ]]; then
    _check "login resolves $username" \
      kc -n "$SLURM_NAMESPACE" exec "$login" -c "$LOGIN_CONTAINER" -- getent passwd "$username"
    _check_contains "login serves the requested ssh key" "$want" \
      kc -n "$SLURM_NAMESPACE" exec "$login" -c "$LOGIN_CONTAINER" -- sss_ssh_authorizedkeys "$username"
    _check "home dir present" \
      kc -n "$SLURM_NAMESPACE" exec "$login" -c "$LOGIN_CONTAINER" -- ls -ld "${HOME_ROOT}/${username}"
  else
    err "login pod not found ($LOGIN_SERVICE); cannot verify SSH access"; rc=1
  fi
  if [[ -n "$worker" ]]; then
    _check "worker resolves $username" \
      kc -n "$SLURM_NAMESPACE" exec "$worker" -c "$WORKER_CONTAINER" -- getent passwd "$username"
  else
    warn "no ready worker pod found; skipping worker check"
  fi
  _check "slurm association exists" \
    slurm_ctl sacctmgr -nP show assoc user="$username" account="$ACCOUNT" format=User,Account

  return "$rc"
}

main() {
  parse_args "$@"
  check_preconditions
  LDAP_ADMIN_PASSWORD="$(get_admin_password)"; export LDAP_ADMIN_PASSWORD
  log "onboarding user=$USERNAME account=$ACCOUNT dry-run=$DRY_RUN"
  ensure_account "$ACCOUNT"
  allocate_ids "$USERNAME"
  create_ldap_user "$USERNAME"
  create_association "$USERNAME" "$ACCOUNT"
  create_home_dir "$USERNAME"
  if [[ "$DRY_RUN" == true ]]; then
    log "dry-run complete; skipping validation"
    return 0
  fi
  log "validating"
  if validate_user "$USERNAME"; then
    log "SUCCESS: $USERNAME onboarded and validated"
  else
    err "validation reported failures for $USERNAME"
    exit "$EXIT_VALIDATION"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
