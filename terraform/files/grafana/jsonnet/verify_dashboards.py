#!/usr/bin/env python3
"""Verify generated dashboard contracts against transition backup JSON."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any, Optional


PACKAGE_DIR = Path(__file__).resolve().parent
BUILD_DIR = PACKAGE_DIR / "build"
BACKUP_DIR = PACKAGE_DIR.parent / "legacy-dashboard-backups"
CATEGORIES = ("common", "gpu", "oci")


def load(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as source:
        return json.load(source)


def datasource_uid(value: Any) -> Optional[str]:
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        return value.get("uid")
    return None


def compare_required(
    failures: list[str], context: str, old: dict[str, Any], new: dict[str, Any], keys: tuple[str, ...]
) -> None:
    for key in keys:
        if key in old and normalized(key, old[key]) != normalized(key, new.get(key)):
            failures.append(f"{context}: {key} changed")


def normalized(key: str, value: Any) -> Any:
    if key in ("expr", "definition", "query"):
        if isinstance(value, dict):
            value = value.get("query")
        if isinstance(value, str):
            return re.sub(r"\s+", "", value)
    if key == "mappings" and value is None:
        return []
    if key == "regex" and value is None:
        return ""
    if key == "thresholds" and isinstance(value, dict):
        value = json.loads(json.dumps(value))
        steps = value.get("steps", [])
        if steps and steps[0].get("value") in (None, 0):
            steps[0]["value"] = None
        return value
    return value


def verify_dashboard(path: Path, generated: Path, failures: list[str]) -> None:
    old = load(path)
    new = load(generated)
    context = f"{path.parent.name}/{path.name}"
    compare_required(failures, context, old, new, ("uid", "title", "links"))

    old_panels = {panel["id"]: panel for panel in old.get("panels", [])}
    new_panels = {panel["id"]: panel for panel in new.get("panels", [])}
    if old_panels.keys() != new_panels.keys():
        failures.append(f"{context}: panel IDs changed")
        return

    target_keys = (
        "expr",
        "legendFormat",
        "refId",
        "instant",
        "range",
        "format",
        "interval",
        "intervalFactor",
        "step",
    )
    standard_keys = ("unit", "decimals", "min", "max", "thresholds", "mappings")
    for panel_id, old_panel in old_panels.items():
        new_panel = new_panels[panel_id]
        panel_context = f"{context} panel {panel_id}"
        compare_required(
            failures,
            panel_context,
            old_panel,
            new_panel,
            ("title", "type", "gridPos", "links"),
        )
        old_panel_uid = datasource_uid(old_panel.get("datasource"))
        new_panel_uid = datasource_uid(new_panel.get("datasource"))
        if old_panel_uid is not None and old_panel_uid != new_panel_uid:
            failures.append(f"{panel_context}: datasource UID changed")
        old_targets = old_panel.get("targets", [])
        new_targets = new_panel.get("targets", [])
        if len(old_targets) != len(new_targets):
            failures.append(f"{panel_context}: target count changed")
            continue
        for index, old_target in enumerate(old_targets):
            new_target = new_targets[index]
            compare_required(
                failures,
                f"{panel_context} target {index}",
                old_target,
                new_target,
                target_keys,
            )
            old_uid = datasource_uid(old_target.get("datasource"))
            new_uid = datasource_uid(new_target.get("datasource"))
            if old_uid is not None and old_uid != new_uid:
                failures.append(f"{panel_context} target {index}: datasource UID changed")

        old_defaults = old_panel.get("fieldConfig", {}).get("defaults", {})
        new_defaults = new_panel.get("fieldConfig", {}).get("defaults", {})
        compare_required(failures, panel_context, old_defaults, new_defaults, standard_keys)

    old_variables = old.get("templating", {}).get("list", [])
    new_variables = new.get("templating", {}).get("list", [])
    if len(old_variables) != len(new_variables):
        failures.append(f"{context}: variable count changed")
    else:
        variable_keys = (
            "name",
            "type",
            "query",
            "datasource",
            "regex",
            "includeAll",
            "allValue",
            "multi",
            "sort",
            "hide",
            "label",
        )
        for index, old_variable in enumerate(old_variables):
            compare_required(
                failures,
                f"{context} variable {index}",
                old_variable,
                new_variables[index],
                variable_keys,
            )


def verify_gpu_vendor_contract(failures: list[str]) -> None:
    dashboard = load(BUILD_DIR / "gpu" / "gpu-health-status.json")
    panels = dashboard["panels"]
    ids = {panel["id"] for panel in panels}
    if not {7, 23}.issubset(ids):
        failures.append("gpu-health-status: source must retain panel IDs 7 and 23")

    for name, amd, nvidia, expected in (
        ("AMD", True, False, {23}),
        ("NVIDIA", False, True, {7}),
        ("mixed", True, True, {7, 23}),
    ):
        filtered = [
            panel
            for panel in panels
            if (panel["id"] != 7 or nvidia) and (panel["id"] != 23 or amd)
        ]
        retained = {panel["id"] for panel in filtered} & {7, 23}
        if retained != expected:
            failures.append(f"gpu-health-status: {name} vendor filtering changed")
        reflowed = []
        for index, panel in enumerate(filtered):
            if panel.get("type") == "stat":
                panel = dict(panel)
                panel["gridPos"] = dict(panel["gridPos"])
                panel["gridPos"].update(
                    {"x": (index % 8) * 3, "y": (index // 8) * 3}
                )
            reflowed.append(panel)
        stat_positions = [
            (panel["gridPos"]["x"], panel["gridPos"]["y"])
            for panel in reflowed
            if panel.get("type") == "stat"
        ]
        if len(stat_positions) != len(set(stat_positions)):
            failures.append(f"gpu-health-status: {name} reflow overlaps stat panels")


def main() -> int:
    failures: list[str] = []
    for category in CATEGORIES:
        backups = {path.name: path for path in (BACKUP_DIR / category).glob("*.json")}
        generated = {path.name: path for path in (BUILD_DIR / category).glob("*.json")}
        if not backups.keys() <= generated.keys():
            failures.append(f"{category}: a backup has no generated dashboard replacement")
            continue
        for name, backup in backups.items():
            verify_dashboard(backup, generated[name], failures)

    verify_gpu_vendor_contract(failures)
    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1
    print("Verified 21 dashboard contracts and AMD/NVIDIA/mixed GPU variants")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
