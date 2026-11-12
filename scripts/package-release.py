#!/usr/bin/env python3
"""Package a reviewed unsigned Wizard build as a guarded rootful-iPad .deb."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import struct
import subprocess
import sys
import tarfile
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
ICON_SIZES = {
    "Icon-76.png": (76, 76),
    "Icon-76@2x.png": (152, 152),
    "Icon-83.5@2x.png": (167, 167),
}
LAUNCH_IMAGE_SIZES = {
    "Default-Landscape.png": (1024, 768),
    "Default-Landscape@2x.png": (2048, 1536),
}
ARTWORK_FILES = ("ViceCity.jpg",)
DISPLAY_FONT_FILES = ("Anton-Regular.ttf",)
DISPLAY_FONT_LICENSE_FILES = ("Anton-OFL.txt",)
UI_APP_FONT_FILES = ["Anton-Regular.ttf"]
APP_ID = "com.rex.wizardsystem"
APP_EXECUTABLE = "WizardSystem"
PACKAGE = "com.rex.wizardsystem"
ARCHITECTURE = "iphoneos-arm"
INSTALL_HELPER = ROOT / "scripts" / "install-wizard.sh"


class PackageError(RuntimeError):
    pass


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_regular(path: Path) -> bytes:
    try:
        mode = path.lstat().st_mode
    except OSError as exc:
        raise PackageError(f"required regular file is missing: {path.name}") from exc
    if not stat.S_ISREG(mode):
        raise PackageError(f"expected a regular file, not a symlink or special file: {path.name}")
    return path.read_bytes()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, help="new universal WizardSystem.app from build-ipad.sh")
    parser.add_argument("--out", type=Path, required=True, help="new output .deb path; uses the published filename")
    parser.add_argument("--lipo", default=os.environ.get("LIPO", "/usr/bin/lipo"), help="lipo executable used to verify the universal binary")
    parser.add_argument("--dry-run", action="store_true", help="validate and print the package manifest without writing files")
    return parser.parse_args()


def png_dimensions(data: bytes, name: str) -> tuple[int, int]:
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise PackageError(f"{name} is not a valid PNG image")
    return struct.unpack(">II", data[16:24])


def validate_png_dimensions(data: bytes, name: str, expected: tuple[int, int]) -> None:
    dimensions = png_dimensions(data, name)
    if dimensions != expected:
        raise PackageError(f"{name} must be {expected[0]}x{expected[1]} pixels")


def validate_build(app_path: Path, lipo: str) -> tuple[dict[str, object], dict[str, bytes], str, str]:
    if app_path.is_symlink() or not app_path.is_dir():
        raise PackageError("--app must name a real WizardSystem.app directory")
    app_path = app_path.absolute()
    entries = list(app_path.iterdir())
    info_data = read_regular(app_path / "Info.plist")
    try:
        info = plistlib.loads(info_data)
    except Exception as exc:
        raise PackageError("app Info.plist is invalid") from exc
    if not isinstance(info, dict):
        raise PackageError("app Info.plist must contain a dictionary")
    if info.get("CFBundleIdentifier") != APP_ID:
        raise PackageError(f"app bundle identifier must be {APP_ID}")
    if info.get("CFBundleExecutable") != APP_EXECUTABLE:
        raise PackageError(f"app executable must be {APP_EXECUTABLE}")
    short_version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    version_pattern = re.compile(r"^[0-9]+(?:\.[0-9]+)*$")
    if not isinstance(short_version, str) or not version_pattern.fullmatch(short_version):
        raise PackageError("CFBundleShortVersionString must contain numeric version components")
    if not isinstance(build, str) or not version_pattern.fullmatch(build):
        raise PackageError("CFBundleVersion must contain numeric version components")
    if info.get("WizardBuildChannel") != "development":
        raise PackageError("unexpected Wizard build channel; review the app candidate before packaging")
    fingerprint = info.get("WizardSourceFingerprint")
    if not isinstance(fingerprint, str) or not re.fullmatch(r"[0-9a-f]{64}", fingerprint):
        raise PackageError("WizardSourceFingerprint is missing or malformed")
    icon_list = info.get("CFBundleIconFiles")
    if not isinstance(icon_list, list) or len(icon_list) != len(ICON_SIZES) or set(icon_list) != set(ICON_SIZES):
        raise PackageError("Info.plist must reference exactly the three reviewed Wizard PNG icons")
    if info.get("UIAppFonts") != UI_APP_FONT_FILES:
        raise PackageError("Info.plist UIAppFonts must register exactly the reviewed Anton-Regular.ttf display font")
    launch_names = info.get("UILaunchImages")
    if (info.get("UILaunchImageFile") != "Default-Landscape" or not isinstance(launch_names, list)
            or not any(isinstance(item, dict) and item.get("UILaunchImageName") == "Default-Landscape" for item in launch_names)):
        raise PackageError("Info.plist must reference the reviewed Default-Landscape launch images")

    expected_names = {
        "Info.plist", APP_EXECUTABLE, *ICON_SIZES, *LAUNCH_IMAGE_SIZES,
        *ARTWORK_FILES, *DISPLAY_FONT_FILES, *DISPLAY_FONT_LICENSE_FILES,
    }
    actual_names = set()
    for entry in entries:
        if entry.is_symlink() or not entry.is_file():
            raise PackageError("app bundle may contain only regular root-level files")
        actual_names.add(entry.name)
    if actual_names != expected_names:
        extra = sorted(actual_names - expected_names)
        missing = sorted(expected_names - actual_names)
        details = []
        if extra:
            details.append("unexpected=" + ",".join(extra))
        if missing:
            details.append("missing=" + ",".join(missing))
        raise PackageError("app bundle file allowlist mismatch (" + "; ".join(details) + ")")

    resource_root = ROOT / "App" / "Resources"
    if resource_root.is_symlink() or not resource_root.is_dir():
        raise PackageError("reviewed App/Resources directory is missing")
    app_files: dict[str, bytes] = {"Info.plist": info_data}
    for name, expected_size in {**ICON_SIZES, **LAUNCH_IMAGE_SIZES}.items():
        resource_data = read_regular(resource_root / name)
        app_data = read_regular(app_path / name)
        if app_data != resource_data:
            raise PackageError(f"built app resource differs from reviewed App/Resources/{name}")
        validate_png_dimensions(app_data, name, expected_size)
        app_files[name] = app_data

    for name in ARTWORK_FILES:
        resource_data = read_regular(resource_root / name)
        app_data = read_regular(app_path / name)
        if app_data != resource_data:
            raise PackageError(f"built app artwork differs from reviewed App/Resources/{name}")
        if not app_data.startswith(b"\xff\xd8\xff") or not app_data.endswith(b"\xff\xd9"):
            raise PackageError(f"{name} must contain the reviewed JPEG artwork")
        app_files[name] = app_data

    for name in (*DISPLAY_FONT_FILES, *DISPLAY_FONT_LICENSE_FILES):
        resource_data = read_regular(resource_root / name)
        app_data = read_regular(app_path / name)
        if app_data != resource_data:
            raise PackageError(f"built app resource differs from reviewed App/Resources/{name}")
        if not app_data:
            raise PackageError(f"{name} must not be empty")
        app_files[name] = app_data

    binary = read_regular(app_path / APP_EXECUTABLE)
    if not (stat.S_IMODE((app_path / APP_EXECUTABLE).stat().st_mode) & 0o111):
        raise PackageError("WizardSystem must be executable")
    try:
        result = subprocess.run([lipo, str(app_path / APP_EXECUTABLE), "-archs"], check=True, capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise PackageError("lipo could not verify the WizardSystem executable") from exc
    architectures = sorted(set(result.stdout.split()))
    if architectures != ["arm64", "armv7"]:
        raise PackageError("WizardSystem must contain exactly armv7 and arm64 slices")
    app_files[APP_EXECUTABLE] = binary
    return info, app_files, build, " ".join(architectures)


def tar_bytes(files: Iterable[tuple[str, bytes, int]], directories: Iterable[str]) -> bytes:
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for directory in sorted(set(directories)):
            name = directory.rstrip("/") + "/"
            member = tarfile.TarInfo(name)
            member.type = tarfile.DIRTYPE
            member.mode = 0o755
            member.uid = member.gid = 0
            member.uname = member.gname = "root"
            member.mtime = 0
            archive.addfile(member)
        for name, data, mode in sorted(files, key=lambda item: item[0]):
            member = tarfile.TarInfo(name)
            member.size = len(data)
            member.mode = mode
            member.uid = member.gid = 0
            member.uname = member.gname = "root"
            member.mtime = 0
            archive.addfile(member, io.BytesIO(data))
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode="wb", filename="", mtime=0, compresslevel=9) as stream:
        stream.write(raw.getvalue())
    return compressed.getvalue()


def debian_ar(members: list[tuple[str, bytes]]) -> bytes:
    output = bytearray(b"!<arch>\n")
    for name, content in members:
        if len(name) > 15 or not name.endswith("/"):
            raise PackageError("internal ar member name is too long")
        header = f"{name:<16}{0:<12}{0:<6}{0:<6}{0o100644:<8o}{len(content):<10}`\n".encode("ascii")
        if len(header) != 60:
            raise PackageError("internal ar header length is invalid")
        output.extend(header)
        output.extend(content)
        if len(content) % 2:
            output.extend(b"\n")
    return bytes(output)


def render_preinst(build: str) -> bytes:
    return f'''#!/bin/sh
set -eu
[ "${{1:-}}" = install ] || [ "${{1:-}}" = upgrade ] || exit 0
fail() {{ echo "Wizard installer: $*" >&2; exit 1; }}
MODEL=$(sysctl -n hw.machine 2>/dev/null) || fail "could not read hardware model"
VERSION=$(sw_vers -productVersion 2>/dev/null) || fail "could not read iOS version"
case "$MODEL:$VERSION" in
  iPad2,4:9.3.5|iPad3,4:10.3.3|iPad4,1:12.5.8) ;;
  *) fail "unsupported iPad model or iOS version; see docs/INSTALL.md" ;;
esac
[ "$(id -u 2>/dev/null)" = 0 ] || fail "rootful package installation is required"
[ -d /Applications ] && [ ! -L /Applications ] && [ -w /Applications ] || fail "writable rootful /Applications is required"
command -v dpkg >/dev/null 2>&1 || fail "rootful Debian package environment is required"
command -v ldid >/dev/null 2>&1 || fail "ldid is required to sign this unsigned build"
command -v uicache >/dev/null 2>&1 || fail "uicache is required to register or refresh Wizard"
command -v killall >/dev/null 2>&1 || fail "killall is required for a controlled Wizard update"
if [ -e /Applications/WizardSystem.app ] || [ -L /Applications/WizardSystem.app ]; then
  [ -d /Applications/WizardSystem.app ] && [ ! -L /Applications/WizardSystem.app ] || fail "existing Wizard path is not a directory"
  [ -f /Applications/WizardSystem.app/Info.plist ] && [ ! -L /Applications/WizardSystem.app/Info.plist ] || fail "existing Wizard Info.plist is missing"
  grep -Fq '<string>com.rex.wizardsystem</string>' /Applications/WizardSystem.app/Info.plist || fail "existing app bundle identifier is not Wizard"
fi
[ ! -e /Applications/.wizard-package-payload-{build}.app ] && [ ! -L /Applications/.wizard-package-payload-{build}.app ] || fail "package payload path already exists"
exit 0
'''.encode("utf-8")


def render_prerm(build: str) -> bytes:
    return f'''#!/bin/sh
set -e
case "${{1:-}}" in
  remove) exec /bin/sh /usr/lib/wizard-installer/install-wizard.sh remove {build} ;;
  upgrade|deconfigure) exit 0 ;;
  *) exit 0 ;;
esac
'''.encode("ascii")


def create_package(info: dict[str, object], app_files: dict[str, bytes], build: str, architectures: str) -> tuple[bytes, dict[str, object]]:
    short_version = str(info["CFBundleShortVersionString"])
    package_version = f"{short_version}-{build}"
    payload_dir = f"Applications/.wizard-package-payload-{build}.app"
    helper = read_regular(INSTALL_HELPER)
    license_files = {
        "usr/share/doc/wizard-system/LICENSE": read_regular(ROOT / "LICENSE"),
        "usr/share/doc/wizard-system/NOTICE": read_regular(ROOT / "NOTICE"),
        "usr/share/doc/wizard-system/Material-Icons-Apache-2.0.txt": read_regular(ROOT / "licenses" / "Material-Icons-Apache-2.0.txt"),
    }
    payload_files: list[tuple[str, bytes, int]] = []
    payload_files.extend((f"{payload_dir}/{name}", data, 0o755 if name == APP_EXECUTABLE else 0o644) for name, data in app_files.items())
    payload_files.append(("usr/lib/wizard-installer/install-wizard.sh", helper, 0o755))
    payload_files.extend((name, data, 0o644) for name, data in license_files.items())
    data_dirs = {
        "Applications",
        payload_dir,
        "usr",
        "usr/lib",
        "usr/lib/wizard-installer",
        "usr/share",
        "usr/share/doc",
        "usr/share/doc/wizard-system",
    }
    control_text = (
        f"Package: {PACKAGE}\n"
        f"Name: Wizard\n"
        f"Version: {package_version}\n"
        f"Architecture: {ARCHITECTURE}\n"
        "Maintainer: Rex Chen\n"
        "Section: System\n"
        "Priority: optional\n"
        "Description: Native Wizard clock, wallpaper gallery, and media display for prepared legacy iPads\n"
        " This preview package targets existing rootful jailbreak environments in the documented allowlist.\n"
        " It does not install a jailbreak, power tweak, Rockstar media, or user data.\n"
    ).encode("ascii")
    postinst = f'''#!/bin/sh
set -e
case "${{1:-}}" in
  configure) exec /bin/sh /usr/lib/wizard-installer/install-wizard.sh configure {build} ;;
  *) exit 0 ;;
esac
'''.encode("ascii")
    control_files = [
        ("control", control_text, 0o644),
        ("preinst", render_preinst(build), 0o755),
        ("postinst", postinst, 0o755),
        ("prerm", render_prerm(build), 0o755),
    ]
    control_tar = tar_bytes(control_files, ())
    data_tar = tar_bytes(payload_files, data_dirs)
    deb = debian_ar([("debian-binary/", b"2.0\n"), ("control.tar.gz/", control_tar), ("data.tar.gz/", data_tar)])
    fingerprint = info.get("WizardSourceFingerprint", "")
    manifest: dict[str, object] = {
        "schema": "wizard.deb-manifest.v1",
        "status": "packaged_not_device_accepted",
        "package": PACKAGE,
        "package_version": package_version,
        "architecture": ARCHITECTURE,
        "bundle_identifier": APP_ID,
        "app_version": short_version,
        "app_build": build,
        "architectures": architectures.split(),
        "source_fingerprint": fingerprint,
        "artifact_sha256": sha256(deb),
        "artifact_size_bytes": len(deb),
        "payload_root": "/Applications/WizardSystem.app",
        "package_files": sorted([name for name, _data, _mode in payload_files]),
        "sha256": {name: sha256(data) for name, data, _mode in sorted(payload_files)},
        "counts": {
            "app_bundle_files": len(app_files),
            "reviewed_wizard_png_icons": len(ICON_SIZES),
            "reviewed_wizard_launch_images": len(LAUNCH_IMAGE_SIZES),
            "reviewed_display_font_files": len(DISPLAY_FONT_FILES),
            "bundled_font_license_files": len(DISPLAY_FONT_LICENSE_FILES),
            "installer_helpers": 1,
            "license_and_notice_files": len(license_files),
            "rockstar_media_files": len(ARTWORK_FILES),
            "user_media_files": 0,
            "sdk_files": 0,
            "power_tweak_files": 0,
            # Reserved for excluded game-origin assets; the reviewed OFL display
            # font and its license are counted separately above.
            "old_game_audio_or_font_files": 0,
        },
        "device_install_verified": False,
        "device_removal_verified": False,
        "code_signing_on_host": False,
    }
    return deb, manifest


def write_exclusive(path: Path, data: bytes) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags, 0o644)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data)
    path.chmod(0o644)


def main() -> int:
    args = parse_args()
    output = args.out if args.out.is_absolute() else Path.cwd() / args.out
    if output.suffix != ".deb":
        raise PackageError("--out must name a .deb file")
    info, app_files, build, architectures = validate_build(args.app, args.lipo)
    deb, manifest = create_package(info, app_files, build, architectures)
    expected_name = f"wizard_{info['CFBundleShortVersionString']}-{build}_{ARCHITECTURE}.deb"
    if output.name != expected_name:
        raise PackageError(f"--out must use the published filename: {expected_name}")
    manifest_path = output.with_suffix(output.suffix + ".manifest.json")
    manifest_data = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")
    if args.dry_run:
        print(json.dumps({"artifact": output.name, **manifest}, indent=2, sort_keys=True))
        return 0
    if output.exists() or output.is_symlink() or manifest_path.exists() or manifest_path.is_symlink():
        raise PackageError("artifact or manifest output already exists; choose a new directory")
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        write_exclusive(output, deb)
        write_exclusive(manifest_path, manifest_data)
    except Exception:
        for created in (manifest_path, output):
            try:
                created.unlink()
            except OSError:
                pass
        raise
    print(json.dumps({"artifact": str(output), "manifest": str(manifest_path), **manifest}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, PackageError) as exc:
        print(f"package-release: {exc}", file=sys.stderr)
        raise SystemExit(2)
