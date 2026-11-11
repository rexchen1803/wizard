#!/usr/bin/env python3
"""Exercise Wizard .deb creation and install guards using temporary fixtures."""

from __future__ import annotations

import gzip
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
import struct
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PACKAGER = ROOT / "scripts" / "package-release.py"
INSTALLER = ROOT / "scripts" / "install-wizard.sh"
APP_ID = "com.rex.wizardsystem"
BUILD = "20261111.37"
SHORT_VERSION = "0.2.0"
FINGERPRINT = "a" * 64
ICON_NAMES = ("Icon-76.png", "Icon-76@2x.png", "Icon-83.5@2x.png")
LAUNCH_IMAGE_SIZES = {
    "Default-Landscape.png": (1024, 768),
    "Default-Landscape@2x.png": (2048, 1536),
}
PASS_COUNT = 0
FAILURES: list[str] = []
PACKAGE_SPEC = importlib.util.spec_from_file_location("wizard_package_release", PACKAGER)
assert PACKAGE_SPEC and PACKAGE_SPEC.loader
PACKAGE_MODULE = importlib.util.module_from_spec(PACKAGE_SPEC)
PACKAGE_SPEC.loader.exec_module(PACKAGE_MODULE)


def check(name: str, condition: bool, detail: str = "") -> None:
    global PASS_COUNT
    if condition:
        PASS_COUNT += 1
    else:
        FAILURES.append(f"{name}: {detail or 'condition failed'}")


def run(*args: str, expected: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, text=True, capture_output=True)
    check("exit " + Path(args[0]).name, result.returncode == expected,
          f"expected {expected}, got {result.returncode}: {result.stderr.strip()}")
    return result


def make_app(path: Path, extra: bool = False) -> Path:
    path.mkdir(parents=True)
    info = {
        "CFBundleIdentifier": APP_ID,
        "CFBundleExecutable": "WizardSystem",
        "CFBundleShortVersionString": SHORT_VERSION,
        "CFBundleVersion": BUILD,
        "CFBundleIconFiles": list(ICON_NAMES),
        "UILaunchImageFile": "Default-Landscape",
        "UILaunchImages": [{"UILaunchImageName": "Default-Landscape"}],
        "WizardBuildChannel": "development",
        "WizardSourceFingerprint": FINGERPRINT,
    }
    (path / "Info.plist").write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML))
    executable = path / "WizardSystem"
    executable.write_bytes(b"synthetic universal executable for lipo fixture\n")
    executable.chmod(0o755)
    for icon_name in ICON_NAMES:
        shutil.copyfile(ROOT / "App" / "Resources" / icon_name, path / icon_name)
    for image_name in LAUNCH_IMAGE_SIZES:
        shutil.copyfile(ROOT / "App" / "Resources" / image_name, path / image_name)
    if extra:
        (path / "user-import.jpg").write_bytes(b"must not be packaged")
    return path


def write_fake_lipo(path: Path, output: str = "armv7 arm64") -> Path:
    path.write_text("#!/bin/sh\nprintf '%s\\n' '" + output + "'\n", encoding="utf-8")
    path.chmod(0o755)
    return path


def parse_ar(data: bytes) -> dict[str, bytes]:
    if not data.startswith(b"!<arch>\n"):
        raise AssertionError("missing Debian ar magic")
    result: dict[str, bytes] = {}
    offset = 8
    while offset < len(data):
        header = data[offset:offset + 60]
        if len(header) != 60 or header[58:60] != b"`\n":
            raise AssertionError("invalid ar member header")
        name = header[:16].decode("ascii").strip().rstrip("/")
        size = int(header[48:58].decode("ascii").strip())
        offset += 60
        result[name] = data[offset:offset + size]
        offset += size + (size % 2)
    return result


def read_tar(data: bytes) -> dict[str, bytes]:
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        return {entry.name: archive.extractfile(entry).read() for entry in archive.getmembers() if entry.isfile()}


def fixture_pkg_args(app: Path, output: Path, lipo: Path) -> list[str]:
    return [sys.executable, str(PACKAGER), "--app", str(app), "--out", str(output), "--lipo", str(lipo)]


def test_package_contents(temp: Path) -> None:
    app = make_app(temp / "WizardSystem.app")
    lipo = write_fake_lipo(temp / "lipo")
    output = temp / f"wizard_{SHORT_VERSION}-{BUILD}_iphoneos-arm.deb"
    result = run(*fixture_pkg_args(app, output, lipo))
    check("package created", output.is_file() and output.stat().st_size > 0)
    manifest_path = output.with_suffix(output.suffix + ".manifest.json")
    check("manifest created", manifest_path.is_file())
    manifest = json.loads(manifest_path.read_text())
    check("manifest artifact hash", manifest["artifact_sha256"] == hashlib.sha256(output.read_bytes()).hexdigest())
    check("manifest content counts", manifest["counts"] == {
        "app_bundle_files": 7,
        "reviewed_wizard_png_icons": 3,
        "reviewed_wizard_launch_images": 2,
        "installer_helpers": 1,
        "license_and_notice_files": 3,
        "rockstar_media_files": 0,
        "user_media_files": 0,
        "sdk_files": 0,
        "power_tweak_files": 0,
        "old_game_audio_or_font_files": 0,
    })
    check("manifest device gates", manifest["status"] == "packaged_not_device_accepted" and
          not manifest["device_install_verified"] and not manifest["device_removal_verified"])
    members = parse_ar(output.read_bytes())
    check("debian archive members", set(members) == {"debian-binary", "control.tar.gz", "data.tar.gz"})
    check("debian format", members.get("debian-binary") == b"2.0\n")
    control = read_tar(members["control.tar.gz"])
    data = read_tar(members["data.tar.gz"])
    check("control scripts", {"control", "preinst", "postinst", "prerm"}.issubset(control))
    check("control architecture", b"Architecture: iphoneos-arm\n" in control["control"])
    check("preinst exact allowlist", all(x in control["preinst"] for x in (b"iPad2,4:9.3.5", b"iPad3,4:10.3.3", b"iPad4,1:12.5.8")))
    check("preinst required device tools", all(x in control["preinst"] for x in (b"command -v ldid", b"command -v uicache", b"command -v killall", b"command -v dpkg")))
    check("postinst delegates to guarded helper", b"install-wizard.sh configure" in control["postinst"])
    check("prerm removes only on package removal", b"remove) exec /bin/sh" in control["prerm"] and b"upgrade|deconfigure) exit 0" in control["prerm"])
    check("prerm delegates exact build", f"install-wizard.sh remove {BUILD}".encode() in control["prerm"])
    check("helper unregisters only named app path", b'uicache -u "$TARGET"' in data["usr/lib/wizard-installer/install-wizard.sh"])
    check("staged app path", any(name.startswith(f"Applications/.wizard-package-payload-{BUILD}.app/") for name in data))
    check("app file list", len([name for name in data if name.startswith(f"Applications/.wizard-package-payload-{BUILD}.app/")]) == 7)
    check("installer helper", "usr/lib/wizard-installer/install-wizard.sh" in data)
    check("power tweak excluded", not any("WizardPower" in name or "Tweak" in name for name in data))
    check("license notices", all(name in data for name in (
        "usr/share/doc/wizard-system/LICENSE",
        "usr/share/doc/wizard-system/NOTICE",
        "usr/share/doc/wizard-system/Material-Icons-Apache-2.0.txt",
    )))
    content_names = tuple(data)
    forbidden_suffixes = (".jpg", ".jpeg", ".mp4", ".mkv", ".m4a", ".ttf", ".otf", ".sdk")
    allowed_pngs = set(ICON_NAMES) | set(LAUNCH_IMAGE_SIZES)
    unexpected_png = [name for name in content_names if name.lower().endswith(".png") and Path(name).name not in allowed_pngs]
    check("no media payloads", not unexpected_png and not any(name.lower().endswith(forbidden_suffixes) for name in content_names))
    check("package manifest in stdout", "artifact_sha256" in result.stdout)


def test_package_rejections(temp: Path) -> None:
    lipo = write_fake_lipo(temp / "lipo-bad-arch", "arm64")
    wrong_arch = make_app(temp / "wrong-arch.app")
    output = temp / f"wizard_{SHORT_VERSION}-{BUILD}_iphoneos-arm.deb"
    result = subprocess.run(fixture_pkg_args(wrong_arch, output, lipo), text=True, capture_output=True)
    check("reject wrong architecture", result.returncode != 0 and "armv7" in result.stderr)
    check("wrong architecture writes nothing", not output.exists())

    good_lipo = write_fake_lipo(temp / "lipo-good")
    extra = make_app(temp / "extra-file.app", extra=True)
    result = subprocess.run(fixture_pkg_args(extra, output, good_lipo), text=True, capture_output=True)
    check("reject extra app content", result.returncode != 0 and "allowlist" in result.stderr)

    changed_icon = make_app(temp / "changed-icon.app")
    (changed_icon / ICON_NAMES[0]).write_bytes(b"not the reviewed icon")
    result = subprocess.run(fixture_pkg_args(changed_icon, output, good_lipo), text=True, capture_output=True)
    check("reject icon mismatch", result.returncode != 0 and "differs from reviewed" in result.stderr)

    changed_launch = make_app(temp / "changed-launch.app")
    (changed_launch / "Default-Landscape.png").write_bytes(png_header(1024, 768))
    result = subprocess.run(fixture_pkg_args(changed_launch, output, good_lipo), text=True, capture_output=True)
    check("reject unbound launch image", result.returncode != 0 and "Default-Landscape.png" in result.stderr)

    no_fingerprint = make_app(temp / "no-fingerprint.app")
    plist_path = no_fingerprint / "Info.plist"
    info = plistlib.loads(plist_path.read_bytes())
    info.pop("WizardSourceFingerprint")
    plist_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML))
    result = subprocess.run(fixture_pkg_args(no_fingerprint, output, good_lipo), text=True, capture_output=True)
    check("reject unbound build", result.returncode != 0 and "WizardSourceFingerprint" in result.stderr)

    valid = make_app(temp / "valid-dry-run.app")
    result = subprocess.run(fixture_pkg_args(valid, output, good_lipo) + ["--dry-run"], text=True, capture_output=True)
    check("package dry-run succeeds", result.returncode == 0, result.stderr)
    check("package dry-run writes nothing", not output.exists() and not output.with_suffix(output.suffix + ".manifest.json").exists())


def make_installer_fixture(root: Path, existing: bool = False) -> Path:
    apps = root / "Applications"
    apps.mkdir(parents=True)
    app = make_app(apps / f".wizard-package-payload-{BUILD}.app")
    if existing:
        shutil.copytree(app, apps / "WizardSystem.app")
    return root


def installer_dryrun(root: Path, model: str = "iPad2,4", ios_version: str = "9.3.5", uid: str = "0", *tail: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([
        "/bin/sh", str(INSTALLER), "--dry-run", "--root", str(root),
        "--model", model, "--ios-version", ios_version, "--uid", uid, *tail,
    ], text=True, capture_output=True)


def test_install_guards(temp: Path) -> None:
    fresh = make_installer_fixture(temp / "fresh")
    before = sorted((path.relative_to(fresh).as_posix(), hashlib.sha256(path.read_bytes()).hexdigest())
                    for path in fresh.rglob("*") if path.is_file())
    result = installer_dryrun(fresh, "iPad2,4", "9.3.5", "0", "configure", BUILD)
    check("fresh install preview", result.returncode == 0 and "DRY RUN: install" in result.stdout, result.stderr)
    after = sorted((path.relative_to(fresh).as_posix(), hashlib.sha256(path.read_bytes()).hexdigest())
                   for path in fresh.rglob("*") if path.is_file())
    check("dry-run makes no changes", before == after)

    update = make_installer_fixture(temp / "update", existing=True)
    result = installer_dryrun(update, "iPad4,1", "12.5.8", "0", "configure", BUILD)
    check("existing update preview", result.returncode == 0 and "DRY RUN: update" in result.stdout, result.stderr)
    check("data and preferences preservation statement", "preserve /var/mobile/Media/iPadWizard/app" in result.stdout)
    remove_root = make_installer_fixture(temp / "remove", existing=True)
    app_path = remove_root / "Applications" / "WizardSystem.app"
    (remove_root / "Applications" / "WizardSystem.rollback-20261111.30-20261110T120000Z.app").mkdir()
    media = remove_root / "var" / "mobile" / "Media" / "iPadWizard" / "app" / "assets" / "user"
    media.mkdir(parents=True)
    (media / "user-import.jpg").write_bytes(b"fixture import")
    prefs = remove_root / "var" / "mobile" / "Library" / "Preferences"
    prefs.mkdir(parents=True)
    (prefs / "com.rex.wizardsystem.plist").write_bytes(b"fixture preferences")
    protected_before = sorted((path.relative_to(remove_root).as_posix(), hashlib.sha256(path.read_bytes()).hexdigest())
                              for path in remove_root.rglob("*") if path.is_file())
    result = installer_dryrun(remove_root, "iPad2,4", "9.3.5", "0", "remove", BUILD)
    check("matching package removal preview", result.returncode == 0 and "unregister" in result.stdout and "WizardSystem.uninstalled-" in result.stdout, result.stderr)
    protected_after = sorted((path.relative_to(remove_root).as_posix(), hashlib.sha256(path.read_bytes()).hexdigest())
                             for path in remove_root.rglob("*") if path.is_file())
    check("remove dry-run preserves app media preferences and rollback", protected_before == protected_after and app_path.is_dir())
    check("remove preview preserves imports and preferences", "preserve /var/mobile/Media/iPadWizard/app, preferences" in result.stdout)

    mismatched = make_installer_fixture(temp / "remove-mismatch", existing=True)
    info_path = mismatched / "Applications" / "WizardSystem.app" / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleVersion"] = "20261111.36"
    info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML))
    result = installer_dryrun(mismatched, "iPad4,1", "12.5.8", "0", "remove", BUILD)
    check("preserve app with nonmatching build", result.returncode == 0 and "does not match package build" in result.stdout)

    for model, version, uid, label in (
        ("iPhone10,1", "12.5.8", "0", "reject unsupported model"),
        ("iPad4,1", "12.5.7", "0", "reject wrong OS"),
        ("iPad2,4", "9.3.5", "501", "reject non-root installer"),
    ):
        rejected = make_installer_fixture(temp / label.replace(" ", "-"))
        result = installer_dryrun(rejected, model, version, uid, "configure", BUILD)
        check(label, result.returncode != 0 and "Wizard installer:" in result.stderr)

    missing = temp / "missing-payload"
    (missing / "Applications").mkdir(parents=True)
    result = installer_dryrun(missing, "iPad2,4", "9.3.5", "0", "configure", BUILD)
    check("reject missing payload", result.returncode != 0 and "payload" in result.stderr)

    link_root = temp / "symlink-applications"
    link_root.mkdir()
    outside = temp / "outside-applications"
    outside.mkdir()
    (link_root / "Applications").symlink_to(outside, target_is_directory=True)
    result = installer_dryrun(link_root, "iPad2,4", "9.3.5", "0", "configure", BUILD)
    check("reject rootless-style Applications link", result.returncode != 0 and "rootful" in result.stderr)

    rollback_root = make_installer_fixture(temp / "rollback", existing=True)
    backup = rollback_root / "Applications" / "WizardSystem.rollback-20261111.30-20261110T120000Z.app"
    shutil.copytree(rollback_root / "Applications" / f".wizard-package-payload-{BUILD}.app", backup)
    result = installer_dryrun(rollback_root, "iPad2,4", "9.3.5", "0", "rollback", str(backup))
    check("rollback preview", result.returncode == 0 and "DRY RUN: restore" in result.stdout, result.stderr)
    uninstalled = rollback_root / "Applications" / "WizardSystem.uninstalled-20261111.37-20261112T120000Z.app"
    shutil.copytree(rollback_root / "Applications" / f".wizard-package-payload-{BUILD}.app", uninstalled)
    result = installer_dryrun(rollback_root, "iPad2,4", "9.3.5", "0", "rollback", str(uninstalled))
    check("uninstalled bundle can be restored", result.returncode == 0 and "DRY RUN: restore" in result.stdout, result.stderr)


def png_header(width: int, height: int) -> bytes:
    return b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", width, height) + b"\x08\x06\x00\x00\x00" + b"\x00\x00\x00\x00"


def test_launch_image_dimensions() -> None:
    for name, expected in LAUNCH_IMAGE_SIZES.items():
        fixture = png_header(*expected)
        try:
            PACKAGE_MODULE.validate_png_dimensions(fixture, name, expected)
            valid = True
        except PACKAGE_MODULE.PackageError:
            valid = False
        check("generated launch-image IHDR " + name, valid)
    try:
        PACKAGE_MODULE.validate_png_dimensions(png_header(768, 1024), "Default-Landscape.png", (1024, 768))
        rejected = False
    except PACKAGE_MODULE.PackageError:
        rejected = True
    check("reject wrong launch-image dimensions", rejected)


def main() -> int:
    if not (ROOT / "App" / "Resources").is_dir():
        print("package-regressions: App/Resources must contain the reviewed release icons", file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix="wizard-package-regressions-") as directory:
        root = Path(directory)
        for name, function in (
            ("contents", test_package_contents),
            ("rejections", test_package_rejections),
            ("install", test_install_guards),
        ):
            fixture = root / name
            fixture.mkdir()
            function(fixture)
        test_launch_image_dimensions()
    if FAILURES:
        print(json.dumps({"suite": "package_and_dry_run_fixtures", "status": "failed", "passed": PASS_COUNT, "failed": len(FAILURES), "failures": FAILURES}, indent=2))
        return 1
    print(json.dumps({"suite": "package_and_dry_run_fixtures", "status": "passed", "checks": PASS_COUNT, "failed": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
