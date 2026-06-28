# Slurm User Onboarding

This runbook creates a regular Slurm user on an OKE Slurm Operator cluster that
uses OpenLDAP, SSSD, FSS-backed home directories, and SlurmDBD accounting.

It was validated on a live test cluster with:

- OpenLDAP in the `identity` namespace;
- Slurm in the `slurm` namespace;
- `sshPublicKey` from the OpenSSH LPK schema for SSH key lookup;
- FSS mounted at `/home`;
- one ready Slurm worker pod.

LDAP SSH keys must use `sshPublicKey`, not `description`.

## Quick Start (script)

The [`slurm-add-user.sh`](./files/slurm-add-user.sh) script performs every step
in this runbook from a username and an SSH public key. Run it from the operator
node or another shell with `kubectl` access to the cluster.

```bash
curl -LO https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/docs/files/slurm-add-user.sh
chmod +x slurm-add-user.sh

# create user "alice" with the given public key, in the default "users" account
./slurm-add-user.sh alice --ssh-key-file ~/keys/alice.pub
```

The only required inputs are the `<username>` and one SSH key source
(`--ssh-key`, `--ssh-key-file`, or `--ssh-key-stdin`). The SSH key can be passed
inline with `--ssh-key "<key>"` or piped in with `--ssh-key-stdin`.

All of the following flags are optional:

- `--account <name>` (default `users`): the Slurm account / LDAP project group.
  The account and its project group are created automatically if they do not
  exist.
- `--full-name "<cn>"`: the `cn` for the LDAP entry (default: derived from the
  username).
- `--kube-context <ctx>`: the kubectl context to use. Defaults to your current
  kubectl context, so you only need this when your kubeconfig has multiple
  contexts and you must target a specific cluster.
- `--dry-run`: print the exact LDAP and Slurm changes without applying them.

The script:

- allocates the next free UID/GID and creates a per-user primary group;
- creates the LDAP user with `sshPublicKey` and adds it to the project group;
- creates the FSS-backed home directory with the correct ownership and mode;
- creates the SlurmDBD association;
- validates identity resolution on the controller and login pods (and on a
  worker, when one is ready), the SSH key actually served for the user, the home
  directory, and the Slurm association before exiting.

It is idempotent, so it is safe to re-run (for example to repair a
partially-created user or to rotate an SSH key). It exits non-zero if any
validation fails.

If the FSS home export uses root squash, the script cannot set home-directory
ownership from a pod. It stops before that step with a clear message; the LDAP
user and Slurm association are already created, so create
`/home/<username>` (owner `<uid>:<gid>`, mode `0700`) through the storage admin
path and re-run.

## How It Works / Manual Steps

The sections below document each step the script performs, for reference and as
a fallback when the script's assumptions do not hold. You do not need to run
them if you used the Quick Start above.

### 1. Set Variables

Run from the operator node or another shell with `kubectl` access.

```bash
export PATH=/home/ubuntu/bin:$PATH
export OCI_CLI_AUTH=instance_principal

export IDENTITY_NAMESPACE=identity
export SLURM_NAMESPACE=slurm
export OPENLDAP_POD=openldap-0
export OPENLDAP_CONTAINER=openldap-stack-ha
export LDAP_BASE='dc=example,dc=org'
export LDAP_PEOPLE_OU="ou=People,${LDAP_BASE}"
export LDAP_GROUPS_OU="ou=Groups,${LDAP_BASE}"
export LDAP_ADMIN_DN="cn=admin,${LDAP_BASE}"
export HOME_PVC=slurm-home

export LOGIN_SERVICE=slurm-login-slinky
export CONTROLLER_POD=slurm-controller-0
export CONTROLLER_CONTAINER=slurmctld
export LOGIN_CONTAINER=login
export WORKER_CONTAINER=slurmd
export SBATCH_PARTITION=cpu

export PROJECT=project-a
export PROJECT_GID=13001
export PROJECT_ORG=example

export USERNAME=alice
export USER_CN='Alice Slurm'
export USER_SN='Slurm'
export USER_UID=12001
export USER_GID=12001
export PRIMARY_GROUP=alice
export PRIMARY_GROUP_GID=12001
export LOGIN_SHELL=/bin/bash
export HOME_DIR=/home/alice
export SSH_PUBLIC_KEY='ssh-ed25519 AAAA_REPLACE_ME alice@example'

export LDAP_ADMIN_PASSWORD="$(
  kubectl -n "$IDENTITY_NAMESPACE" get secret openldap \
    -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' | base64 -d
)"
```

The stack generates unique OpenLDAP admin and `cn=config` passwords when they
are not supplied explicitly. They are available as sensitive Resource Manager
outputs (`slinky_openldap_admin_password` and
`slinky_openldap_config_password`). The admin password can also be retrieved
from the `openldap` Secret as shown above.

SSSD clients do not receive either administrator password. The stack creates a
separate `cn=sssd,ou=ServiceAccounts,<base DN>` account whose ACL permits LDAP
reads but denies writes and access to password attributes.

Use stable UID/GID allocation. Do not reuse IDs while old files may exist on
FSS, in backups, or in accounting history.

### 2. Define LDAP Helpers

These helpers run the Bitnami LDAP tools inside `openldap-0`, which avoids
requiring LDAP client tools on the operator host.

```bash
ldapsearch_primary() {
  kubectl -n "$IDENTITY_NAMESPACE" exec "$OPENLDAP_POD" -c "$OPENLDAP_CONTAINER" -- \
    /opt/bitnami/openldap/bin/ldapsearch \
      -x -H ldap://127.0.0.1:1389 \
      -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" "$@"
}

ldapadd_primary() {
  kubectl -n "$IDENTITY_NAMESPACE" exec -i "$OPENLDAP_POD" -c "$OPENLDAP_CONTAINER" -- \
    /opt/bitnami/openldap/bin/ldapadd \
      -x -H ldap://127.0.0.1:1389 \
      -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD"
}

ldapmodify_primary() {
  kubectl -n "$IDENTITY_NAMESPACE" exec -i "$OPENLDAP_POD" -c "$OPENLDAP_CONTAINER" -- \
    /opt/bitnami/openldap/bin/ldapmodify \
      -x -H ldap://127.0.0.1:1389 \
      -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD"
}

ldap_entry_exists() {
  ldapsearch_primary -LLL -b "$1" -s base dn >/dev/null 2>&1
}
```

### 3. Create the Project

Create the LDAP project group:

```bash
if ! ldap_entry_exists "cn=${PROJECT},${LDAP_GROUPS_OU}"; then
  printf '%s\n' \
    "dn: cn=${PROJECT},${LDAP_GROUPS_OU}" \
    'objectClass: top' \
    'objectClass: posixGroup' \
    "cn: ${PROJECT}" \
    "gidNumber: ${PROJECT_GID}" | ldapadd_primary
fi
```

Create the Slurm account:

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$CONTROLLER_POD" -c "$CONTROLLER_CONTAINER" -- \
  sacctmgr -nP show account "$PROJECT" format=Account | grep -qx "$PROJECT" || \
kubectl -n "$SLURM_NAMESPACE" exec "$CONTROLLER_POD" -c "$CONTROLLER_CONTAINER" -- \
  sacctmgr -i add account "$PROJECT" Organization="$PROJECT_ORG"
```

### 4. Create the LDAP User

Create the user's primary POSIX group:

```bash
if ! ldap_entry_exists "cn=${PRIMARY_GROUP},${LDAP_GROUPS_OU}"; then
  printf '%s\n' \
    "dn: cn=${PRIMARY_GROUP},${LDAP_GROUPS_OU}" \
    'objectClass: top' \
    'objectClass: posixGroup' \
    "cn: ${PRIMARY_GROUP}" \
    "gidNumber: ${PRIMARY_GROUP_GID}" \
    "memberUid: ${USERNAME}" | ldapadd_primary
fi
```

Create the LDAP user. The key pieces are `objectClass: ldapPublicKey` and
`sshPublicKey:`.

```bash
if ! ldap_entry_exists "uid=${USERNAME},${LDAP_PEOPLE_OU}"; then
  printf '%s\n' \
    "dn: uid=${USERNAME},${LDAP_PEOPLE_OU}" \
    'objectClass: top' \
    'objectClass: inetOrgPerson' \
    'objectClass: posixAccount' \
    'objectClass: shadowAccount' \
    'objectClass: ldapPublicKey' \
    "cn: ${USER_CN}" \
    "sn: ${USER_SN}" \
    "uid: ${USERNAME}" \
    "uidNumber: ${USER_UID}" \
    "gidNumber: ${USER_GID}" \
    "homeDirectory: ${HOME_DIR}" \
    "loginShell: ${LOGIN_SHELL}" \
    "sshPublicKey: ${SSH_PUBLIC_KEY}" | ldapadd_primary
fi
```

Add the user to the project group:

```bash
if ! ldapsearch_primary -LLL -b "cn=${PROJECT},${LDAP_GROUPS_OU}" memberUid \
  | grep -qx "memberUid: ${USERNAME}"; then
  printf '%s\n' \
    "dn: cn=${PROJECT},${LDAP_GROUPS_OU}" \
    'changetype: modify' \
    'add: memberUid' \
    "memberUid: ${USERNAME}" | ldapmodify_primary
fi
```

### 5. Create the Home Directory

Create or repair `/home/$USERNAME` on the FSS-backed home PVC:

```bash
kubectl -n "$SLURM_NAMESPACE" delete pod home-admin --ignore-not-found --wait=true

kubectl -n "$SLURM_NAMESPACE" run home-admin \
  --image=docker.io/library/ubuntu:24.04 \
  --restart=Never \
  --overrides="$(
    cat <<EOF
{"spec":{"containers":[{"name":"home-admin","image":"docker.io/library/ubuntu:24.04","command":["sleep","infinity"],"volumeMounts":[{"name":"home","mountPath":"/home"}]}],"volumes":[{"name":"home","persistentVolumeClaim":{"claimName":"${HOME_PVC}"}}]}}
EOF
  )"

kubectl -n "$SLURM_NAMESPACE" wait --for=condition=Ready pod/home-admin --timeout=120s
kubectl -n "$SLURM_NAMESPACE" exec home-admin -- install -d -m 0711 /home
kubectl -n "$SLURM_NAMESPACE" exec home-admin -- \
  install -d -o "$USER_UID" -g "$USER_GID" -m 0700 "$HOME_DIR"
kubectl -n "$SLURM_NAMESPACE" exec home-admin -- ls -ld /home "$HOME_DIR"
kubectl -n "$SLURM_NAMESPACE" delete pod home-admin --wait=true
```

If the FSS export uses root squash, create or repair ownership through the
storage administration path instead of a Kubernetes pod.

### 6. Create the Slurm Association

Create the SlurmDBD user association:

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$CONTROLLER_POD" -c "$CONTROLLER_CONTAINER" -- \
  sacctmgr -nP show assoc user="$USERNAME" account="$PROJECT" format=User,Account \
  | grep -qx "${USERNAME}|${PROJECT}" || \
kubectl -n "$SLURM_NAMESPACE" exec "$CONTROLLER_POD" -c "$CONTROLLER_CONTAINER" -- \
  sacctmgr -i add user name="$USERNAME" account="$PROJECT" defaultaccount="$PROJECT"
```

### 7. Validate

Find the login and worker pods:

```bash
export LOGIN_POD="$(
  kubectl -n "$SLURM_NAMESPACE" get pods -o name \
    | grep "^pod/${LOGIN_SERVICE}-" \
    | head -1 \
    | cut -d/ -f2
)"

export WORKER_POD="$(
  kubectl -n "$SLURM_NAMESPACE" get pods \
    -l app.kubernetes.io/name=slurmd,app.kubernetes.io/component=worker \
    -o jsonpath='{.items[0].metadata.name}'
)"
```

Clear SSSD cache if the image has `sss_cache`. Some Slinky images do not include
it; that is fine.

```bash
for target in \
  "$CONTROLLER_POD:$CONTROLLER_CONTAINER" \
  "$LOGIN_POD:$LOGIN_CONTAINER" \
  "$WORKER_POD:$WORKER_CONTAINER"
do
  pod="${target%%:*}"
  container="${target##*:}"
  kubectl -n "$SLURM_NAMESPACE" exec "$pod" -c "$container" -- \
    sh -lc 'command -v sss_cache >/dev/null 2>&1 && sss_cache -u "$1" || true' \
    sh "$USERNAME"
done
```

Check LDAP:

```bash
ldapsearch_primary -LLL -b "$LDAP_PEOPLE_OU" "(uid=${USERNAME})" \
  uid uidNumber gidNumber homeDirectory loginShell sshPublicKey

ldapsearch_primary -LLL -b "$LDAP_GROUPS_OU" "(memberUid=${USERNAME})" \
  cn gidNumber memberUid
```

Check controller, login, and worker identity resolution:

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$CONTROLLER_POD" -c "$CONTROLLER_CONTAINER" -- \
  getent passwd "$USERNAME"
kubectl -n "$SLURM_NAMESPACE" exec "$CONTROLLER_POD" -c "$CONTROLLER_CONTAINER" -- \
  id "$USERNAME"

kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  getent passwd "$USERNAME"
kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  id "$USERNAME"
kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  sss_ssh_authorizedkeys "$USERNAME"
kubectl -n "$SLURM_NAMESPACE" exec "$LOGIN_POD" -c "$LOGIN_CONTAINER" -- \
  ls -ld /home "$HOME_DIR"

kubectl -n "$SLURM_NAMESPACE" exec "$WORKER_POD" -c "$WORKER_CONTAINER" -- \
  getent passwd "$USERNAME"
kubectl -n "$SLURM_NAMESPACE" exec "$WORKER_POD" -c "$WORKER_CONTAINER" -- \
  id "$USERNAME"
```

Check the Slurm association:

```bash
kubectl -n "$SLURM_NAMESPACE" exec "$CONTROLLER_POD" -c "$CONTROLLER_CONTAINER" -- \
  sacctmgr -nP show assoc user="$USERNAME" format=User,Account,DefaultQOS,QOS
```

If there is no ready worker pod yet, stop here and run the job test after a CPU
or GPU worker pool exists.

### 8. Test SSH and Submit a Job

Set the private key that matches `SSH_PUBLIC_KEY`:

```bash
export SSH_PRIVATE_KEY=/path/to/private/key
export LOGIN_ADDR="$(
  kubectl -n "$SLURM_NAMESPACE" get svc "$LOGIN_SERVICE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
)"
```

Verify SSH login:

```bash
ssh -n -i "$SSH_PRIVATE_KEY" "${USERNAME}@${LOGIN_ADDR}" \
  'whoami; id; pwd; getent passwd "$USER"'
```

Submit a small Slurm job and wait for it to finish:

```bash
JOB="$(
  ssh -n -i "$SSH_PRIVATE_KEY" "${USERNAME}@${LOGIN_ADDR}" \
    "sbatch --parsable --wait --partition=${SBATCH_PARTITION} --account=${PROJECT} \
     --cpus-per-task=1 --time=00:05:00 --output=${HOME_DIR}/onboarding-test-%j.out \
     --wrap='whoami; id; pwd; hostname; touch \$HOME/onboarding-test-\$SLURM_JOB_ID'"
)"

ssh -n -i "$SSH_PRIVATE_KEY" "${USERNAME}@${LOGIN_ADDR}" \
  "sacct -j ${JOB} --format=JobID,User,Account,State,ExitCode,AllocTRES%80,NodeList -P"

ssh -n -i "$SSH_PRIVATE_KEY" "${USERNAME}@${LOGIN_ADDR}" \
  "cat ${HOME_DIR}/onboarding-test-${JOB}.out"
```

Expected result:

- `sss_ssh_authorizedkeys "$USERNAME"` returns the key from `sshPublicKey`.
- `id` shows the primary group and project group from LDAP.
- `/home/$USERNAME` is owned by the user's UID/GID and is mode `700`.
- Controller, login, and worker pods resolve the same UID/GID.
- `sacct` shows the top-level job row as `COMPLETED` for the expected user and
  account.
