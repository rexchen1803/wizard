#!/usr/bin/env python3
"""Exercise repository checks against small, isolated source-export fixtures."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import runpy
import struct
import subprocess
import sys
import tempfile
import zlib


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "scripts/check-repository.py"


def write_export(root: Path, include_media: bool = False) -> None:
    (root / "docs").mkdir(parents=True)
    (root / "LICENSE").write_text("MIT License\nPermission is hereby granted to use this software.\n")
    (root / "NOTICE").write_text(
        "Rockstar Games media retains separate rights and is not covered by the Wizard MIT License.\n"
    )
    (root / "THIRD_PARTY.md").write_text(
        "The MIT license applies to Wizard-authored code only. Rockstar media has separate rights.\n"
    )
    (root / "README.md").write_text(
        "# Example\n\n[Guide](docs/guide.md#checked-step)\n\n![Demo](demo.png)\n\n"
        "https://github.com/google/material-design-icons/blob/10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7/src/action/home/materialicons/24px.svg\n"
    )
    (root / "docs/guide.md").write_text("# Checked Step\n\nLocal source and build notes.\n")
    (root / "demo.png").write_bytes(b"small test fixture, not a real image")
    if include_media:
        media_dir = root / "assets/media"
        media_dir.mkdir(parents=True)
        (media_dir / "ATTRIBUTION.md").write_text(
            "Rockstar Games and other rights holders own this GTA VI material. "
            "It is not covered by the Wizard MIT license.\n"
        )
        manifest = {
            "schema_version": 1,
            "release_tag": "v0.2.0-preview.1",
            "copyright": {
                "owner": "Rockstar Games and applicable rights holders",
                "scope": "GTA VI material; not covered by the Wizard MIT license",
            },
            "release_assets": [
                {
                    "id": "gallery",
                    "name": "wizard-gta6-gallery-20261112.zip",
                    "download_url": "https://github.com/rexchen1803/wizard/releases/download/"
                    "v0.2.0-preview.1/wizard-gta6-gallery-20261112.zip",
                    "bytes": 4,
                    "sha256": hashlib.sha256(b"pack").hexdigest(),
                    "files": 1,
                    "image_count": 1,
                    "video_count": 0,
                    "subtitle_count": 0,
                }
            ],
        }
        (media_dir / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
    paths = sorted(path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file())
    (root / "OPEN_SOURCE_EXPORT_REPORT.json").write_text(
        json.dumps({"included_files": paths}, indent=2) + "\n"
    )


def run(root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CHECKER), "--root", str(root)],
        text=True,
        capture_output=True,
        check=False,
    )


def refresh_report(root: Path) -> None:
    report_path = root / "OPEN_SOURCE_EXPORT_REPORT.json"
    report = json.loads(report_path.read_text())
    report["included_files"] = sorted(
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and path.name != "OPEN_SOURCE_EXPORT_REPORT.json"
    )
    report_path.write_text(json.dumps(report))


with tempfile.TemporaryDirectory(prefix="wizard-repository-checks-") as temporary:
    base = Path(temporary)
    valid = base / "valid-export"
    valid.mkdir()
    write_export(valid, include_media=True)
    result = run(valid)
    assert result.returncode == 0, result.stdout + result.stderr

    broken_link = base / "broken-link"
    broken_link.mkdir()
    write_export(broken_link)
    (broken_link / "README.md").write_text("[Missing](docs/missing.md)\n")
    refresh_report(broken_link)
    result = run(broken_link)
    assert result.returncode == 1 and "broken local link" in result.stderr, result.stdout + result.stderr

    unlisted = base / "unlisted-file"
    unlisted.mkdir()
    write_export(unlisted)
    (unlisted / "not-in-export-report.txt").write_text("unexpected")
    result = run(unlisted)
    assert result.returncode == 2 and "unlisted files" in result.stderr, result.stdout + result.stderr

    secret = base / "credential"
    secret.mkdir()
    write_export(secret)
    sample_token = "ghp_" + "a" * 30
    (secret / "README.md").write_text("Do not publish this token: " + sample_token + "\n")
    refresh_report(secret)
    result = run(secret)
    assert result.returncode == 1 and "credential or private key" in result.stderr, result.stdout + result.stderr

    gta_payload = base / "gta-payload"
    gta_payload.mkdir()
    write_export(gta_payload)
    (gta_payload / "gta6-trailer.mp4").write_bytes(b"not a real video")
    refresh_report(gta_payload)
    result = run(gta_payload)
    assert result.returncode == 1 and "Rockstar media payload" in result.stderr, result.stdout + result.stderr

    for label, local_path in (
        ("unix-home", "/" + "home/" + "sample" + "/Library/Secrets"),
        ("mac-home", "/" + "Users/" + "sample" + "/Library/Secrets"),
    ):
        workstation_path = base / label
        workstation_path.mkdir()
        write_export(workstation_path)
        (workstation_path / "README.md").write_text("Local file: " + local_path + "\n")
        refresh_report(workstation_path)
        result = run(workstation_path)
        assert result.returncode == 1 and "workstation home path" in result.stderr, result.stdout + result.stderr

    tracked_only = base / "tracked-only-checkout"
    tracked_only.mkdir()
    write_export(tracked_only)
    checker_copy = tracked_only / "scripts/check-repository.py"
    checker_copy.parent.mkdir()
    shutil.copyfile(CHECKER, checker_copy)
    subprocess.run(["git", "init", "--quiet", str(tracked_only)], check=True)
    subprocess.run(
        [
            "git", "-C", str(tracked_only), "add", "LICENSE", "NOTICE", "THIRD_PARTY.md",
            "README.md", "docs/guide.md", "demo.png", "scripts/check-repository.py",
        ],
        check=True,
    )
    private = tracked_only / ".private-audit"
    private.mkdir()
    (private / "untracked-secret.md").write_text("ghp_" + "b" * 30)
    result = subprocess.run(
        [sys.executable, str(checker_copy)], text=True, capture_output=True, check=False
    )
    assert result.returncode == 0, result.stdout + result.stderr

scanner = runpy.run_path(str(ROOT / "scripts/prepare-open-source.py"))["scan_bytes"]
# Real, unchanged capture: its compressed pixels contain a six-byte sequence
# resembling a contact address. Metadata and decoded visual content are separate.
capture = ROOT / "assets/demo/screens/city-calendar.png"
assert scanner(capture.read_bytes()) == {}
address = b"sample" + bytes([64]) + b"example.invalid"
assert scanner(address).get("email_address") == 1


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))


prefix = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
suffix = png_chunk(b"IDAT", zlib.compress(b"\0\0\0\0")) + png_chunk(b"IEND", b"")
for kind, payload in (
    (b"tEXt", b"Comment\0" + address),
    (b"zTXt", b"Comment\0\0" + zlib.compress(address)),
    (b"iTXt", b"Comment\0\1\0\0\0" + zlib.compress(address)),
):
    assert scanner(prefix + png_chunk(kind, payload) + suffix).get("email_address") == 1, kind
assert scanner(prefix + png_chunk(b"zTXt", b"Comment\0\0invalid") + suffix).get("unreadable_png_metadata") == 1
assert scanner(prefix + png_chunk(b"zTXt", b"Comment\0\0" + zlib.compress(b"ok") + zlib.compress(address)) + suffix).get("unreadable_png_metadata") == 1

print("Repository and export scanner regressions passed (15 isolated cases).")
