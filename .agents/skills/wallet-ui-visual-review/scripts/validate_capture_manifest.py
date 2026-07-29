#!/usr/bin/env python3
"""Validate a wallet visual-review manifest and its complete PNG evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import sys
import zlib
from pathlib import Path
from typing import Any


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
VIEWPORT_RE = re.compile(r"^[1-9][0-9]*x[1-9][0-9]*$")
FORBIDDEN_KEY_PARTS = ("serial", "udid", "local_path", "worktree_path", "repo_root")
MACHINE_VALUE_PATTERNS = (
    re.compile(r"(?:^|[\s\"'])/(?:Users|home|private/var|tmp)/"),
    re.compile(r"\bfile://", re.I),
    re.compile(r"\b[A-Za-z]:\\"),
    re.compile(r"\bemulator-\d+\b", re.I),
    re.compile(r"\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|"
               r"172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})\b"),
)
ALLOWED_TOP_LEVEL = {
    "schema_version",
    "target",
    "revisions",
    "routing",
    "environments",
    "builds",
    "captures",
    "extras",
    "limitations",
}
ALLOWED_ENVIRONMENT_KEYS = {
    "id",
    "platform",
    "stability",
    "os_name",
    "os_version",
    "os_build",
    "device_type",
    "viewport_px",
    "theme",
    "locale",
    "font_scale",
    "details",
}


def fail(message: str) -> None:
    raise ValueError(message)


def require_object(value: object, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{field} must be an object")
    return value


def require_array(value: object, field: str) -> list[Any]:
    if not isinstance(value, list):
        fail(f"{field} must be an array")
    return value


def require_string(data: dict[str, Any], key: str, field: str = "") -> str:
    value = data.get(key)
    name = f"{field}.{key}" if field else key
    if not isinstance(value, str) or not value.strip():
        fail(f"{name} must be a non-empty string")
    return value


def require_exact_keys(
    data: dict[str, Any],
    allowed: set[str],
    field: str,
    *,
    required: set[str] | None = None,
) -> None:
    unknown = sorted(set(data) - allowed)
    if unknown:
        fail(f"{field} contains unknown field(s): {', '.join(unknown)}")
    missing = sorted((required or set()) - set(data))
    if missing:
        fail(f"{field} is missing field(s): {', '.join(missing)}")


def require_id(value: str, field: str) -> str:
    if not ID_RE.fullmatch(value):
        fail(f"{field} must use lowercase letters, digits, '.', '_' or '-'")
    return value


def require_sha256(value: str, field: str) -> str:
    if not SHA256_RE.fullmatch(value):
        fail(f"{field} must be a lowercase 64-character SHA-256")
    return value


def scan_machine_identifiers(value: object, field: str = "manifest") -> None:
    if isinstance(value, dict):
        for key, item in value.items():
            normalized = str(key).lower().replace("-", "_")
            if any(part in normalized for part in FORBIDDEN_KEY_PARTS):
                fail(f"{field}.{key} uses a forbidden machine-identifier field")
            scan_machine_identifiers(item, f"{field}.{key}")
    elif isinstance(value, list):
        for index, item in enumerate(value):
            scan_machine_identifiers(item, f"{field}[{index}]")
    elif isinstance(value, str):
        for pattern in MACHINE_VALUE_PATTERNS:
            if pattern.search(value):
                fail(f"{field} contains a local path, selector, or private address")


def relative_file(root: Path, value: object, field: str) -> Path:
    if not isinstance(value, str) or not value:
        fail(f"{field} must be a non-empty relative path")
    candidate = Path(value)
    if candidate.is_absolute() or ".." in candidate.parts:
        fail(f"{field} must stay relative to the artifact directory: {value!r}")
    resolved = (root / candidate).resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError as exc:
        raise ValueError(f"{field} escapes the artifact directory: {value!r}") from exc
    if not resolved.is_file():
        fail(f"{field} does not exist: {value}")
    if resolved.suffix.lower() != ".png":
        fail(f"{field} must reference a PNG file: {value}")
    return resolved


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pass_size(total: int, start: int, step: int) -> int:
    if total <= start:
        return 0
    return (total - start + step - 1) // step


def expected_scanline_bytes(
    width: int,
    height: int,
    bit_depth: int,
    color_type: int,
    interlace: int,
) -> int:
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    bits_per_pixel = channels * bit_depth

    def pass_bytes(pass_width: int, pass_height: int) -> int:
        if pass_width == 0 or pass_height == 0:
            return 0
        row_bytes = (pass_width * bits_per_pixel + 7) // 8
        return pass_height * (1 + row_bytes)

    if interlace == 0:
        return pass_bytes(width, height)

    adam7 = (
        (0, 0, 8, 8),
        (4, 0, 8, 8),
        (0, 4, 4, 8),
        (2, 0, 4, 4),
        (0, 2, 2, 4),
        (1, 0, 2, 2),
        (0, 1, 1, 2),
    )
    return sum(
        pass_bytes(pass_size(width, x0, dx), pass_size(height, y0, dy))
        for x0, y0, dx, dy in adam7
    )


def validate_scanline_filters(
    decoded: bytes,
    width: int,
    height: int,
    bit_depth: int,
    color_type: int,
    interlace: int,
    path: Path,
) -> None:
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    bits_per_pixel = channels * bit_depth
    passes = (
        ((width, height),)
        if interlace == 0
        else tuple(
            (
                pass_size(width, x0, dx),
                pass_size(height, y0, dy),
            )
            for x0, y0, dx, dy in (
                (0, 0, 8, 8),
                (4, 0, 8, 8),
                (0, 4, 4, 8),
                (2, 0, 4, 4),
                (0, 2, 2, 4),
                (1, 0, 2, 2),
                (0, 1, 1, 2),
            )
        )
    )
    offset = 0
    for pass_width, pass_height in passes:
        if pass_width == 0 or pass_height == 0:
            continue
        row_bytes = (pass_width * bits_per_pixel + 7) // 8
        for _ in range(pass_height):
            if decoded[offset] not in {0, 1, 2, 3, 4}:
                fail(f"PNG contains an invalid scanline filter: {path.name}")
            offset += 1 + row_bytes
    if offset != len(decoded):
        fail(f"PNG scanline payload was not consumed exactly: {path.name}")


def validate_png(path: Path) -> tuple[int, int]:
    if path.stat().st_size > 100 * 1024 * 1024:
        fail(f"PNG is unexpectedly large: {path.name}")
    payload = path.read_bytes()
    if not payload.startswith(PNG_SIGNATURE):
        fail(f"invalid PNG signature: {path.name}")

    offset = len(PNG_SIGNATURE)
    chunks: list[tuple[bytes, bytes]] = []
    seen_iend = False
    while offset < len(payload):
        if len(payload) - offset < 12:
            fail(f"truncated PNG chunk header or CRC: {path.name}")
        length = struct.unpack(">I", payload[offset : offset + 4])[0]
        chunk_end = offset + 12 + length
        if chunk_end > len(payload):
            fail(f"truncated PNG chunk payload: {path.name}")
        chunk_type = payload[offset + 4 : offset + 8]
        chunk_data = payload[offset + 8 : offset + 8 + length]
        recorded_crc = struct.unpack(">I", payload[offset + 8 + length : chunk_end])[0]
        actual_crc = zlib.crc32(chunk_type)
        actual_crc = zlib.crc32(chunk_data, actual_crc) & 0xFFFFFFFF
        if recorded_crc != actual_crc:
            fail(f"PNG CRC mismatch in {chunk_type!r}: {path.name}")
        if not re.fullmatch(rb"[A-Za-z]{4}", chunk_type):
            fail(f"invalid PNG chunk type: {path.name}")
        if chunk_type[:1].isupper() and chunk_type not in {
            b"IHDR",
            b"PLTE",
            b"IDAT",
            b"IEND",
        }:
            fail(f"unknown critical PNG chunk {chunk_type!r}: {path.name}")
        chunks.append((chunk_type, chunk_data))
        offset = chunk_end
        if chunk_type == b"IEND":
            if length != 0:
                fail(f"IEND must be empty: {path.name}")
            seen_iend = True
            break

    if not seen_iend:
        fail(f"PNG is missing IEND: {path.name}")
    if offset != len(payload):
        fail(f"PNG contains trailing bytes after IEND: {path.name}")
    if not chunks or chunks[0][0] != b"IHDR":
        fail(f"IHDR must be the first PNG chunk: {path.name}")
    if sum(1 for chunk_type, _ in chunks if chunk_type == b"IHDR") != 1:
        fail(f"PNG must contain exactly one IHDR: {path.name}")

    ihdr = chunks[0][1]
    if len(ihdr) != 13:
        fail(f"invalid IHDR length: {path.name}")
    width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", ihdr
    )
    if width <= 0 or height <= 0 or width * height > 50_000_000:
        fail(f"invalid or excessive PNG dimensions: {path.name}")
    valid_depths = {
        0: {1, 2, 4, 8, 16},
        2: {8, 16},
        3: {1, 2, 4, 8},
        4: {8, 16},
        6: {8, 16},
    }
    if color_type not in valid_depths or bit_depth not in valid_depths[color_type]:
        fail(f"invalid PNG color type/bit depth: {path.name}")
    if compression != 0 or filtering != 0 or interlace not in {0, 1}:
        fail(f"unsupported PNG compression/filter/interlace metadata: {path.name}")

    idat_chunks = [data for chunk_type, data in chunks if chunk_type == b"IDAT"]
    if not idat_chunks:
        fail(f"PNG is missing IDAT data: {path.name}")
    seen_idat = False
    idat_closed = False
    for chunk_type, _ in chunks:
        if chunk_type == b"IDAT":
            if idat_closed:
                fail(f"PNG IDAT chunks are not consecutive: {path.name}")
            seen_idat = True
        elif seen_idat:
            idat_closed = True

    try:
        decompressor = zlib.decompressobj()
        decoded = decompressor.decompress(b"".join(idat_chunks))
        decoded += decompressor.flush()
    except zlib.error as exc:
        raise ValueError(f"PNG IDAT data cannot be decompressed: {path.name}") from exc
    if (
        not decompressor.eof
        or decompressor.unused_data
        or decompressor.unconsumed_tail
    ):
        fail(f"PNG IDAT does not contain exactly one complete zlib stream: {path.name}")
    expected = expected_scanline_bytes(
        width, height, bit_depth, color_type, interlace
    )
    if len(decoded) != expected:
        fail(
            f"PNG decoded payload length is invalid: {path.name} "
            f"(expected {expected}, got {len(decoded)})"
        )
    validate_scanline_filters(
        decoded,
        width,
        height,
        bit_depth,
        color_type,
        interlace,
        path,
    )
    return width, height


def validate_manifest(path: Path) -> dict[str, object]:
    manifest_path = path.resolve()
    if not manifest_path.is_file():
        fail(f"manifest not found: {manifest_path}")
    root = manifest_path.parent
    with manifest_path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    data = require_object(data, "manifest")
    require_exact_keys(
        data,
        ALLOWED_TOP_LEVEL,
        "manifest",
        required={
            "schema_version",
            "target",
            "revisions",
            "routing",
            "environments",
            "builds",
            "captures",
            "limitations",
        },
    )
    if data.get("schema_version") != 1:
        fail("schema_version must be 1")
    scan_machine_identifiers(data)

    target = require_object(data.get("target"), "target")
    require_exact_keys(
        target,
        {"kind", "value", "base_ref", "pr_number"},
        "target",
        required={"kind", "value", "base_ref"},
    )
    target_kind = require_string(target, "kind", "target")
    if target_kind not in {"pr", "branch", "commit"}:
        fail("target.kind must be pr, branch, or commit")
    require_string(target, "value", "target")
    require_string(target, "base_ref", "target")
    if target_kind == "pr":
        if not isinstance(target.get("pr_number"), int) or target["pr_number"] <= 0:
            fail("target.pr_number must be a positive integer for PR targets")
    elif target.get("pr_number") is not None:
        fail("target.pr_number must be omitted or null for non-PR targets")

    revisions = require_object(data.get("revisions"), "revisions")
    require_exact_keys(
        revisions,
        {"before_sha", "after_sha"},
        "revisions",
        required={"before_sha", "after_sha"},
    )
    before_sha = require_string(revisions, "before_sha", "revisions")
    after_sha = require_string(revisions, "after_sha", "revisions")
    if not SHA_RE.fullmatch(before_sha) or not SHA_RE.fullmatch(after_sha):
        fail("revision SHAs must be lowercase 40-character Git SHAs")
    if before_sha == after_sha:
        fail("before_sha and after_sha must differ")

    routing = require_object(data.get("routing"), "routing")
    require_exact_keys(
        routing,
        {"platforms", "skipped_platforms"},
        "routing",
        required={"platforms", "skipped_platforms"},
    )
    platforms = require_array(routing.get("platforms"), "routing.platforms")
    if (
        len(platforms) != len(set(platforms))
        or not all(platform in {"android", "ios"} for platform in platforms)
    ):
        fail("routing.platforms must contain unique android/ios values")
    skipped = require_array(
        routing.get("skipped_platforms"), "routing.skipped_platforms"
    )
    skipped_names: set[str] = set()
    for index, value in enumerate(skipped):
        item = require_object(value, f"routing.skipped_platforms[{index}]")
        require_exact_keys(
            item,
            {"platform", "reason"},
            f"routing.skipped_platforms[{index}]",
            required={"platform", "reason"},
        )
        platform = require_string(
            item, "platform", f"routing.skipped_platforms[{index}]"
        )
        require_string(item, "reason", f"routing.skipped_platforms[{index}]")
        if platform not in {"android", "ios"} or platform in skipped_names:
            fail("skipped platforms must be unique android/ios values")
        if platform in platforms:
            fail(f"{platform} cannot be both routed and skipped")
        skipped_names.add(platform)
    if set(platforms) | skipped_names != {"android", "ios"}:
        fail("routing must account for both android and ios")

    environments_raw = require_array(data.get("environments"), "environments")
    environments: dict[str, dict[str, Any]] = {}
    for index, value in enumerate(environments_raw):
        field = f"environments[{index}]"
        item = require_object(value, field)
        require_exact_keys(
            item,
            ALLOWED_ENVIRONMENT_KEYS,
            field,
            required=ALLOWED_ENVIRONMENT_KEYS,
        )
        env_id = require_id(require_string(item, "id", field), f"{field}.id")
        if env_id in environments:
            fail(f"duplicate environment id: {env_id}")
        platform = require_string(item, "platform", field)
        if platform not in platforms:
            fail(f"{field}.platform is not routed: {platform}")
        stability = require_string(item, "stability", field)
        if stability not in {"stable", "beta", "preview", "rc"}:
            fail(f"{field}.stability is invalid")
        for key in ("os_name", "os_version", "os_build", "device_type", "theme", "locale"):
            require_string(item, key, field)
        if not VIEWPORT_RE.fullmatch(require_string(item, "viewport_px", field)):
            fail(f"{field}.viewport_px must use WIDTHxHEIGHT")
        font_scale = item.get("font_scale")
        if not isinstance(font_scale, (int, float)) or font_scale <= 0:
            fail(f"{field}.font_scale must be positive")
        details = require_object(item.get("details"), f"{field}.details")
        if platform == "android":
            require_exact_keys(
                details,
                {
                    "api_level",
                    "build_fingerprint",
                    "security_patch",
                    "abi",
                    "density_dpi",
                    "logical_viewport_dp",
                },
                f"{field}.details",
                required={
                    "api_level",
                    "build_fingerprint",
                    "security_patch",
                    "abi",
                    "density_dpi",
                    "logical_viewport_dp",
                },
            )
            if not isinstance(details.get("api_level"), int) or details["api_level"] <= 0:
                fail(f"{field}.details.api_level must be positive")
            if not isinstance(details.get("density_dpi"), int) or details["density_dpi"] <= 0:
                fail(f"{field}.details.density_dpi must be positive")
            for key in ("build_fingerprint", "security_patch", "abi", "logical_viewport_dp"):
                require_string(details, key, f"{field}.details")
        else:
            require_exact_keys(
                details,
                {
                    "runtime_build",
                    "xcode_version",
                    "xcode_build",
                    "viewport_points",
                    "display_scale",
                    "dynamic_type",
                },
                f"{field}.details",
                required={
                    "runtime_build",
                    "xcode_version",
                    "xcode_build",
                    "viewport_points",
                    "display_scale",
                    "dynamic_type",
                },
            )
            for key in (
                "runtime_build",
                "xcode_version",
                "xcode_build",
                "viewport_points",
                "dynamic_type",
            ):
                require_string(details, key, f"{field}.details")
            if not isinstance(details.get("display_scale"), (int, float)) or details["display_scale"] <= 0:
                fail(f"{field}.details.display_scale must be positive")
        environments[env_id] = item

    builds_raw = require_array(data.get("builds"), "builds")
    builds: dict[str, dict[str, Any]] = {}
    for index, value in enumerate(builds_raw):
        field = f"builds[{index}]"
        item = require_object(value, field)
        require_exact_keys(
            item,
            {
                "id",
                "platform",
                "side",
                "source_sha",
                "environment_id",
                "app_id",
                "app_version",
                "build_number",
                "binary_name",
                "binary_sha256",
            },
            field,
            required={
                "id",
                "platform",
                "side",
                "source_sha",
                "environment_id",
                "app_id",
                "app_version",
                "build_number",
                "binary_name",
                "binary_sha256",
            },
        )
        build_id = require_id(require_string(item, "id", field), f"{field}.id")
        if build_id in builds:
            fail(f"duplicate build id: {build_id}")
        platform = require_string(item, "platform", field)
        side = require_string(item, "side", field)
        if platform not in platforms or side not in {"before", "after"}:
            fail(f"{field} has invalid platform or side")
        expected_sha = before_sha if side == "before" else after_sha
        if item.get("source_sha") != expected_sha:
            fail(f"{field}.source_sha does not match the {side} revision")
        env_id = require_string(item, "environment_id", field)
        if env_id not in environments or environments[env_id]["platform"] != platform:
            fail(f"{field}.environment_id does not match its platform")
        for key in ("app_id", "app_version", "build_number", "binary_name"):
            require_string(item, key, field)
        require_sha256(
            require_string(item, "binary_sha256", field),
            f"{field}.binary_sha256",
        )
        builds[build_id] = item

    captures_raw = require_array(data.get("captures"), "captures")
    if platforms and not captures_raw:
        fail("captures must contain evidence for every routed platform")
    captures: list[dict[str, Any]] = []
    used_paths: set[Path] = set()
    seen_ids: set[str] = set()
    platform_capture_count = {platform: 0 for platform in platforms}
    dimensions: list[dict[str, object]] = []

    for index, value in enumerate(captures_raw):
        field = f"captures[{index}]"
        item = require_object(value, field)
        require_exact_keys(
            item,
            {
                "id",
                "platform",
                "environment_id",
                "surface",
                "state",
                "fixture",
                "expected_change",
                "before",
                "after",
                "limitations",
            },
            field,
            required={
                "id",
                "platform",
                "environment_id",
                "surface",
                "state",
                "fixture",
                "expected_change",
                "before",
                "after",
                "limitations",
            },
        )
        capture_id = require_id(require_string(item, "id", field), f"{field}.id")
        if capture_id in seen_ids:
            fail(f"duplicate capture/extra id: {capture_id}")
        seen_ids.add(capture_id)
        platform = require_string(item, "platform", field)
        env_id = require_string(item, "environment_id", field)
        if (
            platform not in platforms
            or env_id not in environments
            or environments[env_id]["platform"] != platform
        ):
            fail(f"{field} has an invalid platform/environment association")
        for key in ("surface", "state", "fixture", "expected_change"):
            require_string(item, key, field)
        limitations = require_array(item.get("limitations"), f"{field}.limitations")
        if not all(isinstance(entry, str) and entry.strip() for entry in limitations):
            fail(f"{field}.limitations must contain non-empty strings")

        sizes: dict[str, tuple[int, int]] = {}
        for side in ("before", "after"):
            image_field = f"{field}.{side}"
            image = require_object(item.get(side), image_field)
            require_exact_keys(
                image,
                {"file", "build_id", "sha256"},
                image_field,
                required={"file", "build_id", "sha256"},
            )
            build_id = require_string(image, "build_id", image_field)
            if build_id not in builds:
                fail(f"{image_field}.build_id is unknown")
            build = builds[build_id]
            if (
                build["side"] != side
                or build["platform"] != platform
                or build["environment_id"] != env_id
            ):
                fail(f"{image_field}.build_id does not match side/platform/environment")
            image_path = relative_file(root, image.get("file"), f"{image_field}.file")
            if image_path in used_paths:
                fail(f"screenshot path is reused: {image_path.name}")
            used_paths.add(image_path)
            expected_hash = require_sha256(
                require_string(image, "sha256", image_field),
                f"{image_field}.sha256",
            )
            actual_hash = file_sha256(image_path)
            if expected_hash != actual_hash:
                fail(f"{image_field}.sha256 does not match {image_path.name}")
            sizes[side] = validate_png(image_path)

        if sizes["before"] != sizes["after"]:
            fail(
                f"{capture_id} dimensions differ: before={sizes['before']}, "
                f"after={sizes['after']}"
            )
        platform_capture_count[platform] += 1
        dimensions.append(
            {
                "id": capture_id,
                "width": sizes["before"][0],
                "height": sizes["before"][1],
            }
        )
        captures.append(item)

    missing_platforms = [
        platform for platform, count in platform_capture_count.items() if count == 0
    ]
    if missing_platforms:
        fail(f"no capture evidence for routed platform(s): {', '.join(missing_platforms)}")

    extras_raw = require_array(data.get("extras", []), "extras")
    for index, value in enumerate(extras_raw):
        field = f"extras[{index}]"
        item = require_object(value, field)
        require_exact_keys(
            item,
            {
                "id",
                "platform",
                "environment_id",
                "role",
                "file",
                "build_id",
                "sha256",
            },
            field,
            required={
                "id",
                "platform",
                "environment_id",
                "role",
                "file",
                "build_id",
                "sha256",
            },
        )
        extra_id = require_id(require_string(item, "id", field), f"{field}.id")
        if extra_id in seen_ids:
            fail(f"duplicate capture/extra id: {extra_id}")
        seen_ids.add(extra_id)
        platform = require_string(item, "platform", field)
        env_id = require_string(item, "environment_id", field)
        build_id = require_string(item, "build_id", field)
        require_string(item, "role", field)
        if (
            platform not in platforms
            or env_id not in environments
            or build_id not in builds
            or environments[env_id]["platform"] != platform
            or builds[build_id]["platform"] != platform
            or builds[build_id]["environment_id"] != env_id
        ):
            fail(f"{field} has an invalid platform/environment/build association")
        image_path = relative_file(root, item.get("file"), f"{field}.file")
        if image_path in used_paths:
            fail(f"screenshot path is reused: {image_path.name}")
        used_paths.add(image_path)
        expected_hash = require_sha256(
            require_string(item, "sha256", field), f"{field}.sha256"
        )
        if expected_hash != file_sha256(image_path):
            fail(f"{field}.sha256 does not match {image_path.name}")
        validate_png(image_path)

    limitations = require_array(data.get("limitations"), "limitations")
    if not all(isinstance(entry, str) and entry.strip() for entry in limitations):
        fail("limitations must contain non-empty strings")

    used_environment_ids = {
        str(capture["environment_id"]) for capture in captures
    } | {str(item["environment_id"]) for item in extras_raw}
    unused_environments = sorted(set(environments) - used_environment_ids)
    if unused_environments:
        fail(f"unused environment(s): {', '.join(unused_environments)}")
    used_build_ids = {
        str(capture[side]["build_id"])
        for capture in captures
        for side in ("before", "after")
    } | {str(item["build_id"]) for item in extras_raw}
    unused_builds = sorted(set(builds) - used_build_ids)
    if unused_builds:
        fail(f"unused build receipt(s): {', '.join(unused_builds)}")

    return {
        "status": "ok",
        "schema_version": 1,
        "platforms": platforms,
        "pairs": len(captures),
        "extras": len(extras_raw),
        "png_files": len(used_paths),
        "dimensions": dimensions,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    print(json.dumps(validate_manifest(args.manifest), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
