#!/usr/bin/env python3
"""Route a committed Git diff to Android, iOS, both, or no app build."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


ANDROID_TEST_PREFIXES = (
    "android/app/src/test/",
    "android/app/src/androidTest/",
    "android/app/src/testFixtures/",
    "android/macrobenchmark/",
)
IOS_TEST_PREFIXES = (
    "ios/CashuWalletTests/",
    "ios/CashuWalletUITests/",
)
NON_COMPILED_SUFFIXES = (".md", ".adoc", ".txt")
ANDROID_NON_INPUT_PREFIXES = (
    "android/docs/",
    "android/screenshots/",
    "android/app/release/",
)
IOS_NON_INPUT_PREFIXES = (
    "ios/docs/",
    "ios/screenshots/",
)
ANDROID_DIRECT_PREFIXES = (
    "android/app/src/main/java/com/cashu/me/ui/",
    "android/app/src/main/java/com/cashu/me/Views/",
    "android/app/src/main/res/",
    "android/app/src/debug/res/",
)
IOS_DIRECT_PREFIXES = (
    "ios/CashuWallet/Views/",
    "ios/CashuWallet/Resources/",
)
ANDROID_RUNTIME_PATH_RE = re.compile(
    r"(?:^|/)(?:values|drawable|mipmap)-v\d+(?:/|$)"
)
ANDROID_RUNTIME_DIFF_RE = re.compile(
    r"\b(?:Build\.VERSION|VERSION_CODES|RequiresApi|ChecksSdkIntAtLeast|"
    r"minSdk|targetSdk|compileSdk)\b"
)
IOS_RUNTIME_DIFF_RE = re.compile(
    r"(?:#available|@available|IPHONEOS_DEPLOYMENT_TARGET|"
    r"MinimumOSVersion|LiquidGlass|SDKROOT)"
)


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=check,
        text=True,
        capture_output=True,
    )


def resolve_commit(repo: Path, value: str, label: str) -> str:
    result = git(repo, "rev-parse", "--verify", f"{value}^{{commit}}", check=False)
    if result.returncode != 0:
        raise ValueError(f"cannot resolve {label} revision: {value}")
    return result.stdout.strip()


def changed_files(repo: Path, before: str, after: str) -> list[str]:
    result = subprocess.run(
        [
            "git",
            "-C",
            str(repo),
            "diff",
            "--name-only",
            "-z",
            "--diff-filter=ACDMRTUXB",
            before,
            after,
        ],
        check=True,
        capture_output=True,
    )
    return sorted(
        {
            item.decode("utf-8", "surrogateescape")
            for item in result.stdout.split(b"\0")
            if item
        }
    )


def focused_diff(repo: Path, before: str, after: str, paths: list[str]) -> str:
    if not paths:
        return ""
    result = git(
        repo,
        "diff",
        "--no-ext-diff",
        "--unified=0",
        before,
        after,
        "--",
        *paths,
        check=False,
    )
    return result.stdout if result.returncode == 0 else ""


def is_android_app_path(path: str) -> bool:
    if (
        any(path.startswith(prefix) for prefix in ANDROID_TEST_PREFIXES)
        or any(path.startswith(prefix) for prefix in ANDROID_NON_INPUT_PREFIXES)
        or path.lower().endswith(NON_COMPILED_SUFFIXES)
    ):
        return False
    return path.startswith("android/")


def is_ios_app_path(path: str) -> bool:
    if (
        any(path.startswith(prefix) for prefix in IOS_TEST_PREFIXES)
        or any(path.startswith(prefix) for prefix in IOS_NON_INPUT_PREFIXES)
        or path.lower().endswith(NON_COMPILED_SUFFIXES)
    ):
        return False
    return path.startswith("ios/")


def is_android_direct(path: str) -> bool:
    return (
        any(path.startswith(prefix) for prefix in ANDROID_DIRECT_PREFIXES)
        or path.endswith("AndroidManifest.xml")
    )


def is_ios_direct(path: str) -> bool:
    return (
        any(path.startswith(prefix) for prefix in IOS_DIRECT_PREFIXES)
        or path.endswith("Info.plist")
    )


def route(repo: Path, before: str, after: str) -> dict[str, object]:
    files = changed_files(repo, before, after)
    android_files = [path for path in files if is_android_app_path(path)]
    ios_files = [path for path in files if is_ios_app_path(path)]
    routed = set(android_files + ios_files)
    non_app_files = [path for path in files if path not in routed]

    platforms: list[str] = []
    impact: dict[str, str] = {}
    reasons: dict[str, str] = {}

    if android_files:
        platforms.append("android")
        direct = any(is_android_direct(path) for path in android_files)
        impact["android"] = "direct" if direct else "indirect"
        reasons["android"] = (
            "Android views/resources/manifests changed."
            if direct
            else "Compiled Android app code or build inputs changed; trace state to its nearest surface."
        )

    if ios_files:
        platforms.append("ios")
        direct = any(is_ios_direct(path) for path in ios_files)
        impact["ios"] = "direct" if direct else "indirect"
        reasons["ios"] = (
            "iOS views/resources/application metadata changed."
            if direct
            else "Compiled iOS app code or build inputs changed; trace state to its nearest surface."
        )

    android_diff = focused_diff(repo, before, after, android_files)
    ios_diff = focused_diff(repo, before, after, ios_files)
    runtime_matrix = {
        "android": bool(
            android_files
            and (
                any(ANDROID_RUNTIME_PATH_RE.search(path) for path in android_files)
                or ANDROID_RUNTIME_DIFF_RE.search(android_diff)
            )
        ),
        "ios": bool(
            ios_files
            and IOS_RUNTIME_DIFF_RE.search(ios_diff)
        ),
    }

    skipped = []
    for platform in ("android", "ios"):
        if platform not in platforms:
            display_name = "iOS" if platform == "ios" else "Android"
            skipped.append(
                {
                    "platform": platform,
                    "reason": f"No compiled {display_name} app input changed.",
                }
            )

    return {
        "before_sha": before,
        "after_sha": after,
        "platforms": platforms,
        "impact": impact,
        "reasons": reasons,
        "requires_runtime_matrix": runtime_matrix,
        "skipped_platforms": skipped,
        "changed_files": files,
        "platform_files": {
            "android": android_files,
            "ios": ios_files,
        },
        "non_app_files": non_app_files,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--before", required=True)
    parser.add_argument("--after", required=True)
    parser.add_argument("--compact", action="store_true")
    args = parser.parse_args()

    repo = Path(
        git(args.repo_root, "rev-parse", "--show-toplevel").stdout.strip()
    ).resolve()
    before = resolve_commit(repo, args.before, "before")
    after = resolve_commit(repo, args.after, "after")
    if before == after:
        raise ValueError("before and after revisions must differ")

    print(
        json.dumps(
            route(repo, before, after),
            indent=None if args.compact else 2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
