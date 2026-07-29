#!/usr/bin/env python3
"""Inventory supported and installed mobile runtimes without exposing host paths."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


UNSTABLE_RE = re.compile(r"\b(beta|preview|canary|rc|release candidate)\b", re.I)


def run(command: list[str], *, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        text=True,
        capture_output=True,
        check=False,
        env=env,
    )


def parse_android_config(worktree: Path) -> dict[str, int | None]:
    path = worktree / "android/app/build.gradle.kts"
    if not path.is_file():
        return {"min_sdk": None, "target_sdk": None, "compile_sdk": None}
    text = path.read_text(encoding="utf-8")

    def value(name: str) -> int | None:
        match = re.search(rf"\b{name}\s*=\s*(\d+)", text)
        return int(match.group(1)) if match else None

    return {
        "min_sdk": value("minSdk"),
        "target_sdk": value("targetSdk"),
        "compile_sdk": value("compileSdk"),
    }


def parse_ios_config(worktree: Path) -> dict[str, object]:
    path = worktree / "ios/CashuWallet.xcodeproj/project.pbxproj"
    if not path.is_file():
        return {"minimum_deployment_targets": []}
    values = sorted(
        {
            match.group(1)
            for match in re.finditer(
                r"IPHONEOS_DEPLOYMENT_TARGET\s*=\s*([0-9]+(?:\.[0-9]+)*)",
                path.read_text(encoding="utf-8"),
            )
        },
        key=version_key,
    )
    return {"minimum_deployment_targets": values}


def version_key(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", value))


def android_sdk_root() -> Path | None:
    for key in ("ANDROID_SDK_ROOT", "ANDROID_HOME"):
        value = os.environ.get(key)
        if value and Path(value).is_dir():
            return Path(value)
    default = Path.home() / "Library/Android/sdk"
    return default if default.is_dir() else None


def android_inventory(official_api: int | None) -> dict[str, object]:
    sdk = android_sdk_root()
    if sdk is None:
        return {
            "available": False,
            "error": "Android SDK not found.",
            "official_stable_api": official_api,
        }

    platform_apis = sorted(
        {
            int(match.group(1))
            for path in (sdk / "platforms").glob("android-*")
            if (match := re.fullmatch(r"android-(\d+)(?:\.\d+)?", path.name))
        }
    )
    images: list[dict[str, object]] = []
    image_root = sdk / "system-images"
    if image_root.is_dir():
        for api_dir in image_root.glob("android-*"):
            match = re.fullmatch(r"android-(\d+)(?:\.\d+)?", api_dir.name)
            if not match:
                continue
            for abi_dir in api_dir.glob("*/*"):
                if abi_dir.is_dir():
                    label = f"{api_dir.name}/{abi_dir.parent.name}/{abi_dir.name}"
                    images.append(
                        {
                            "api": int(match.group(1)),
                            "variant": abi_dir.parent.name,
                            "abi": abi_dir.name,
                            "stable_name": not bool(UNSTABLE_RE.search(label)),
                        }
                    )
    images.sort(key=lambda item: (int(item["api"]), str(item["variant"]), str(item["abi"])))
    stable_image_apis = sorted(
        {int(item["api"]) for item in images if bool(item["stable_name"])}
    )

    return {
        "available": True,
        "official_stable_api": official_api,
        "installed_platform_apis": platform_apis,
        "installed_system_images": images,
        "newest_installed_stable_image_api": stable_image_apis[-1]
        if stable_image_apis
        else None,
        "official_image_installed": official_api in stable_image_apis
        if official_api is not None
        else None,
    }


def ios_inventory(official_version: str | None) -> dict[str, object]:
    developer_dir = os.environ.get(
        "DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"
    )
    env = dict(os.environ)
    env["DEVELOPER_DIR"] = developer_dir

    xcode = run(["xcodebuild", "-version"], env=env)
    runtimes = run(["xcrun", "simctl", "list", "runtimes", "-j"], env=env)
    if xcode.returncode != 0 or runtimes.returncode != 0:
        message = (runtimes.stderr or xcode.stderr).strip().splitlines()
        return {
            "available": False,
            "error": message[-1] if message else "Xcode simulator inventory failed.",
            "official_stable_version": official_version,
        }

    data = json.loads(runtimes.stdout)
    installed: list[dict[str, object]] = []
    for item in data.get("runtimes", []):
        if not isinstance(item, dict):
            continue
        name = str(item.get("name", ""))
        if not name.lower().startswith("ios "):
            continue
        available = bool(item.get("isAvailable", True))
        version = str(item.get("version", ""))
        build = str(item.get("buildversion", ""))
        stable = available and not bool(UNSTABLE_RE.search(f"{name} {version} {build}"))
        installed.append(
            {
                "name": name,
                "version": version,
                "build": build,
                "available": available,
                "stable_name": stable,
            }
        )
    installed.sort(key=lambda item: version_key(str(item["version"])))
    stable_versions = [
        str(item["version"]) for item in installed if bool(item["stable_name"])
    ]
    xcode_lines = [line.strip() for line in xcode.stdout.splitlines() if line.strip()]

    return {
        "available": True,
        "official_stable_version": official_version,
        "xcode": {
            "version": xcode_lines[0].removeprefix("Xcode ")
            if xcode_lines
            else "",
            "build": xcode_lines[1].removeprefix("Build version ")
            if len(xcode_lines) > 1
            else "",
        },
        "installed_runtimes": installed,
        "newest_installed_stable_version": stable_versions[-1]
        if stable_versions
        else None,
        "official_runtime_installed": official_version in stable_versions
        if official_version is not None
        else None,
    }


def revision_support(
    label: str,
    worktree: Path,
    android_api: int | None,
    ios_version: str | None,
) -> dict[str, Any]:
    android = parse_android_config(worktree)
    ios = parse_ios_config(worktree)

    android_supported: bool | None = None
    if android_api is not None and android["min_sdk"] is not None:
        android_supported = android_api >= int(android["min_sdk"])

    ios_supported: bool | None = None
    targets = list(ios["minimum_deployment_targets"])
    if ios_version is not None and targets:
        ios_supported = version_key(ios_version) >= version_key(max(targets, key=version_key))

    return {
        "label": label,
        "android": {
            **android,
            "official_runtime_supported": android_supported,
        },
        "ios": {
            **ios,
            "official_runtime_supported": ios_supported,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--before-worktree", type=Path)
    parser.add_argument("--after-worktree", type=Path)
    parser.add_argument("--official-android-api", type=int)
    parser.add_argument("--official-ios-version")
    parser.add_argument("--compact", action="store_true")
    args = parser.parse_args()

    root = args.repo_root.resolve()
    revisions = [
        revision_support(
            "before" if args.before_worktree else "current",
            (args.before_worktree or root).resolve(),
            args.official_android_api,
            args.official_ios_version,
        )
    ]
    if args.after_worktree:
        revisions.append(
            revision_support(
                "after",
                args.after_worktree.resolve(),
                args.official_android_api,
                args.official_ios_version,
            )
        )

    result = {
        "policy": {
            "preview_allowed": False,
            "fallback_requires_explicit_approval": True,
            "pair_requires_exact_same_runtime_build": True,
        },
        "revisions": revisions,
        "android": android_inventory(args.official_android_api),
        "ios": ios_inventory(args.official_ios_version),
    }
    print(
        json.dumps(
            result,
            indent=None if args.compact else 2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
