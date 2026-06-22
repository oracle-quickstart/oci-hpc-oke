#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (C) SchedMD LLC.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Additional arguments to pass to slurmd.
export SLURMD_OPTIONS="${SLURMD_OPTIONS:-} $*"

# Additional arguments to pass to daemons.
export SSHD_OPTIONS="${SSHD_OPTIONS:-}"
export SSSD_OPTIONS="${SSSD_OPTIONS:-}"

# Ref: https://slurm.schedmd.com/pam_slurm_adopt.html#OPTIONS
export PAM_SLURM_ADOPT_OPTIONS="${PAM_SLURM_ADOPT_OPTIONS:-"action_adopt_failure=deny action_generic_failure=deny"}"

# The asserted CPU resource limit of the pod.
export POD_CPUS="${POD_CPUS:-0}"

# The asserted memory resource limit (in MiB) of the pod.
export POD_MEMORY="${POD_MEMORY:-0}"

# The asserted topology of the pod.
export POD_TOPOLOGY="${POD_TOPOLOGY:-}"

# calculateCoreSpecCount returns a value for CoreSpecCount for the pod.
#
# CoreSpecCount represents the number of cores that the slurmd/slurmstepd
# should not use. Effectively it is the difference of the host and the pod's
# resource limits. We have to convert CPUs to cores.
#
# Ref: https://slurm.schedmd.com/slurm.conf.html#OPT_CoreSpecCount
# Ref: https://slurm.schedmd.com/core_spec.html
function calculateCoreSpecCount() {
	local socketCount=0
	local coreCount=0
	local threadsPerCore=0
	local coreSpecCount=0

	socketCount="$(($(slurmd -C | grep -Eo "Boards=[0-9]+" | cut -d= -f2) * $(slurmd -C | grep -Eo "SocketsPerBoard=[0-9]+" | cut -d= -f2)))"
	coreCount="$((socketCount * $(slurmd -C | grep -Eo "CoresPerSocket=[0-9]+" | cut -d= -f2)))"
	threadsPerCore="$(slurmd -C | grep -Eo "ThreadsPerCore=[0-9]+" | cut -d= -f2)"
	coreSpecCount="$((coreCount - (POD_CPUS / threadsPerCore)))"

	if ((coreSpecCount > 0)); then
		echo "$coreSpecCount"
	else
		echo "0"
	fi
}

# calculateMemSpecLimit returns a value for MemSpecLimit for the pod.
#
# MemSpecLimit represents the amount of memory that the slurmd/slurmstepd
# cannot use. Effectively it is the difference of the host and the pod's
# resource limits. Memory is in MiB (mebibytes) to match Slurm's internal units.
#
# Ref: https://slurm.schedmd.com/slurm.conf.html#OPT_MemSpecLimit
function calculateMemSpecLimit() {
	local memSpecLimit=0
	local totalMemory=0

	totalMemory="$(slurmd -C | grep -Eo "RealMemory=[0-9]+" | cut -d= -f2)"
	memSpecLimit="$((totalMemory - POD_MEMORY))"

	if ((memSpecLimit > 0)); then
		echo "$memSpecLimit"
	else
		echo "0"
	fi
}

# addConfItem shims the item into SLURMD_OPTIONS.
#
# This function will add `--conf` if it is not present in SLURMD_OPTIONS,
# otherwise will add the item into the argument of `--conf`.
function addConfItem() {
	local item="$1"
	local slurmdOptions=()
	local foundConf=0
	readarray -t slurmdOptions < <(echo -n "$SLURMD_OPTIONS" | gawk -v FPAT="([^ ]+)|[^ ]*((\"[^\"]+\")|('[^']+'))" '{ for (i=1; i<=NF; i++) print $i }')
	for i in "${!slurmdOptions[@]}"; do
		case "${slurmdOptions[$i]}" in
		--conf=*)
			foundConf=1
			local val="${slurmdOptions[$i]#--conf=}"
			val="$(echo -n "$val" | sed -e 's/[\\]*"//g' -e "s/[\\]*'//g")"
			slurmdOptions[$i]="--conf='${val} ${item}'"
			;;
		--conf)
			foundConf=1
			local j="$((i + 1))"
			local val="${slurmdOptions[$j]}"
			val="$(echo -n "$val" | sed -e 's/[\\]*"//g' -e "s/[\\]*'//g")"
			slurmdOptions[$j]="'${val} ${item}'"
			;;
		*) ;;
		esac
	done
	if ((foundConf == 0)); then
		slurmdOptions+=("--conf")
		slurmdOptions+=("'${item}'")
	fi
	export SLURMD_OPTIONS="${slurmdOptions[*]}"
}

# configure_pam_slurm configures PAM to use pam_slurm_adopt for SSH sessions.
#
# This allows SSH access to be restricted to users with active jobs on the node.
# Ref: https://slurm.schedmd.com/pam_slurm_adopt.html#PAM_CONFIG
function configure_pam_slurm() {
	# Add pam_slurm_adopt to SSH PAM configuration if not already present
	if grep -q "pam_slurm_adopt.so" /etc/pam.d/sshd 2>/dev/null; then
		return
	fi
	# Insert pam_slurm_adopt BEFORE @include common-account
	# This is critical because common-account contains "sufficient pam_localuser.so"
	# which would short-circuit the PAM stack for local users, bypassing pam_slurm_adopt
	local search_line="@include[[:space:]]*common-account"
	local pam_slurm_adopt="account    required     pam_slurm_adopt.so"
	sed -i "s|^${search_line}|${pam_slurm_adopt} ${PAM_SLURM_ADOPT_OPTIONS}\n&|" /etc/pam.d/sshd
}

function main() {
	mkdir -p /run/slurm/
	mkdir -p /var/spool/slurmd/
	mkdir -p /run/sshd/
	chmod 0755 /run/sshd/
	mkdir -p /run/slurm/

	ssh-keygen -A
	configure_pam_slurm

	# Ref: https://slurm.schedmd.com/slurm.conf.html#OPT_CoreSpecCount
	local coreSpecCount=0
	if ((POD_CPUS > 0)); then
		coreSpecCount="$(calculateCoreSpecCount)"
	fi
	if ((coreSpecCount > 0)); then
		addConfItem "CoreSpecCount=${coreSpecCount}"
	fi

	# Ref: https://slurm.schedmd.com/slurm.conf.html#OPT_MemSpecLimit
	local memSpecLimit=0
	if ((POD_MEMORY > 0)); then
		memSpecLimit="$(calculateMemSpecLimit)"
	fi
	if ((memSpecLimit > 0)); then
		addConfItem "MemSpecLimit=${memSpecLimit}"
	fi

	# Ref: https://slurm.schedmd.com/topology.html#dynamic_topo
	if [ -n "$POD_TOPOLOGY" ]; then
		addConfItem "Topology=${POD_TOPOLOGY}"
	fi

	exec supervisord -c /etc/supervisor/supervisord.conf
}
main
