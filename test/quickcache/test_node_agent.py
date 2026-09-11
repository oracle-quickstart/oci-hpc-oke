import importlib.util
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


RUNTIME_PATH = (
    Path(__file__).resolve().parents[2] / "terraform/files/oci-quickcache/files"
)
sys.path.insert(0, str(RUNTIME_PATH))

fake_kubernetes = types.ModuleType("kubernetes")
fake_kubernetes.client = types.ModuleType("kubernetes.client")
fake_kubernetes.config = types.ModuleType("kubernetes.config")
fake_rest = types.ModuleType("kubernetes.client.rest")


class FakeApiException(Exception):
    pass


fake_rest.ApiException = FakeApiException
saved_modules = {
    name: sys.modules.get(name)
    for name in ("kubernetes", "kubernetes.client", "kubernetes.client.rest")
}
sys.modules["kubernetes"] = fake_kubernetes
sys.modules["kubernetes.client"] = fake_kubernetes.client
sys.modules["kubernetes.client.rest"] = fake_rest

SPEC = importlib.util.spec_from_file_location(
    "quickcache_node_agent", RUNTIME_PATH / "node_agent.py"
)
node_agent = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = node_agent
SPEC.loader.exec_module(node_agent)

for module_name, module in saved_modules.items():
    if module is None:
        sys.modules.pop(module_name, None)
    else:
        sys.modules[module_name] = module


class NodeAgentPathTests(unittest.TestCase):
    def test_host_path_symlink_cannot_escape_trusted_root(self):
        with tempfile.TemporaryDirectory() as directory:
            host_root = Path(directory)
            trusted = host_root / "var/lib/ociqc"
            outside = host_root / "outside"
            trusted.mkdir(parents=True)
            outside.mkdir()
            (trusted / "runtime").symlink_to(outside, target_is_directory=True)

            with self.assertRaisesRegex(ValueError, "real host path"):
                node_agent._validated_host_child_path(
                    "/var/lib/ociqc/runtime",
                    "/var/lib/ociqc",
                    "HOST_RUNTIME_ROOT",
                    str(host_root),
                )

    def test_host_paths_must_not_overlap(self):
        with self.assertRaisesRegex(ValueError, "must not overlap"):
            node_agent._reject_overlapping_paths(
                {
                    "HOST_RUNTIME_ROOT": "/var/lib/ociqc/runtime",
                    "HOST_CONFIG_ROOT": "/var/lib/ociqc/runtime/config",
                }
            )

    def test_symlinked_host_paths_are_compared_by_real_location(self):
        with tempfile.TemporaryDirectory() as directory:
            host_root = Path(directory)
            trusted = host_root / "var/lib/ociqc"
            runtime = trusted / "runtime"
            nested_config = runtime / "config"
            nested_config.mkdir(parents=True)
            (trusted / "config-link").symlink_to(
                nested_config,
                target_is_directory=True,
            )

            paths = {
                "HOST_RUNTIME_ROOT": node_agent._validated_host_child_path(
                    "/var/lib/ociqc/runtime",
                    "/var/lib/ociqc",
                    "HOST_RUNTIME_ROOT",
                    str(host_root),
                ),
                "HOST_CONFIG_ROOT": node_agent._validated_host_child_path(
                    "/var/lib/ociqc/config-link",
                    "/var/lib/ociqc",
                    "HOST_CONFIG_ROOT",
                    str(host_root),
                ),
            }
            with self.assertRaisesRegex(ValueError, "must not overlap"):
                node_agent._reject_overlapping_paths(paths)

    def test_client_mode_publishes_health_and_its_distinct_ready_label(self):
        core = SimpleNamespace(patch_node=mock.Mock())
        environment = {
            "NODE_MODE": "client",
            "QUICKCACHE_READY_LABEL": "client-ready",
            "HEARTBEAT_ANNOTATION": "heartbeat",
            "NODE_NAME": "client-a",
        }
        with mock.patch.dict(node_agent.os.environ, environment, clear=False):
            node_agent._patch_status(core, ready=True)

        core.patch_node.assert_called_once_with(
            "client-a",
            {
                "metadata": {
                    "annotations": {"heartbeat": mock.ANY},
                    "labels": {"client-ready": "true"},
                }
            },
        )

    def test_peer_probe_stats_the_exported_cache_directory(self):
        environment = {
            "PEER_PROBE_TIMEOUT": "7",
            "CACHE_DIR_NAME": "OCI_QC_Cache",
        }
        with (
            mock.patch.dict(node_agent.os.environ, environment, clear=False),
            mock.patch.object(node_agent, "_host_command") as host_command,
        ):
            node_agent._probe_peer("/var/lib/ociqc/mounts/uid-a")

        host_command.assert_called_once_with(
            [
                "stat",
                "-L",
                "-c",
                "%d",
                "/var/lib/ociqc/mounts/uid-a/OCI_QC_Cache",
            ],
            timeout=7,
        )

    def test_unreadable_stale_mount_is_lazily_unmounted(self):
        host_root = mock.Mock()
        host_root.exists.return_value = True
        stale_mount = mock.Mock()
        stale_mount.name = "stale-peer"
        stale_mount.is_dir.side_effect = OSError(5, "Input/output error")
        host_root.iterdir.return_value = [stale_mount]

        def path_factory(*parts):
            if parts == ("/host", "var/lib/ociqc/mounts"):
                return host_root
            return Path(*parts)

        environment = {"HOST_MOUNT_ROOT": "/var/lib/ociqc/mounts"}
        with (
            mock.patch.dict(node_agent.os.environ, environment, clear=False),
            mock.patch.object(node_agent, "Path", side_effect=path_factory),
            mock.patch.object(node_agent, "_host_command") as host_command,
        ):
            node_agent._remove_stale_mounts(set())

        host_command.assert_called_once_with(
            ["umount", "-l", "/var/lib/ociqc/mounts/stale-peer"], timeout=30
        )
        stale_mount.rmdir.assert_called_once_with()

    def test_shard_map_changes_are_appended_to_the_host_audit_log(self):
        environment = {
            "NODE_NAME": "worker-a",
            "NODE_MODE": "server",
            "HOST_LOG_ROOT": "/var/lib/ociqc/logs",
            "ACCESS_MODE": "trustedShared",
        }
        with tempfile.TemporaryDirectory() as directory:
            log_root = Path(directory, "var/lib/ociqc/logs")
            log_root.mkdir(parents=True)
            with mock.patch.dict(node_agent.os.environ, environment, clear=False):
                node_agent._audit_shard_map_change(
                    {"0": "/mounts/a", "1": "/mounts/a"},
                    {"0": "/mounts/a", "1": "/mounts/b", "2": "/mounts/b"},
                    directory,
                )

            record = json.loads(
                (log_root / "shard_map_audit.log").read_text(encoding="utf-8")
            )
            self.assertEqual(record["node"], "worker-a")
            self.assertEqual(record["added_shards"], 1)
            self.assertEqual(record["removed_shards"], 0)
            self.assertEqual(record["moved_shards"], 1)


if __name__ == "__main__":
    unittest.main()
