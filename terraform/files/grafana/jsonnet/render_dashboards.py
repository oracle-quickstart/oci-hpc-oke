#!/usr/bin/env python3
"""Compile OKE Grafonnet dashboards for Terraform or local development."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
from pathlib import Path


JSONNET_VERSION = "0.21.0"
JB_VERSION = "0.6.0"

JSONNET_ASSETS = {
    ("Darwin", "arm64"): ("go-jsonnet_Darwin_arm64.tar.gz", "398189a264e31a2c1316eed8ee6308306a221fd10b72f405def0100d295efeac"),
    ("Darwin", "x86_64"): ("go-jsonnet_Darwin_x86_64.tar.gz", "a6cee4b381d2319fa807d7a7bf8a4ecf2d0cca64e2bcd53eeaa575ce1f7689a4"),
    ("Linux", "arm64"): ("go-jsonnet_Linux_arm64.tar.gz", "4a263da605dbe2edb99529f495266211062fac476789f2119408bc223338f1d6"),
    ("Linux", "x86_64"): ("go-jsonnet_Linux_x86_64.tar.gz", "ad3181fde77726b02d17eb4e72687020bf2cb35b9336cdeaaca4783c7ff104f7"),
}

JB_ASSETS = {
    ("Darwin", "arm64"): ("jb-darwin-arm64", "5757d499f84123d8af0148030cf9c9c3921f96ea7b314d7b267ee1e5c338f181"),
    ("Darwin", "x86_64"): ("jb-darwin-amd64", "73262cfb5052d047044a8bbcf99ed1683bfb71e73f43042ab503c6fdfc9df054"),
    ("Linux", "arm64"): ("jb-linux-arm64", "19f2da64816137cd87a82dd963c752ff4b7c8701fc1ed7b979c356321dcf3f5a"),
    ("Linux", "x86_64"): ("jb-linux-amd64", "78e54afbbc3ff3e0942b1576b4992277df4f6beb64cddd58528a76f0cd70db54"),
}


def log(message: str) -> None:
    print(message, file=sys.stderr)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def download(url: str, destination: Path, expected_sha256: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and sha256_file(destination) == expected_sha256:
        return

    for attempt in range(1, 4):
        temporary = destination.with_suffix(destination.suffix + ".part")
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "oci-hpc-oke-grafonnet-renderer"})
            with urllib.request.urlopen(request, timeout=60) as response:
                with temporary.open("wb") as target:
                    shutil.copyfileobj(response, target)
            actual_sha256 = sha256_file(temporary)
            if actual_sha256 != expected_sha256:
                raise RuntimeError(
                    f"checksum mismatch for {url}: expected {expected_sha256}, got {actual_sha256}"
                )
            os.replace(temporary, destination)
            return
        except Exception:
            temporary.unlink(missing_ok=True)
            if attempt == 3:
                raise
            time.sleep(attempt)


def normalized_machine() -> str:
    machine = platform.machine().lower()
    return {"aarch64": "arm64", "amd64": "x86_64"}.get(machine, machine)


def ensure_tools(cache_dir: Path) -> tuple[Path, Path]:
    target = (platform.system(), normalized_machine())
    if target not in JSONNET_ASSETS or target not in JB_ASSETS:
        raise RuntimeError(f"unsupported Jsonnet build platform: {target[0]} {target[1]}")

    tools_dir = cache_dir / "tools"
    tools_dir.mkdir(parents=True, exist_ok=True)
    jsonnet_path = tools_dir / f"go-jsonnet-{JSONNET_VERSION}" / "jsonnet"
    jb_path = tools_dir / f"jb-{JB_VERSION}" / "jb"

    jsonnet_asset, jsonnet_sha256 = JSONNET_ASSETS[target]
    if not jsonnet_path.is_file():
        archive = tools_dir / "downloads" / jsonnet_asset
        download(
            f"https://github.com/google/go-jsonnet/releases/download/v{JSONNET_VERSION}/{jsonnet_asset}",
            archive,
            jsonnet_sha256,
        )
        extract_dir = jsonnet_path.parent
        temporary_dir = Path(tempfile.mkdtemp(prefix="jsonnet-extract-", dir=tools_dir))
        try:
            with tarfile.open(archive, "r:gz") as bundle:
                extraction_root = temporary_dir.resolve()
                for member in bundle.getmembers():
                    if member.issym() or member.islnk():
                        raise RuntimeError(f"unsafe link in Jsonnet archive: {member.name}")
                    member_path = (temporary_dir / member.name).resolve()
                    if os.path.commonpath((extraction_root, member_path)) != str(extraction_root):
                        raise RuntimeError(f"unsafe path in Jsonnet archive: {member.name}")
                bundle.extractall(temporary_dir)
            extract_dir.mkdir(parents=True, exist_ok=True)
            for binary in ("jsonnet", "jsonnetfmt"):
                shutil.copy2(temporary_dir / binary, extract_dir / binary)
                (extract_dir / binary).chmod((extract_dir / binary).stat().st_mode | stat.S_IXUSR)
        finally:
            shutil.rmtree(temporary_dir, ignore_errors=True)

    jb_asset, jb_sha256 = JB_ASSETS[target]
    if not jb_path.is_file():
        downloaded_jb = tools_dir / "downloads" / jb_asset
        download(
            f"https://github.com/jsonnet-bundler/jsonnet-bundler/releases/download/v{JB_VERSION}/{jb_asset}",
            downloaded_jb,
            jb_sha256,
        )
        jb_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(downloaded_jb, jb_path)
        jb_path.chmod(jb_path.stat().st_mode | stat.S_IXUSR)

    return jsonnet_path, jb_path


def dependency_hash(package_dir: Path) -> str:
    digest = hashlib.sha256()
    for filename in ("jsonnetfile.json", "jsonnetfile.lock.json"):
        digest.update(filename.encode())
        digest.update((package_dir / filename).read_bytes())
    return digest.hexdigest()


def ensure_dependencies(package_dir: Path, cache_dir: Path, jb_path: Path) -> Path:
    expected_hash = dependency_hash(package_dir)
    dependency_dir = cache_dir / "dependencies"
    vendor_dir = dependency_dir / "vendor"
    stamp = dependency_dir / ".dependency-hash"
    if vendor_dir.is_dir() and stamp.is_file() and stamp.read_text(encoding="utf-8").strip() == expected_hash:
        return vendor_dir

    temporary_dir = Path(tempfile.mkdtemp(prefix="jsonnet-dependencies-", dir=cache_dir))
    try:
        for filename in ("jsonnetfile.json", "jsonnetfile.lock.json"):
            shutil.copy2(package_dir / filename, temporary_dir / filename)
        subprocess.run([str(jb_path), "install"], cwd=temporary_dir, check=True)
        (temporary_dir / ".dependency-hash").write_text(expected_hash + "\n", encoding="utf-8")
        shutil.rmtree(dependency_dir, ignore_errors=True)
        os.replace(temporary_dir, dependency_dir)
    except Exception:
        shutil.rmtree(temporary_dir, ignore_errors=True)
        raise
    return vendor_dir


def source_hash(package_dir: Path) -> str:
    digest = hashlib.sha256()
    paths = [
        *sorted((package_dir / "dashboards").rglob("*.jsonnet")),
        *sorted((package_dir / "dashboards").rglob("*.libsonnet")),
        *sorted((package_dir / "lib").rglob("*.libsonnet")),
        package_dir / "jsonnetfile.json",
        package_dir / "jsonnetfile.lock.json",
        Path(__file__),
    ]
    for path in paths:
        digest.update(str(path.relative_to(package_dir)).encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def compile_dashboards(
    package_dir: Path, output_dir: Path, jsonnet_path: Path, vendor_dir: Path
) -> dict[str, dict[str, str]]:
    dashboard_dir = package_dir / "dashboards"
    sources = sorted(dashboard_dir.glob("*/*.jsonnet"))
    if not sources:
        raise RuntimeError(f"no dashboard sources found under {dashboard_dir}")

    temporary_dir = Path(tempfile.mkdtemp(prefix="grafana-render-", dir=output_dir.parent))
    dashboards: dict[str, dict[str, str]] = {}
    seen_names: set[str] = set()
    try:
        for source in sources:
            category = source.parent.name
            filename = source.with_suffix(".json").name
            if filename in seen_names:
                raise RuntimeError(f"duplicate dashboard output name: {filename}")
            seen_names.add(filename)
            destination = temporary_dir / category / filename
            destination.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(
                [str(jsonnet_path), "-J", str(vendor_dir), "--output-file", str(destination), str(source)],
                check=True,
            )
            with destination.open(encoding="utf-8") as rendered:
                json.load(rendered)
            dashboards.setdefault(category, {})[filename] = destination.read_text(encoding="utf-8")
        shutil.rmtree(output_dir, ignore_errors=True)
        os.replace(temporary_dir, output_dir)
    except Exception:
        shutil.rmtree(temporary_dir, ignore_errors=True)
        raise
    return dashboards


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--external", action="store_true")
    parser.add_argument("--bootstrap-only", action="store_true")
    parser.add_argument("--cache-dir", type=Path)
    parser.add_argument("--output-dir", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    package_dir = Path(__file__).resolve().parent
    query: dict[str, str] = json.load(sys.stdin) if args.external else {}
    cache_dir = (args.cache_dir or (Path(query["cache_dir"]) if query.get("cache_dir") else package_dir / ".cache")).resolve()
    output_dir = (args.output_dir or (Path(query["output_dir"]) if query.get("output_dir") else package_dir / "build")).resolve()
    cache_dir.mkdir(parents=True, exist_ok=True)
    output_dir.parent.mkdir(parents=True, exist_ok=True)

    log(f"Preparing Jsonnet {JSONNET_VERSION} and jb {JB_VERSION}")
    jsonnet_path, jb_path = ensure_tools(cache_dir)
    vendor_dir = ensure_dependencies(package_dir, cache_dir, jb_path)
    if args.bootstrap_only:
        print(f"Prepared Jsonnet {JSONNET_VERSION} and jb {JB_VERSION}")
        return 0
    dashboards = compile_dashboards(package_dir, output_dir, jsonnet_path, vendor_dir)
    rendered_count = sum(len(category) for category in dashboards.values())
    log(f"Compiled {rendered_count} dashboards into {output_dir}")

    if args.external:
        json.dump(
            {
                "build_dir": str(output_dir),
                "dashboards": json.dumps(dashboards, separators=(",", ":")),
                "source_hash": source_hash(package_dir),
                "tool_versions": f"jsonnet={JSONNET_VERSION},jb={JB_VERSION}",
            },
            sys.stdout,
            separators=(",", ":"),
        )
        sys.stdout.write("\n")
    else:
        print(f"Compiled {rendered_count} dashboards into {output_dir}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        log(f"Dashboard compilation failed: {error}")
        raise SystemExit(1) from error
