# /// script
# requires-python = ">=3.12"
# dependencies = ["kubernetes==31.0.0"]
# ///
"""Prepare QuickCache hosts and reconcile the full-mesh NFS mounts."""

from __future__ import annotations

import filecmp
import fcntl
import ipaddress
import json
import logging
import os
import re
import shlex
import shutil
import signal
import subprocess
import threading
import time
from decimal import Decimal, InvalidOperation
from pathlib import Path

from kubernetes import client, config
from kubernetes.client.rest import ApiException

from agent_common import (
    enter_host_namespaces as _enter_host_namespaces,
    read_configmap_json_objects,
    write_json_atomic as _write_json_atomic,
)
from sharding import resolve_shard_mounts


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
LOG = logging.getLogger("quickcache-node-agent")
HEALTH_FILE = Path("/tmp/health/alive")
READY_FILE = Path("/tmp/health/ready")
UID_RE = re.compile(r"^[a-f0-9-]{16,64}$")
STOP_EVENT = threading.Event()
MAX_COMMAND_OUTPUT_CHARS = 8192


def _validated_child_path(value: str, base: str, name: str) -> str:
    normalized = os.path.normpath(value)
    if not os.path.isabs(normalized) or normalized == base:
        raise ValueError(f"{name} must be an absolute child of {base}")
    try:
        if os.path.commonpath((normalized, base)) != base:
            raise ValueError(f"{name} must remain below {base}")
    except ValueError as exc:
        raise ValueError(f"{name} must remain below {base}") from exc
    return normalized


def _validated_host_child_path(
    value: str,
    base: str,
    name: str,
    host_root: str = "/host",
) -> str:
    """Reject host paths whose existing symlinks escape the trusted base."""
    normalized = _validated_child_path(value, base, name)
    root = Path(host_root).resolve()
    expected_base = root / base.lstrip("/")
    resolved_base = expected_base.resolve()
    resolved_path = (root / normalized.lstrip("/")).resolve()
    if resolved_base != expected_base or resolved_path == expected_base:
        raise ValueError(f"{name} must remain below the real host path {base}")
    try:
        if os.path.commonpath((resolved_path, expected_base)) != str(expected_base):
            raise ValueError(f"{name} must remain below the real host path {base}")
    except ValueError as exc:
        raise ValueError(f"{name} must remain below the real host path {base}") from exc
    return f"/{resolved_path.relative_to(root)}"


def _reject_overlapping_paths(paths: dict[str, str]) -> None:
    items = list(paths.items())
    for index, (first_name, first_path) in enumerate(items):
        for second_name, second_path in items[index + 1 :]:
            common = os.path.commonpath((first_path, second_path))
            if common in {first_path, second_path}:
                raise ValueError(f"{first_name} and {second_name} must not overlap")


def _validate_configuration() -> None:
    if _node_mode() == "server":
        _validated_child_path(
            os.environ["LOCAL_CACHE_PATH"], "/mnt/nvme", "LOCAL_CACHE_PATH"
        )
    host_paths = {
        name: _validated_host_child_path(os.environ[name], "/var/lib/ociqc", name)
        for name in (
            "HOST_MOUNT_ROOT",
            "HOST_RUNTIME_ROOT",
            "HOST_CONFIG_ROOT",
            "HOST_LOG_ROOT",
        )
    }
    _reject_overlapping_paths(host_paths)
    cache_name = os.environ["CACHE_DIR_NAME"]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", cache_name):
        raise ValueError("CACHE_DIR_NAME must be one safe path component")
    if os.environ["CACHE_PATH_LAYOUT"] not in {"friendly", "hashed"}:
        raise ValueError("CACHE_PATH_LAYOUT must be friendly or hashed")
    if os.environ["ACCESS_MODE"] not in {"trustedShared", "sharedGroup"}:
        raise ValueError("ACCESS_MODE must be trustedShared or sharedGroup")
    shared_gid = _parse_positive_integer(os.environ["SHARED_GID"], "SHARED_GID")
    if shared_gid > 2147483647:
        raise ValueError("SHARED_GID must be a valid Linux group ID")


def _node_mode() -> str:
    mode = os.environ.get("NODE_MODE", "server")
    if mode not in {"server", "client"}:
        raise ValueError("NODE_MODE must be server or client")
    return mode


def _host_command(
    args: list[str],
    timeout: int = 120,
    check: bool = True,
) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            args,
            check=check,
            capture_output=True,
            text=True,
            timeout=timeout,
            preexec_fn=_enter_host_namespaces,
        )
    except subprocess.CalledProcessError as exc:
        LOG.error(
            "host command failed: exit_code=%s command=%s\nstdout (tail):\n%s\nstderr (tail):\n%s",
            exc.returncode,
            shlex.join(args),
            _output_tail(exc.stdout),
            _output_tail(exc.stderr),
        )
        raise
    except subprocess.TimeoutExpired as exc:
        LOG.error(
            "host command timed out after %ss: command=%s\nstdout (tail):\n%s\nstderr (tail):\n%s",
            timeout,
            shlex.join(args),
            _output_tail(exc.stdout),
            _output_tail(exc.stderr),
        )
        raise


def _output_tail(output: str | bytes | None) -> str:
    if output is None:
        return "<empty>"
    if isinstance(output, bytes):
        output = output.decode("utf-8", errors="replace")
    output = output.rstrip()
    return output[-MAX_COMMAND_OUTPUT_CHARS:] if output else "<empty>"


def _parse_positive_integer(value: str, name: str) -> int:
    try:
        number = Decimal(value)
    except InvalidOperation as exc:
        raise ValueError(f"{name} must be a positive integer, got {value!r}") from exc

    if not number.is_finite() or number != number.to_integral_value() or number <= 0:
        raise ValueError(f"{name} must be a positive integer, got {value!r}")
    return int(number)


def _copy_runtime(host_runtime_root: str) -> None:
    destination = Path("/host", host_runtime_root.lstrip("/"))
    destination.mkdir(parents=True, exist_ok=True)
    for filename in (
        "sitecustomize.py",
        "cache_paths.py",
        "cleanup.py",
        "migrate_shards.py",
        "host_setup.sh",
        "host_teardown.sh",
    ):
        source = Path("/runtime", filename)
        target = destination / filename
        if (
            target.is_file()
            and not target.is_symlink()
            and filecmp.cmp(source, target, shallow=False)
        ):
            if filename in {"host_setup.sh", "host_teardown.sh"}:
                target.chmod(0o700)
            continue
        temporary = destination / f".{filename}.{os.getpid()}.tmp"
        try:
            shutil.copy2(source, temporary)
            if filename in {"host_setup.sh", "host_teardown.sh"}:
                temporary.chmod(0o700)
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)


def _read_host_json(host_path: str) -> dict:
    path = Path("/host", host_path.lstrip("/"))
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _audit_shard_map_change(
    old_map: dict,
    new_map: dict,
    host_root: str = "/host",
) -> None:
    """Persist one JSON audit record whenever this node's resolved map changes."""
    if old_map == new_map:
        return

    old_keys = set(old_map)
    new_keys = set(new_map)
    shared_keys = old_keys & new_keys
    record = {
        "timestamp_epoch": int(time.time()),
        "node": os.environ["NODE_NAME"],
        "node_mode": _node_mode(),
        "old_shards": len(old_map),
        "new_shards": len(new_map),
        "added_shards": len(new_keys - old_keys),
        "removed_shards": len(old_keys - new_keys),
        "moved_shards": sum(old_map[key] != new_map[key] for key in shared_keys),
    }
    path = Path(
        host_root,
        os.environ["HOST_LOG_ROOT"].lstrip("/"),
        "shard_map_audit.log",
    )
    file_mode = 0o660 if os.environ["ACCESS_MODE"] == "sharedGroup" else 0o666
    descriptor = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, file_mode)
    with os.fdopen(descriptor, "a", encoding="utf-8") as stream:
        fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
        stream.write(json.dumps(record, sort_keys=True) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
        fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def _run_host_setup(node_uid: str) -> None:
    env = {
        "LOCAL_CACHE_PATH": os.environ["LOCAL_CACHE_PATH"],
        "HOST_MOUNT_ROOT": os.environ["HOST_MOUNT_ROOT"],
        "HOST_RUNTIME_ROOT": os.environ["HOST_RUNTIME_ROOT"],
        "HOST_CONFIG_ROOT": os.environ["HOST_CONFIG_ROOT"],
        "HOST_LOG_ROOT": os.environ["HOST_LOG_ROOT"],
        "CACHE_DIR_NAME": os.environ["CACHE_DIR_NAME"],
        "ACCESS_MODE": os.environ["ACCESS_MODE"],
        "SHARED_GID": os.environ["SHARED_GID"],
        "NODE_MODE": _node_mode(),
        "NODE_UID": node_uid,
    }
    assignments = [f"{key}={value}" for key, value in env.items()]
    _host_command(
        ["env", *assignments, "/bin/bash", f"{env['HOST_RUNTIME_ROOT']}/host_setup.sh"],
        timeout=600,
    )


def _run_host_teardown() -> None:
    runtime_root = os.environ["HOST_RUNTIME_ROOT"]
    _host_command(
        [
            "env",
            f"HOST_MOUNT_ROOT={os.environ['HOST_MOUNT_ROOT']}",
            f"NODE_MODE={_node_mode()}",
            "/bin/bash",
            f"{runtime_root}/host_teardown.sh",
        ],
        timeout=120,
    )


def _probe_peer(mount_path: str) -> None:
    timeout = _parse_positive_integer(
        os.environ.get("PEER_PROBE_TIMEOUT", "5"), "PEER_PROBE_TIMEOUT"
    )
    cache_path = str(Path(mount_path, os.environ["CACHE_DIR_NAME"]))
    _host_command(
        ["stat", "-L", "-c", "%d", cache_path],
        timeout=timeout,
    )


def _mount_peer(uid: str, address: str) -> None:
    if not UID_RE.fullmatch(uid):
        raise ValueError(f"unsafe Node UID: {uid}")
    ipaddress.ip_address(address)
    mount_path = f"{os.environ['HOST_MOUNT_ROOT'].rstrip('/')}/{uid}"
    options = os.environ["NFS_OPTIONS"]
    source = f"[{address}]:/" if ":" in address else f"{address}:/"
    _host_command(["mkdir", "-p", mount_path])
    probe = _host_command(["mountpoint", "-q", mount_path], check=False, timeout=30)
    if probe.returncode == 0:
        current_source = _host_command(
            ["findmnt", "-n", "-o", "SOURCE", "--target", mount_path],
            timeout=30,
        ).stdout.strip()
        if current_source == source:
            try:
                _probe_peer(mount_path)
                return
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                LOG.warning("peer %s failed its I/O probe; remounting", uid)
        else:
            LOG.warning(
                "peer %s mount source changed from %s to %s; remounting",
                uid,
                current_source,
                source,
            )
        _host_command(["umount", "-l", mount_path], timeout=30)
    _host_command(
        ["mount", "-t", "nfs4", "-o", options, source, mount_path], timeout=60
    )
    _probe_peer(mount_path)


def _remove_stale_mounts(desired_uids: set[str]) -> None:
    host_root = Path("/host", os.environ["HOST_MOUNT_ROOT"].lstrip("/"))
    if not host_root.exists():
        return
    try:
        mount_paths = list(host_root.iterdir())
    except OSError as exc:
        LOG.warning("could not list peer mount root %s: %s", host_root, exc)
        return
    for path in mount_paths:
        # A desired peer is retained regardless of whether a transient NFS I/O
        # error prevents pathlib from statting its mount point.
        if path.name in desired_uids:
            continue
        try:
            if not path.is_dir():
                continue
        except OSError as exc:
            # A stale NFS mount can return EIO on stat. It must not prevent the
            # rest of reconciliation from publishing the node's ready status.
            LOG.warning(
                "could not inspect stale peer mount %s: %s; attempting lazy unmount",
                path.name,
                exc,
            )
        try:
            _host_command(
                ["umount", "-l", str(Path(os.environ["HOST_MOUNT_ROOT"], path.name))],
                timeout=30,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            LOG.warning("could not unmount stale peer %s", path.name)
            continue
        try:
            path.rmdir()
        except OSError:
            pass


def _read_state(core: client.CoreV1Api) -> tuple[dict, dict, dict, dict]:
    try:
        return read_configmap_json_objects(
            core,
            os.environ.get("STATE_CONFIGMAP_NAME", "oci-quickcache-state"),
            os.environ["POD_NAMESPACE"],
            "peers.json",
            "shard_map.json",
            "previous_shard_map.json",
            "rebalance.json",
        )
    except ApiException as exc:
        if exc.status == 404:
            return {}, {}, {}, {}
        raise


def _patch_status(
    core: client.CoreV1Api,
    ready: bool | None = None,
    heartbeat: bool = True,
) -> None:
    metadata: dict[str, dict[str, str]] = {}
    if heartbeat:
        metadata["annotations"] = {
            os.environ["HEARTBEAT_ANNOTATION"]: str(int(time.time()))
        }
    if ready is not None:
        metadata["labels"] = {
            os.environ["QUICKCACHE_READY_LABEL"]: "true" if ready else "false"
        }
    core.patch_node(
        os.environ["NODE_NAME"],
        {"metadata": metadata},
    )


def reconcile(core: client.CoreV1Api, node_uid: str) -> None:
    _copy_runtime(os.environ["HOST_RUNTIME_ROOT"])
    _run_host_setup(node_uid)
    # Server heartbeats allow shard ownership; client heartbeats allow the
    # controller to clear stale workload-ready labels without making clients
    # cache owners because membership still requires the server label.
    _patch_status(core)

    peers, shard_map, previous_shard_map, rebalance = _read_state(core)
    if (_node_mode() == "server" and node_uid not in peers) or not shard_map:
        raise RuntimeError(
            "waiting for the controller to publish this node's shard map"
        )
    desired_uids = set(peers)
    if _node_mode() == "server":
        desired_uids.add(node_uid)
    last_heartbeat = time.monotonic()
    heartbeat_interval = max(
        5,
        min(int(os.environ.get("RECONCILE_INTERVAL", "30")), 30),
    )
    for uid, peer in peers.items():
        if _node_mode() == "server" and uid == node_uid:
            continue
        _mount_peer(uid, peer["internalIP"])
        if time.monotonic() - last_heartbeat >= heartbeat_interval:
            _patch_status(core)
            last_heartbeat = time.monotonic()
    _remove_stale_mounts(desired_uids)

    workload_shard_map = resolve_shard_mounts(shard_map, peers)
    if len(workload_shard_map) != len(shard_map):
        raise RuntimeError("could not resolve every QuickCache shard to a peer mount")
    previous_workload_shard_map = resolve_shard_mounts(previous_shard_map, peers)
    if len(previous_workload_shard_map) != len(previous_shard_map):
        raise RuntimeError(
            "could not resolve every previous QuickCache shard to a peer mount"
        )

    config_root = os.environ["HOST_CONFIG_ROOT"].rstrip("/")
    old_workload_shard_map = _read_host_json(f"{config_root}/shard_map.json")
    _write_json_atomic(f"{config_root}/peers.json", peers)
    # Publish the fallback map first. A process that reloads between these two
    # atomic renames sees either the old active map or a usable fallback for
    # the new active map; it never sees the cutover without its fallback.
    _write_json_atomic(
        f"{config_root}/previous_shard_map.json", previous_workload_shard_map
    )
    _write_json_atomic(f"{config_root}/rebalance.json", rebalance)
    _write_json_atomic(f"{config_root}/shard_map.json", workload_shard_map)
    _audit_shard_map_change(old_workload_shard_map, workload_shard_map)
    _write_json_atomic(
        f"{config_root}/env.json",
        {
            "OCI_QC_SHARD_MAP_FILE": "/etc/ociqc/shard_map.json",
            "OCI_QC_PREVIOUS_SHARD_MAP_FILE": (
                "/etc/ociqc/previous_shard_map.json"
            ),
            "OCI_QC_CACHE_DIR_NAME": os.environ["CACHE_DIR_NAME"],
            "OCI_QC_CACHE_PATH_LAYOUT": os.environ["CACHE_PATH_LAYOUT"],
            "OCI_QC_LOG_DIR": "/var/log/ociqc",
            "OCI_QC_CACHE_DIRECTORY_MODE": (
                "2770" if os.environ["ACCESS_MODE"] == "sharedGroup" else "0777"
            ),
            "OCI_QC_LOG_FILE_MODE": (
                "0660" if os.environ["ACCESS_MODE"] == "sharedGroup" else "0666"
            ),
            "OCI_QC_MAX_CACHE_AGE": _parse_positive_integer(
                os.environ["CACHE_MAX_AGE"], "CACHE_MAX_AGE"
            ),
            "OCI_QC_MAP_RELOAD_INTERVAL": _parse_positive_integer(
                os.environ["MAP_RELOAD_INTERVAL"], "MAP_RELOAD_INTERVAL"
            ),
            "OCI_QC_CACHE_RANGE_GETS": os.environ["CACHE_RANGE_GETS"].lower() == "true",
        },
    )
    _patch_status(core, ready=True)


def _stop(*_args) -> None:
    STOP_EVENT.set()


def main() -> None:
    _validate_configuration()
    config.load_incluster_config()
    core = client.CoreV1Api()
    node = core.read_node(os.environ["NODE_NAME"])
    node_uid = str(node.metadata.uid)
    if not UID_RE.fullmatch(node_uid):
        raise RuntimeError(f"unexpected Kubernetes Node UID: {node_uid}")

    interval = int(os.environ.get("RECONCILE_INTERVAL", "30"))
    READY_FILE.unlink(missing_ok=True)
    # Package installation and the initial peer convergence can take several
    # minutes. Mark the process alive immediately so liveness does not restart
    # it while readiness continues to report initialization accurately.
    HEALTH_FILE.touch()
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    while not STOP_EVENT.is_set():
        try:
            reconcile(core, node_uid)
            HEALTH_FILE.touch()
            READY_FILE.touch()
        except Exception:
            READY_FILE.unlink(missing_ok=True)
            try:
                _patch_status(core, ready=False, heartbeat=False)
            except Exception:
                LOG.exception("could not clear the node workload-ready label")
            LOG.exception("node reconciliation failed")
        STOP_EVENT.wait(interval)
    try:
        _patch_status(core, ready=False, heartbeat=False)
    except Exception:
        LOG.exception("could not clear the node workload-ready label during shutdown")
    try:
        _run_host_teardown()
    except Exception:
        LOG.exception("could not tear down the node's QuickCache mounts and export")


if __name__ == "__main__":
    main()
