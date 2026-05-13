# Dirty Frag: CVE-2026-43284, CVE-2026-43500

Dirty Frag is a Linux kernel vulnerability chain involving flaws in the xfrm-ESP (IPsec) and RxRPC subsystems that enable unauthorized modification of page-cache-backed memory, allowing attackers to corrupt sensitive files and potentially achieve local privilege escalation through reliable, deterministic exploitation.

The vulnerabilities are triggered through two specific kernel modules:

- `esp4` / `esp6` — used in IPSec encapsulation
- `rxrpc` — used in AFS distributed filesystems

See [Dirty Frag][wiz-dirty-frag] for additional details.

## OKE

Currently there is no patch available for the OKE images.

To protect nodes in the OKE cluster, you can disable the vulnerable kernel modules running the following daemonset:

```
wget https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/docs/files/dirty-frag-mitigation-ds.yml
kubectl apply -f dirty-frag-mitigation-ds.yml

# Use this command to get the list of nodes where the patch was successful
kubectl get pods -n kube-system -l app=dirty-frag-patch \
  -o jsonpath='{range .items[?(@.status.initContainerStatuses[0].state.terminated.exitCode==0)]}{.spec.nodeName}{"\n"}{end}'

# Use this command to get the list of nodes where the patch failed
kubectl get pods -n kube-system -l app=dirty-frag-patch \
  -o custom-columns='NODE:.spec.nodeName,POD:.metadata.name,REASON:.status.initContainerStatuses[?(@.name=="patch")].state.terminated.reason,EXIT:.status.initContainerStatuses[?(@.name=="patch")].state.terminated.exitCode' \
  | awk '$4 != 0'
```

## Slurm

### Slurm V2

#### Existing nodes

To apply the mitigation on the existing nodes of the Slurm v2 cluster you can download and execute the `dirty-frag-mitigation-playbook.yml` ansible playbook:

```
wget https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/docs/files/dirty-frag-mitigation-playbook.yml
ansible-playbook -i /etc/ansible/hosts dirty-frag-mitigation-playbook.yml
```

#### New nodes

To apply the mitigation on the new nodes of the Slurm v2 cluster you can add the code below to the end of the `/opt/oci-hpc/playbooks/resize_add.yml` ansible playbook:

```
- hosts: compute_to_add
  become: true
  tasks:
    - name: Prevent vulnerable kernel modules from loading
      ansible.builtin.copy:
        dest: /etc/modprobe.d/dirtyfrag.conf
        owner: root
        group: root
        mode: "0644"
        content: |
          install esp4 /bin/false
          install esp6 /bin/false
          install rxrpc /bin/false

    - name: Read loaded kernel modules
      ansible.builtin.command:
        cmd: lsmod
      register: dirtyfrag_lsmod
      changed_when: false

    - name: Unload vulnerable kernel modules
      ansible.builtin.command:
        cmd: "rmmod {{ item }}"
      loop:
        - esp4
        - esp6
        - rxrpc
      when: dirtyfrag_lsmod.stdout is search('^' ~ item ~ '\\s')
      register: dirtyfrag_rmmod
      changed_when: dirtyfrag_rmmod.rc == 0
      failed_when: dirtyfrag_rmmod.rc != 0

    - name: Drop kernel caches
      ansible.builtin.shell:
        cmd: echo 3 > /proc/sys/vm/drop_caches
      changed_when: true

    - name: Report mitigation status
      ansible.builtin.debug:
        msg: Dirty-frag mitigation applied
```

### Slurm V3

#### Existing nodes

To apply the mitigation on the existing nodes of the Slurm v3 cluster you can download and execute the `dirty-frag-mitigation-playbook.yml` ansible playbook:

```
wget https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/docs/files/dirty-frag-mitigation-playbook.yml -O /config/playbooks/dirty-frag-mitigation-playbook.yml
ansible-playbook -i /etc/ansible/hosts /config/playbooks/dirty-frag-mitigation-playbook.yml

# use the command below to get the cluster names
mgmt clusters list

# use the command below to patch the nodes in each cluster
CLUSTER_NAME="cluster-name"
mgmt nodes reconfigure --fields cluster_name=$CLUSTER_NAME --action ansible --playbook dirty-frag-mitigation-playbook
```

#### New nodes

To apply the mitigation on the new nodes of the Slurm v3 cluster you can add the code below to the end of the `/config/playbooks/compute.yml` ansible playbook:

```
- hosts: localhost
  become: true
  tasks:
    - name: Prevent vulnerable kernel modules from loading
      ansible.builtin.copy:
        dest: /etc/modprobe.d/dirtyfrag.conf
        owner: root
        group: root
        mode: "0644"
        content: |
          install esp4 /bin/false
          install esp6 /bin/false
          install rxrpc /bin/false

    - name: Read loaded kernel modules
      ansible.builtin.command:
        cmd: lsmod
      register: dirtyfrag_lsmod
      changed_when: false

    - name: Unload vulnerable kernel modules
      ansible.builtin.command:
        cmd: "rmmod {{ item }}"
      loop:
        - esp4
        - esp6
        - rxrpc
      when: dirtyfrag_lsmod.stdout is search('^' ~ item ~ '\\s')
      register: dirtyfrag_rmmod
      changed_when: dirtyfrag_rmmod.rc == 0
      failed_when: dirtyfrag_rmmod.rc != 0

    - name: Drop kernel caches
      ansible.builtin.shell:
        cmd: echo 3 > /proc/sys/vm/drop_caches
      changed_when: true

    - name: Report mitigation status
      ansible.builtin.debug:
        msg: Dirty-frag mitigation applied
```

## References

- [Dirty Frag vulnerability overview][dirty-frag]

[dirty-frag]: https://orca.security/resources/blog/dirty-frag-linux-kernel-vulnerability/
[wiz-dirty-frag]: https://www.wiz.io/blog/dirty-frag-linux-kernel-local-privilege-escalation-via-esp-and-rxrpc
