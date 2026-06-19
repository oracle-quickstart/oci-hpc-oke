#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (C) SchedMD LLC.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

NOTIFY_SOCKET="${NOTIFY_SOCKET:-"/tmp/fakesystemd.sock"}"
PIDFILE="${PIDFILE:-"/tmp/proxy.pid"}"

function log() {
	echo "[$(date --rfc-3339=seconds)] $(basename "$0"): $*"
}

function do_pidproxy() {
	log "start pidproxy: $PIDFILE"
	exec pidproxy "$PIDFILE" /usr/bin/sleep infinity
}

function main() {
	local notification
	local pid

	do_pidproxy &

	while true; do
		notification="$(socat -u "UNIX-RECVFROM:${NOTIFY_SOCKET},unlink-early" -)"
		pid="$(echo -e "$notification" | grep '^MAINPID=' | cut -d'=' -f2)"

		if [[ -z $pid ]]; then
			log "Notification lacks a MAINPID, skipping message."
			continue
		fi

		log "received PID=$pid"
		echo "$pid" >"$PIDFILE"
	done
}

main
