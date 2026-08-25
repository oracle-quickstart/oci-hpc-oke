# Slurm User Onboarding

Use this guide to add a regular user to an OKE Slurm cluster.

The onboarding script configures these services:

- OpenLDAP for the user identity and SSH public key
- SSSD for identity lookup
- File Storage Service (FSS) for the home directory
- SlurmDBD for the user account association

Root SSH access to the Slurm login service is disabled. Use a regular LDAP user for SSH access.

## Quick Start

Run these commands on the operator node. You can also use another host with `kubectl` access.

### 1. Download the Script

```bash
curl -LO https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/docs/files/slurm-add-user.sh

chmod +x slurm-add-user.sh
```

### 2. Add the User

Use this command format:

```bash
./slurm-add-user.sh "<USERNAME>" \
  --ssh-key-file "<PATH TO SSH PUBLIC KEY>"
```

For example:

```bash
./slurm-add-user.sh alice \
  --ssh-key-file /path/to/alice.pub
```

For a new user, the script creates the `users` association and makes it the default.

The script validates the user before it exits. A successful run ends with this message:

```text
SUCCESS: alice onboarded and validated
```

### 3. Test SSH Access

Get the login service IP:

```bash
kubectl -n slurm get service slurm-login-slinky \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}'
```

Connect as the new user:

```bash
ssh "alice@<login-service-ip>"
```

### 4. Submit a Test Job

Run these commands in the login pod:

```bash
JOB_ID="$(sbatch --parsable --wait \
  --nodes=1 \
  --ntasks=1 \
  --time=00:05:00 \
  --output="$HOME/onboarding-test-%j.out" \
  --wrap='whoami; id; pwd; hostname')"

sacct -j "$JOB_ID" \
  --format=JobID,User,Account,State,ExitCode,NodeList \
  --parsable2

cat "$HOME/onboarding-test-${JOB_ID}.out"
```

## Script Options

The script requires a username and one SSH key source.

| Option | Purpose |
| --- | --- |
| `--ssh-key "<key>"` | Read the public key from the command line. |
| `--ssh-key-file <path>` | Read the public key from a file. |
| `--ssh-key-stdin` | Read the public key from standard input. |
| `--account <name>` | Set the LDAP project group and Slurm account. The default is `users`. |
| `--full-name "<name>"` | Set the LDAP common name. The default comes from the username. |
| `--kube-context <context>` | Select a Kubernetes context. The current context is the default. |
| `--dry-run` | Show planned changes without changing the cluster. |

For example, add `alice` to the `research` account:

```bash
./slurm-add-user.sh alice \
  --ssh-key-file /path/to/alice.pub \
  --account research
```

If the association is new, the script makes `research` the user's default account.
If the association exists, the script leaves the current default account unchanged.

Specify `--account` in `sbatch` only when the user must select another valid account.

## What the Script Changes

The script performs these actions:

1. It checks the required namespaces, pods, secrets, and persistent volume claim.
2. It creates the LDAP project group when necessary.
3. It allocates the next available UID and GID.
4. It creates the LDAP user and primary group.
5. It stores the SSH key in the LDAP `sshPublicKey` attribute.
6. It creates the SlurmDBD user association.
7. It creates `/home/<username>` with mode `0700`.
8. It validates identity lookup, the SSH key, the home directory, and the Slurm association.

The script uses a Kubernetes Lease during UID and GID allocation. This prevents concurrent runs from selecting the same ID.

Run the script again if an earlier run stopped before completion.
The script also replaces the SSH public key.
It does not repair conflicting LDAP, Slurm, or home directory data.

## Verify an Existing User

Set the username:

```bash
export SLURM_USER=alice
```

Find the login pod:

```bash
LOGIN_POD="$(
  kubectl -n slurm get pods \
    -l app.kubernetes.io/name=login \
    -o jsonpath='{.items[0].metadata.name}'
)"
```

Check identity lookup, the SSH key, and the home directory:

```bash
kubectl -n slurm exec "$LOGIN_POD" -c login -- getent passwd "$SLURM_USER"
kubectl -n slurm exec "$LOGIN_POD" -c login -- sss_ssh_authorizedkeys "$SLURM_USER"
kubectl -n slurm exec "$LOGIN_POD" -c login -- ls -ld "/home/$SLURM_USER"
```

Check the Slurm association and default account:

```bash
kubectl -n slurm exec slurm-controller-0 -c slurmctld -- \
  sacctmgr -nP show user "$SLURM_USER" \
  format=User,DefaultAccount,AdminLevel
```

## Root-Squash Recovery

FSS can block ownership changes from Kubernetes pods. The script reports the required UID and GID when this occurs.

Create the directory through the storage administration path:

```text
Path:  /home/<username>
Owner: <uid>:<gid>
Mode:  0700
```

Run `slurm-add-user.sh` again after you create the directory. The script detects the correct directory and continues validation.

## Troubleshooting

### SSH Access Fails

Confirm that LDAP returns the expected public key:

```bash
kubectl -n slurm exec "$LOGIN_POD" -c login -- \
  sss_ssh_authorizedkeys "$SLURM_USER"
```

LDAP must store SSH keys in `sshPublicKey`. Do not store SSH keys in `description`.

### The Login Pod Cannot Resolve the User

Run the script again. It clears the SSSD cache when the image provides `sss_cache`.

You can also check the user directly:

```bash
kubectl -n slurm exec "$LOGIN_POD" -c login -- getent passwd "$SLURM_USER"
```

### Slurm Rejects the Account

Check the user's associations:

```bash
kubectl -n slurm exec slurm-controller-0 -c slurmctld -- \
  sacctmgr -nP show association user="$SLURM_USER" \
  format=User,Account,Cluster,Partition
```

Check the default account:

```bash
kubectl -n slurm exec slurm-controller-0 -c slurmctld -- \
  sacctmgr -nP show user "$SLURM_USER" format=User,DefaultAccount
```

### No Worker Pod Is Ready

The script skips worker validation when no worker pod is ready. Run the script again after a worker becomes ready.

## Security Notes

- The stack generates the OpenLDAP administrator passwords unless you supply them.
- Resource Manager outputs mark these passwords as sensitive.
- SSSD uses a separate read-only LDAP service account.
- The SSSD account cannot read password attributes.
- The login service accepts regular LDAP users only.
