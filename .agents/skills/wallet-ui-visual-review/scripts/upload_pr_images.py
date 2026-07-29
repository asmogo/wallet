#!/usr/bin/env python3
"""Upload validated PR screenshots through gh api without touching a source branch."""

from __future__ import annotations

import argparse
import base64
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

from validate_capture_manifest import validate_manifest


REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


def gh_api(
    endpoint: str,
    *,
    method: str = "GET",
    payload: dict[str, object] | None = None,
    allow_not_found: bool = False,
) -> dict[str, object] | None:
    command = ["gh", "api"]
    if method != "GET":
        command.extend(["-X", method])
    command.append(endpoint)
    input_text = None
    if payload is not None:
        command.extend(["--input", "-"])
        input_text = json.dumps(payload)

    result = subprocess.run(
        command,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        if allow_not_found and "HTTP 404" in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip() or f"gh api failed for {endpoint}")
    if not result.stdout.strip():
        return {}
    parsed = json.loads(result.stdout)
    if not isinstance(parsed, dict):
        raise RuntimeError(f"unexpected gh api response for {endpoint}")
    return parsed


def manifest_images(manifest_path: Path, expected_pr: int) -> tuple[list[Path], str]:
    validate_manifest(manifest_path)
    with manifest_path.open(encoding="utf-8") as handle:
        data = json.load(handle)

    target = data["target"]
    if target["kind"] != "pr" or target.get("pr_number") != expected_pr:
        raise ValueError("manifest PR target does not match --pr")
    after_sha = data["revisions"]["after_sha"]
    root = manifest_path.resolve().parent

    relative_paths: list[str] = []
    for capture in data["captures"]:
        relative_paths.extend((capture["before"]["file"], capture["after"]["file"]))
    relative_paths.extend(extra["file"] for extra in data.get("extras", []))

    files: list[Path] = []
    seen_names: set[str] = set()
    for relative in relative_paths:
        path = (root / relative).resolve()
        if path.name in seen_names:
            raise ValueError(f"duplicate basename would collide in upload: {path.name}")
        seen_names.add(path.name)
        files.append(path)
    if not files:
        raise ValueError("manifest contains no images to upload")
    return files, after_sha


def image_markdown(files: list[dict[str, str]]) -> str:
    sections: list[str] = []
    for index in range(0, len(files), 2):
        pair = files[index : index + 2]
        labels = " | ".join(item["name"] for item in pair)
        separators = " | ".join("---" for _ in pair)
        images = " | ".join(
            f'![{item["name"]}]({item["url"]})' for item in pair
        )
        sections.append(f"| {labels} |\n| {separators} |\n| {images} |")
    return "\n\n".join(sections)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, help="OWNER/REPO")
    parser.add_argument("--pr", required=True, type=int)
    parser.add_argument("--manifest", required=True, type=Path)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--dry-run", action="store_true")
    action.add_argument(
        "--confirm-publish",
        action="store_true",
        help="Acknowledge that this creates or updates a GitHub upload ref.",
    )
    args = parser.parse_args()

    if not REPO_RE.fullmatch(args.repo):
        raise ValueError("--repo must use OWNER/REPO")
    if args.pr <= 0:
        raise ValueError("--pr must be a positive integer")
    files, after_sha = manifest_images(args.manifest.resolve(), args.pr)
    file_info = [
        {"name": path.name, "size": path.stat().st_size} for path in files
    ]

    if args.dry_run:
        print(
            json.dumps(
                {
                    "status": "dry-run",
                    "repo": args.repo,
                    "pr": args.pr,
                    "after_sha": after_sha,
                    "ref": f"refs/uploads/issues/{args.pr}",
                    "files": file_info,
                },
                indent=2,
            )
        )
        return 0

    api_prefix = f"repos/{args.repo}"
    ref_path = f"uploads/issues/{args.pr}"
    ref_response = gh_api(
        f"{api_prefix}/git/ref/{ref_path}",
        allow_not_found=True,
    )

    parent_sha = ""
    base_tree_sha = ""
    if ref_response is not None:
        ref_object = ref_response.get("object")
        if not isinstance(ref_object, dict) or not isinstance(ref_object.get("sha"), str):
            raise RuntimeError("existing upload ref did not contain a commit SHA")
        parent_sha = str(ref_object["sha"])
        parent_commit = gh_api(f"{api_prefix}/git/commits/{parent_sha}")
        tree = parent_commit.get("tree") if parent_commit else None
        if not isinstance(tree, dict) or not isinstance(tree.get("sha"), str):
            raise RuntimeError("existing upload commit did not contain a tree SHA")
        base_tree_sha = str(tree["sha"])

    entries: list[dict[str, str]] = []
    for path in files:
        content = base64.b64encode(path.read_bytes()).decode("ascii")
        blob = gh_api(
            f"{api_prefix}/git/blobs",
            method="POST",
            payload={"content": content, "encoding": "base64"},
        )
        blob_sha = blob.get("sha") if blob else None
        if not isinstance(blob_sha, str):
            raise RuntimeError(f"blob upload did not return a SHA for {path.name}")
        entries.append(
            {
                "path": path.name,
                "mode": "100644",
                "type": "blob",
                "sha": blob_sha,
            }
        )

    tree_payload: dict[str, object] = {"tree": entries}
    if base_tree_sha:
        tree_payload["base_tree"] = base_tree_sha
    tree_response = gh_api(
        f"{api_prefix}/git/trees",
        method="POST",
        payload=tree_payload,
    )
    tree_sha = tree_response.get("sha") if tree_response else None
    if not isinstance(tree_sha, str):
        raise RuntimeError("tree creation did not return a SHA")

    commit_response = gh_api(
        f"{api_prefix}/git/commits",
        method="POST",
        payload={
            "message": f"Add wallet visual evidence for PR #{args.pr} ({after_sha[:12]})",
            "tree": tree_sha,
            "parents": [parent_sha] if parent_sha else [],
        },
    )
    commit_sha = commit_response.get("sha") if commit_response else None
    if not isinstance(commit_sha, str):
        raise RuntimeError("commit creation did not return a SHA")

    if parent_sha:
        gh_api(
            f"{api_prefix}/git/refs/{ref_path}",
            method="PATCH",
            payload={"sha": commit_sha, "force": False},
        )
    else:
        gh_api(
            f"{api_prefix}/git/refs",
            method="POST",
            payload={"ref": f"refs/{ref_path}", "sha": commit_sha},
        )

    uploaded = [
        {
            "name": path.name,
            "url": (
                f"https://github.com/{args.repo}/blob/{commit_sha}/"
                f"{quote(path.name)}?raw=true"
            ),
        }
        for path in files
    ]
    print(
        json.dumps(
            {
                "status": "ok",
                "repo": args.repo,
                "pr": args.pr,
                "after_sha": after_sha,
                "ref": f"refs/{ref_path}",
                "sha": commit_sha,
                "files": uploaded,
                "markdown": image_markdown(uploaded),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
