from __future__ import annotations

import copy
import hashlib
import json
import os
import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parents[1]
SCRIPTS = SKILL_DIR / "scripts"
VALIDATOR = SCRIPTS / "validate_capture_manifest.py"
ROUTER = SCRIPTS / "route_platforms.py"
SESSION = SCRIPTS / "create_review_session.sh"
UPLOADER = SCRIPTS / "upload_pr_images.py"
BEFORE_SHA = "1" * 40
AFTER_SHA = "2" * 40


def png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(chunk_type)
    crc = zlib.crc32(data, crc) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", crc)


def png_bytes(width: int = 1, height: int = 1) -> bytes:
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    raw = b"".join(b"\x00" + (b"\x11\x22\x33\xff" * width) for _ in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(raw))
        + png_chunk(b"IEND", b"")
    )


def invalid_compressed_png() -> bytes:
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", b"not-a-zlib-stream")
        + png_chunk(b"IEND", b"")
    )


def trailing_zlib_data_png() -> bytes:
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    raw = b"\x00\x11\x22\x33\xff"
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(raw) + b"trailing")
        + png_chunk(b"IEND", b"")
    )


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def base_manifest(before_png: bytes, after_png: bytes) -> dict[str, object]:
    return {
        "schema_version": 1,
        "target": {
            "kind": "branch",
            "value": "feature",
            "base_ref": "main",
            "pr_number": None,
        },
        "revisions": {
            "before_sha": BEFORE_SHA,
            "after_sha": AFTER_SHA,
        },
        "routing": {
            "platforms": ["android"],
            "skipped_platforms": [
                {"platform": "ios", "reason": "No compiled iOS app input changed."}
            ],
        },
        "environments": [
            {
                "id": "android-api37-light",
                "platform": "android",
                "stability": "stable",
                "os_name": "Android",
                "os_version": "17",
                "os_build": "build",
                "device_type": "Pixel phone",
                "viewport_px": "1080x2400",
                "theme": "light",
                "locale": "en-US",
                "font_scale": 1.0,
                "details": {
                    "api_level": 37,
                    "build_fingerprint": "generic/device/build",
                    "security_patch": "2026-07-05",
                    "abi": "arm64-v8a",
                    "density_dpi": 420,
                    "logical_viewport_dp": "411x914",
                },
            }
        ],
        "builds": [
            {
                "id": "android-before",
                "platform": "android",
                "side": "before",
                "source_sha": BEFORE_SHA,
                "environment_id": "android-api37-light",
                "app_id": "com.cashu.me.debug",
                "app_version": "1.0",
                "build_number": "4",
                "binary_name": "app-debug.apk",
                "binary_sha256": "a" * 64,
            },
            {
                "id": "android-after",
                "platform": "android",
                "side": "after",
                "source_sha": AFTER_SHA,
                "environment_id": "android-api37-light",
                "app_id": "com.cashu.me.debug",
                "app_version": "1.0",
                "build_number": "4",
                "binary_name": "app-debug.apk",
                "binary_sha256": "b" * 64,
            },
        ],
        "captures": [
            {
                "id": "android-settings-light",
                "platform": "android",
                "environment_id": "android-api37-light",
                "surface": "Settings",
                "state": "Synthetic seeded wallet",
                "fixture": "Fixed test seed",
                "expected_change": "No visual delta",
                "before": {
                    "file": "before.png",
                    "build_id": "android-before",
                    "sha256": sha256(before_png),
                },
                "after": {
                    "file": "after.png",
                    "build_id": "android-after",
                    "sha256": sha256(after_png),
                },
                "limitations": [],
            }
        ],
        "extras": [],
        "limitations": ["Static screenshots do not prove payment behavior."],
    }


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        text=True,
        capture_output=True,
        check=True,
    )
    return result.stdout.strip()


def init_repo(root: Path) -> tuple[Path, str]:
    repo = root / "repo"
    repo.mkdir()
    git(repo, "init", "-b", "main")
    git(repo, "config", "user.name", "Skill Test")
    git(repo, "config", "user.email", "skill-test@example.invalid")
    (repo / "README.md").write_text("base\n", encoding="utf-8")
    git(repo, "add", "README.md")
    git(repo, "commit", "-m", "base")
    return repo, git(repo, "rev-parse", "HEAD")


class ManifestValidatorTests(unittest.TestCase):
    def run_validator(
        self,
        manifest: dict[str, object],
        *,
        before_payload: bytes | None = None,
        after_payload: bytes | None = None,
        outside_payload: bytes | None = None,
    ) -> subprocess.CompletedProcess[str]:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        before = before_payload if before_payload is not None else png_bytes()
        after = after_payload if after_payload is not None else png_bytes()
        (root / "before.png").write_bytes(before)
        (root / "after.png").write_bytes(after)
        if outside_payload is not None:
            (root.parent / "outside.png").write_bytes(outside_payload)
            self.addCleanup(lambda: (root.parent / "outside.png").unlink(missing_ok=True))
        manifest_path = root / "capture-manifest.json"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        return subprocess.run(
            ["python3", str(VALIDATOR), str(manifest_path)],
            text=True,
            capture_output=True,
            check=False,
        )

    def test_valid_manifest_allows_identical_no_delta_images(self) -> None:
        image = png_bytes()
        result = self.run_validator(base_manifest(image, image))
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = json.loads(result.stdout)
        self.assertEqual(summary["status"], "ok")
        self.assertEqual(summary["pairs"], 1)

    def test_rejects_png_missing_iend(self) -> None:
        before = png_bytes()
        after = png_bytes()[:-12]
        manifest = base_manifest(before, after)
        result = self.run_validator(manifest, before_payload=before, after_payload=after)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing IEND", result.stderr)

    def test_rejects_corrupt_png_crc(self) -> None:
        before = png_bytes()
        after = bytearray(png_bytes())
        idat = after.index(b"IDAT")
        length = struct.unpack(">I", after[idat - 4 : idat])[0]
        crc_offset = idat + 4 + length
        after[crc_offset] ^= 0x01
        payload = bytes(after)
        manifest = base_manifest(before, payload)
        result = self.run_validator(manifest, before_payload=before, after_payload=payload)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CRC mismatch", result.stderr)

    def test_rejects_invalid_compressed_payload(self) -> None:
        before = png_bytes()
        after = invalid_compressed_png()
        manifest = base_manifest(before, after)
        result = self.run_validator(manifest, before_payload=before, after_payload=after)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot be decompressed", result.stderr)

    def test_rejects_trailing_data_after_zlib_stream(self) -> None:
        before = png_bytes()
        after = trailing_zlib_data_png()
        manifest = base_manifest(before, after)
        result = self.run_validator(manifest, before_payload=before, after_payload=after)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exactly one complete zlib stream", result.stderr)

    def test_rejects_mismatched_dimensions(self) -> None:
        before = png_bytes()
        after = png_bytes(width=2)
        manifest = base_manifest(before, after)
        result = self.run_validator(manifest, before_payload=before, after_payload=after)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dimensions differ", result.stderr)

    def test_rejects_mismatched_runtime_association(self) -> None:
        image = png_bytes()
        manifest = base_manifest(image, image)
        second = copy.deepcopy(manifest["environments"][0])
        second["id"] = "android-api36-light"
        second["details"]["api_level"] = 36
        manifest["environments"].append(second)
        manifest["builds"][1]["environment_id"] = second["id"]
        result = self.run_validator(manifest)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match side/platform/environment", result.stderr)

    def test_rejects_wrong_build_source_sha(self) -> None:
        image = png_bytes()
        manifest = base_manifest(image, image)
        manifest["builds"][1]["source_sha"] = "3" * 40
        result = self.run_validator(manifest)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match the after revision", result.stderr)

    def test_rejects_duplicate_image_path(self) -> None:
        image = png_bytes()
        manifest = base_manifest(image, image)
        manifest["captures"][0]["after"]["file"] = "before.png"
        result = self.run_validator(manifest)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("screenshot path is reused", result.stderr)

    def test_rejects_path_traversal(self) -> None:
        image = png_bytes()
        manifest = base_manifest(image, image)
        manifest["captures"][0]["after"]["file"] = "../outside.png"
        result = self.run_validator(manifest, outside_payload=image)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must stay relative", result.stderr)

    def test_rejects_machine_identifier(self) -> None:
        image = png_bytes()
        manifest = base_manifest(image, image)
        manifest["captures"][0]["fixture"] = "Loaded from /Users/example/fixture.json"
        result = self.run_validator(manifest)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("local path", result.stderr)

    def test_accepts_docs_only_manifest_without_fake_captures(self) -> None:
        manifest = {
            "schema_version": 1,
            "target": {
                "kind": "commit",
                "value": AFTER_SHA,
                "base_ref": "main",
                "pr_number": None,
            },
            "revisions": {"before_sha": BEFORE_SHA, "after_sha": AFTER_SHA},
            "routing": {
                "platforms": [],
                "skipped_platforms": [
                    {"platform": "android", "reason": "No compiled app input changed."},
                    {"platform": "ios", "reason": "No compiled app input changed."},
                ],
            },
            "environments": [],
            "builds": [],
            "captures": [],
            "extras": [],
            "limitations": ["No compiled application input changed."],
        }
        result = self.run_validator(manifest)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["pairs"], 0)


class RouterTests(unittest.TestCase):
    def route(self, files: dict[str, str]) -> dict[str, object]:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        repo, before = init_repo(Path(temp.name))
        for relative, contents in files.items():
            path = repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents, encoding="utf-8")
        git(repo, "add", ".")
        git(repo, "commit", "-m", "change")
        after = git(repo, "rev-parse", "HEAD")
        result = subprocess.run(
            [
                "python3",
                str(ROUTER),
                "--repo-root",
                str(repo),
                "--before",
                before,
                "--after",
                after,
            ],
            text=True,
            capture_output=True,
            check=True,
        )
        return json.loads(result.stdout)

    def test_routes_android_only(self) -> None:
        result = self.route(
            {"android/app/src/main/java/com/cashu/me/ui/home/HomeScreen.kt": "UI\n"}
        )
        self.assertEqual(result["platforms"], ["android"])
        self.assertEqual(result["impact"]["android"], "direct")

    def test_routes_ios_only(self) -> None:
        result = self.route({"ios/CashuWallet/Views/Main/MainWalletView.swift": "UI\n"})
        self.assertEqual(result["platforms"], ["ios"])
        self.assertEqual(result["impact"]["ios"], "direct")

    def test_routes_both_and_flags_version_gate(self) -> None:
        result = self.route(
            {
                "android/app/src/main/java/com/cashu/me/ui/home/HomeScreen.kt": (
                    "if (Build.VERSION.SDK_INT >= 37) {}\n"
                ),
                "ios/CashuWallet/Views/Main/MainWalletView.swift": (
                    "if #available(iOS 26, *) {}\n"
                ),
            }
        )
        self.assertEqual(result["platforms"], ["android", "ios"])
        self.assertTrue(result["requires_runtime_matrix"]["android"])
        self.assertTrue(result["requires_runtime_matrix"]["ios"])

    def test_routes_docs_and_tests_to_no_app(self) -> None:
        result = self.route(
            {
                "docs/visual-review.md": "docs\n",
                "android/README.md": "android docs\n",
                "android/app/release/app-release.aab": "build output\n",
                "ios/docs/README.md": "ios docs\n",
                "ios/CashuWalletUITests/NewTests.swift": "test\n",
                "android/app/src/androidTest/java/Test.kt": "test\n",
            }
        )
        self.assertEqual(result["platforms"], [])
        self.assertEqual(len(result["skipped_platforms"]), 2)


class UploaderTests(unittest.TestCase):
    def test_dry_run_uses_only_validated_pr_manifest_images(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            image = png_bytes()
            (root / "before.png").write_bytes(image)
            (root / "after.png").write_bytes(image)
            manifest = base_manifest(image, image)
            manifest["target"] = {
                "kind": "pr",
                "value": "PR #195",
                "base_ref": "main",
                "pr_number": 195,
            }
            manifest_path = root / "capture-manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            result = subprocess.run(
                [
                    "python3",
                    str(UPLOADER),
                    "--repo",
                    "asmogo/wallet",
                    "--pr",
                    "195",
                    "--manifest",
                    str(manifest_path),
                    "--dry-run",
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)
            self.assertEqual(output["status"], "dry-run")
            self.assertEqual(
                [item["name"] for item in output["files"]],
                ["before.png", "after.png"],
            )

    def test_non_dry_run_requires_explicit_confirm_flag(self) -> None:
        result = subprocess.run(
            [
                "python3",
                str(UPLOADER),
                "--repo",
                "asmogo/wallet",
                "--pr",
                "195",
                "--manifest",
                "missing.json",
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("one of the arguments", result.stderr)


class SessionTests(unittest.TestCase):
    def test_creates_two_worktrees_and_preserves_dirty_source(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            repo, before = init_repo(root)
            git(repo, "switch", "-c", "feature")
            (repo / "feature.txt").write_text("feature\n", encoding="utf-8")
            git(repo, "add", "feature.txt")
            git(repo, "commit", "-m", "feature")
            after = git(repo, "rev-parse", "HEAD")
            (repo / "README.md").write_text("dirty but unrelated\n", encoding="utf-8")
            status_before = git(repo, "status", "--porcelain")
            branch_before = git(repo, "branch", "--show-current")

            session_root = root / "sessions"
            result = subprocess.run(
                [
                    "bash",
                    str(SESSION),
                    "--repo-root",
                    str(repo),
                    "--target",
                    "feature",
                    "--base",
                    "main",
                    "--session-root",
                    str(session_root),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            values = dict(
                line.split("=", 1)
                for line in result.stdout.splitlines()
                if "=" in line
            )
            session = json.loads(Path(values["SESSION_JSON"]).read_text(encoding="utf-8"))
            self.assertEqual(session["before_sha"], before)
            self.assertEqual(session["after_sha"], after)
            self.assertEqual(session["target_kind"], "branch")
            self.assertTrue(session["source_checkout_dirty"])
            self.assertNotEqual(session["before_worktree"], session["after_worktree"])
            self.assertEqual(
                git(Path(session["before_worktree"]), "rev-parse", "HEAD"), before
            )
            self.assertEqual(
                git(Path(session["after_worktree"]), "rev-parse", "HEAD"), after
            )
            self.assertEqual(git(repo, "branch", "--show-current"), branch_before)
            self.assertEqual(git(repo, "status", "--porcelain"), status_before)

    def test_rejects_patch_and_working_tree_targets(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            repo, _ = init_repo(Path(temp))
            for target in ("change.patch", "working-tree"):
                result = subprocess.run(
                    [
                        "bash",
                        str(SESSION),
                        "--repo-root",
                        str(repo),
                        "--target",
                        target,
                    ],
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 2)
                self.assertIn("not supported", result.stderr)


if __name__ == "__main__":
    unittest.main()
