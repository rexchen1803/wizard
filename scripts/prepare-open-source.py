#!/usr/bin/env python3
"""Create a reviewed Wizard source-and-documentation export from a fixed allowlist."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import stat
import sys
from pathlib import Path
from typing import Optional


SCRIPT_ROOT = Path(__file__).resolve().parents[1]
PUBLIC_APP = SCRIPT_ROOT / "App"

# Keep this explicit. New helper headers require an individual review and entry here.
APP_ALLOWLIST = (
    "main.m",
    "Info.plist",
    "IWMediaCatalog.h",
    "IWHTTPTransport.h",
    "IWWeatherService.h",
    "IWWeatherService.m",
    "IWFrameProbe.h",
    "WizardPowerTweak/Tweak.xm",
    "WizardPowerTweak/WizardPower.plist",
    "WizardPowerTweak/README.md",
    "Resources/Icon.svg",
    "Resources/Icon-76.png",
    "Resources/Icon-76@2x.png",
    "Resources/Icon-83.5@2x.png",
    "Resources/Launch.svg",
    "Resources/Default-Landscape.png",
    "Resources/Default-Landscape@2x.png",
    "Resources/ViceCity.jpg",
    "Resources/Anton-Regular.ttf",
    "Resources/Anton-OFL.txt",
)

ROOT_ALLOWLIST = (
    ("README.en.md", "README.en.md"),
    ("assets/demo/README.en.md", "assets/demo/README.en.md"),
    ("assets/readme/hero-en.svg", "assets/readme/hero-en.svg"),
    ("assets/readme/hero-en-mobile.svg", "assets/readme/hero-en-mobile.svg"),
    ("assets/readme/showcase-en.svg", "assets/readme/showcase-en.svg"),
    ("assets/readme/showcase-en-mobile.svg", "assets/readme/showcase-en-mobile.svg"),
    ("assets/readme/collection-en.svg", "assets/readme/collection-en.svg"),
    ("assets/readme/collection-en-mobile.svg", "assets/readme/collection-en-mobile.svg"),
    ("assets/readme/install-en.svg", "assets/readme/install-en.svg"),
    ("assets/readme/install-en-mobile.svg", "assets/readme/install-en-mobile.svg"),
    ("assets/readme/agent-en.svg", "assets/readme/agent-en.svg"),
    ("assets/readme/agent-en-mobile.svg", "assets/readme/agent-en-mobile.svg"),
    ("assets/readme/source-en.svg", "assets/readme/source-en.svg"),
    ("assets/readme/source-en-mobile.svg", "assets/readme/source-en-mobile.svg"),
    ("assets/readme/footer-en.svg", "assets/readme/footer-en.svg"),
    ("assets/readme/footer-en-mobile.svg", "assets/readme/footer-en-mobile.svg"),
    ("docs/en/README.md", "docs/en/README.md"),
    ("docs/en/INSTALL.md", "docs/en/INSTALL.md"),
    ("docs/en/AGENT-INSTALL.md", "docs/en/AGENT-INSTALL.md"),
    ("docs/en/GTA6-MATERIALS.md", "docs/en/GTA6-MATERIALS.md"),
    ("docs/zh-CN/README.md", "docs/zh-CN/README.md"),
    ("docs/zh-CN/COMPATIBILITY.md", "docs/zh-CN/COMPATIBILITY.md"),
    ("docs/zh-CN/DEVELOPMENT.md", "docs/zh-CN/DEVELOPMENT.md"),
    ("docs/zh-CN/THIRD_PARTY.md", "docs/zh-CN/THIRD_PARTY.md"),
    ("docs/zh-CN/PRIVACY.md", "docs/zh-CN/PRIVACY.md"),
    ("docs/zh-CN/CONTRIBUTING.md", "docs/zh-CN/CONTRIBUTING.md"),
    ("docs/zh-CN/SECURITY.md", "docs/zh-CN/SECURITY.md"),
    ("docs/zh-CN/CHANGELOG.md", "docs/zh-CN/CHANGELOG.md"),
    ("PRODUCT.md", "PRODUCT.md"),
    ("DESIGN.md", "DESIGN.md"),
    ("scripts/build-preview.py", "scripts/build-preview.py"),
    ("scripts/build-showcase.py", "scripts/build-showcase.py"),
    (".gitignore", ".gitignore"),
    ("README.md", "README.md"),
    ("LICENSE", "LICENSE"),
    ("NOTICE", "NOTICE"),
    ("scripts/build-ipad.sh", "scripts/build-ipad.sh"),
    ("scripts/prepare-open-source.py", "scripts/prepare-open-source.py"),
    ("docs/open-source/README.md", "docs/open-source/README.md"),
    ("docs/open-source/INSTALL.md", "docs/open-source/INSTALL.md"),
    ("docs/open-source/PRIVACY.md", "docs/open-source/PRIVACY.md"),
    ("docs/open-source/MATERIAL-ICONS.md", "docs/open-source/MATERIAL-ICONS.md"),
    ("docs/open-source/GTA6-MATERIALS.md", "docs/open-source/GTA6-MATERIALS.md"),
    ("THIRD_PARTY.md", "THIRD_PARTY.md"),
    ("licenses/Material-Icons-Apache-2.0.txt", "licenses/Material-Icons-Apache-2.0.txt"),
    ("licenses/NotoSansCJK-OFL.txt", "licenses/NotoSansCJK-OFL.txt"),
    ("tests/native-regressions.py", "tests/native-regressions.py"),
    ("AGENTS.md", "AGENTS.md"),
    ("CONTRIBUTING.md", "CONTRIBUTING.md"),
    ("SECURITY.md", "SECURITY.md"),
    ("CHANGELOG.md", "CHANGELOG.md"),
    (".github/workflows/ci.yml", ".github/workflows/ci.yml"),
    (".github/pull_request_template.md", ".github/pull_request_template.md"),
    (".github/ISSUE_TEMPLATE/bug_report.yml", ".github/ISSUE_TEMPLATE/bug_report.yml"),
    (".github/ISSUE_TEMPLATE/feature_request.yml", ".github/ISSUE_TEMPLATE/feature_request.yml"),
    (".github/ISSUE_TEMPLATE/config.yml", ".github/ISSUE_TEMPLATE/config.yml"),
    ("scripts/build-power.sh", "scripts/build-power.sh"),
    ("scripts/package-release.py", "scripts/package-release.py"),
    ("scripts/install-wizard.sh", "scripts/install-wizard.sh"),
    ("scripts/check-repository.py", "scripts/check-repository.py"),
    ("tests/package-regressions.py", "tests/package-regressions.py"),
    ("tests/repository-regressions.py", "tests/repository-regressions.py"),
    ("docs/INSTALL.md", "docs/INSTALL.md"),
    ("docs/AGENT-INSTALL.md", "docs/AGENT-INSTALL.md"),
    ("docs/COMPATIBILITY.md", "docs/COMPATIBILITY.md"),
    ("assets/readme/hero.svg", "assets/readme/hero.svg"),
    ("assets/readme/hero-mobile.svg", "assets/readme/hero-mobile.svg"),
    ("assets/readme/LAYOUT.json", "assets/readme/LAYOUT.json"),
    ("assets/readme/SOURCES.md", "assets/readme/SOURCES.md"),
    ("assets/readme/agent-mobile.svg", "assets/readme/agent-mobile.svg"),
    ("assets/readme/agent.svg", "assets/readme/agent.svg"),
    ("assets/readme/collection-mobile.svg", "assets/readme/collection-mobile.svg"),
    ("assets/readme/collection.svg", "assets/readme/collection.svg"),
    ("assets/readme/footer-mobile.svg", "assets/readme/footer-mobile.svg"),
    ("assets/readme/footer.svg", "assets/readme/footer.svg"),
    ("assets/readme/install-mobile.svg", "assets/readme/install-mobile.svg"),
    ("assets/readme/install.svg", "assets/readme/install.svg"),
    ("assets/readme/showcase-mobile.svg", "assets/readme/showcase-mobile.svg"),
    ("assets/readme/showcase.svg", "assets/readme/showcase.svg"),
    ("assets/readme/source-mobile.svg", "assets/readme/source-mobile.svg"),
    ("assets/readme/source.svg", "assets/readme/source.svg"),
    ("assets/demo/home-ipad2.png", "assets/demo/home-ipad2.png"),
    ("assets/demo/gallery-ipad2.png", "assets/demo/gallery-ipad2.png"),
    ("assets/demo/categories-ipad2.png", "assets/demo/categories-ipad2.png"),
    ("assets/demo/README.md", "assets/demo/README.md"),
    ("assets/demo/home-miami.jpg", "assets/demo/home-miami.jpg"),
    ("assets/demo/gallery-miami.jpg", "assets/demo/gallery-miami.jpg"),
    ("assets/demo/categories-miami.jpg", "assets/demo/categories-miami.jpg"),
    ("assets/demo/menu-miami.jpg", "assets/demo/menu-miami.jpg"),
    ("assets/demo/settings-miami.jpg", "assets/demo/settings-miami.jpg"),
    ("assets/demo/themes-miami.jpg", "assets/demo/themes-miami.jpg"),
    ("assets/demo/clock-edit-miami.jpg", "assets/demo/clock-edit-miami.jpg"),
    ("assets/demo/calendar-miami.jpg", "assets/demo/calendar-miami.jpg"),
    ("assets/demo/CAPTURE-METADATA.json", "assets/demo/CAPTURE-METADATA.json"),
    ("assets/media/MANIFEST.json", "assets/media/MANIFEST.json"),
    ("assets/media/ATTRIBUTION.md", "assets/media/ATTRIBUTION.md"),
)

APP_TEST_ALLOWLIST = (
    ("tests/power-edge-regressions.py", "App/tests/power-edge-regressions.py"),
    ("tests/media-lifecycle-regressions.py", "App/tests/media-lifecycle-regressions.py"),
    ("tests/gallery-media-regressions.py", "App/tests/gallery-media-regressions.py"),
    ("tests/menu-layout-regressions.py", "App/tests/menu-layout-regressions.py"),
    ("tests/cast-lifecycle-regressions.py", "App/tests/cast-lifecycle-regressions.py"),
    ("tests/http-transport-regressions.m", "App/tests/http-transport-regressions.m"),
    ("tests/run-http-transport-regressions.sh", "App/tests/run-http-transport-regressions.sh"),
    ("tests/weather-service-regressions.m", "App/tests/weather-service-regressions.m"),
    ("tests/run-weather-service-regressions.sh", "App/tests/run-weather-service-regressions.sh"),
)

IPV4_RE = re.compile(rb"(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])")
HOME_PATH_RE = re.compile(rb"(?<![A-Za-z0-9_./-])/(?:Users|home)/[^/\s\"']+")
PRIVATE_KEY_RE = re.compile(
    rb"(?im)-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|"
    rb"^\s*ssh-(?:rsa|ed25519|ecdsa)\s+[A-Za-z0-9+/=]{100,}"
)
SECRET_ASSIGNMENT_RE = re.compile(
    rb"(?im)^\s*(?:WIZARD_ROOT_PASSWORD|SSH_PASS|AWS_SECRET_ACCESS_KEY|"
    rb"API_KEY|ACCESS_TOKEN)\s*[:=]\s*\S+|sshpass\s+-p\s+\S+"
)
EMAIL_RE = re.compile(rb"(?<![A-Za-z0-9._%+-])[A-Za-z][A-Za-z0-9._%+-]*@[A-Za-z][A-Za-z0-9.-]*\.[A-Za-z]{2,}(?![A-Za-z0-9.-])")
LOCAL_INCLUDE_RE = re.compile(rb"(?m)^\s*#\s*(?:import|include)\s+\"([^\"]+)\"")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        type=Path,
        help="new output directory; must not already exist (default: private .private-audit candidate)",
    )
    return parser.parse_args()


def choose_source_app() -> tuple[Path, str]:
    if (PUBLIC_APP / "main.m").is_file():
        return PUBLIC_APP, "App"
    raise RuntimeError("Could not locate the reviewed iPad app source.")


def safe_source_file(path: Path) -> bytes:
    """Read a regular allowlisted file without following any symlink component."""
    try:
        relative = path.relative_to(SCRIPT_ROOT)
    except ValueError as exc:
        raise RuntimeError("Allowlisted source is outside the source workspace.") from exc
    if not relative.parts or any(part in (".", "..") for part in relative.parts):
        raise RuntimeError("Allowlisted source has an invalid relative path.")
    directory = None
    try:
        directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        directory = os.open(SCRIPT_ROOT, directory_flags)
        for component in relative.parts[:-1]:
            child = os.open(component, directory_flags, dir_fd=directory)
            os.close(directory)
            directory = child
        descriptor = os.open(relative.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        with os.fdopen(descriptor, "rb") as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                raise RuntimeError(f"Allowlisted source is not a regular file: {path.name}")
            return stream.read()
    except OSError as exc:
        raise RuntimeError(f"Allowlisted source is missing or has an unsafe path: {path.name}") from exc
    finally:
        if directory is not None:
            os.close(directory)


def is_protocol_address(raw: bytes) -> bool:
    try:
        octets = [int(part) for part in raw.decode("ascii").split(".")]
    except (ValueError, UnicodeDecodeError):
        return False
    if len(octets) != 4 or any(part < 0 or part > 255 for part in octets):
        return False
    first, second, third, fourth = octets
    return (
        octets == [0, 0, 0, 0]
        or first == 127
        or octets == [255, 255, 255, 255]
        or 224 <= first <= 239
    )


def scan_bytes(data: bytes) -> dict[str, int]:
    findings: dict[str, int] = {}
    home_paths = len(HOME_PATH_RE.findall(data))
    if home_paths:
        findings["workstation_home_path"] = home_paths
    private_keys = len(PRIVATE_KEY_RE.findall(data))
    if private_keys:
        findings["private_key_material"] = private_keys
    secret_assignments = len(SECRET_ASSIGNMENT_RE.findall(data))
    if secret_assignments:
        findings["credential_or_token"] = secret_assignments
    email_addresses = len(EMAIL_RE.findall(data))
    if email_addresses:
        findings["email_address"] = email_addresses
    node_addresses = sum(1 for address in IPV4_RE.findall(data) if not is_protocol_address(address))
    if node_addresses:
        findings["nonprotocol_ipv4_address"] = node_addresses
    return findings


def merge_findings(target: dict[str, int], extra: dict[str, int]) -> None:
    for category, count in extra.items():
        target[category] = target.get(category, 0) + count


def destination_path(requested: Optional[Path]) -> Path:
    if requested is not None:
        path = requested if requested.is_absolute() else Path.cwd() / requested
        return path.absolute()
    base = SCRIPT_ROOT
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return base / ".private-audit" / f"ipad-open-source-candidate-{stamp}-{os.getpid()}"


def create_file(destination: Path, data: bytes, executable: bool = False) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(destination, flags, 0o755 if executable else 0o644)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)
    destination.chmod(0o755 if executable else 0o644)


def build_manifest() -> tuple[list[tuple[Path, str, str, bytes, bool]], Path, str]:
    source_app, baseline = choose_source_app()
    manifest: list[tuple[Path, str, str, bytes, bool]] = []
    main_source = safe_source_file(source_app / "main.m")
    reviewed_headers = {name for name in APP_ALLOWLIST if name.endswith(".h") and "/" not in name}
    for included in LOCAL_INCLUDE_RE.findall(main_source):
        try:
            include_name = included.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise RuntimeError("main.m contains a non-UTF8 local include path.") from exc
        if include_name != Path(include_name).name or include_name not in reviewed_headers:
            raise RuntimeError("main.m references an unreviewed local header; add it only after individual review.")
    for relative in APP_ALLOWLIST:
        source = source_app / relative
        data = main_source if relative == "main.m" else safe_source_file(source)
        manifest.append((source, f"{baseline}/{relative}", f"App/{relative}", data, False))

    for source_rel, destination_rel in APP_TEST_ALLOWLIST:
        source = source_app / source_rel
        manifest.append((source, f"{baseline}/{source_rel}", destination_rel, safe_source_file(source), destination_rel.endswith(".sh")))

    for source_rel, destination_rel in ROOT_ALLOWLIST:
        source = SCRIPT_ROOT / source_rel
        data = safe_source_file(source)
        is_executable = destination_rel.endswith((".sh", ".py"))
        manifest.append((source, source_rel, destination_rel, data, is_executable))
    return manifest, source_app, baseline


def main() -> int:
    os.umask(0o077)
    args = parse_args()
    manifest, source_app, baseline = build_manifest()

    findings: dict[str, int] = {}
    hashes_before = {source_label: hashlib.sha256(data).hexdigest()
                     for _source, source_label, _destination, data, _executable in manifest}
    for _source, _source_label, _destination, data, _executable in manifest:
        merge_findings(findings, scan_bytes(data))
    if findings:
        print("Export blocked: sensitive categories were found in allowlisted files.", file=sys.stderr)
        for category, count in sorted(findings.items()):
            print(f"- {category}: {count}", file=sys.stderr)
        print("No candidate directory was created. Remove or review the source material, then retry.", file=sys.stderr)
        return 2

    output = destination_path(args.out)
    if output.exists() or output.is_symlink():
        print("Export blocked: output path already exists; choose a new directory.", file=sys.stderr)
        return 2
    # Recheck the reviewed byte snapshot before creating any output.
    for source, source_label, _destination, _data, _executable in manifest:
        current = safe_source_file(source)
        if hashlib.sha256(current).hexdigest() != hashes_before[source_label]:
            print("Export stopped: an allowlisted input changed before copying; no candidate was created.", file=sys.stderr)
            return 3

    output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        output.mkdir(mode=0o700)
    except FileExistsError:
        print("Export blocked: output path was created concurrently; choose a new directory.", file=sys.stderr)
        return 2

    copied: list[str] = []
    copied_hashes: dict[str, str] = {}
    try:
        for source, source_label, destination_rel, data, executable in manifest:
            create_file(output / destination_rel, data, executable)
            copied_hash = hashlib.sha256((output / destination_rel).read_bytes()).hexdigest()
            if copied_hash != hashes_before[source_label]:
                raise RuntimeError("Copied bytes differ from the reviewed source snapshot.")
            copied.append(destination_rel)
            copied_hashes[destination_rel] = copied_hash

        # Bind the report to an unchanged source snapshot after all copies complete.
        hashes_after: dict[str, str] = {}
        for source, source_label, _destination, _data, _executable in manifest:
            current = safe_source_file(source)
            hashes_after[source_label] = hashlib.sha256(current).hexdigest()
            if hashes_after[source_label] != hashes_before[source_label]:
                raise RuntimeError("An allowlisted input changed during export.")

        report = {
            "status": "local_candidate_prepared",
            "distribution_status": "prepared_local_export",
            "license_status": "MIT_for_Wizard_authored_code",
            "license_scope": "Wizard-authored code only; excludes third-party materials and media",
            "third_party_clearance": {
                "google_material_derived_vector_provenance": "pinned_35_exact_0_adapted_game_icons_removed_2026-11-12",
                "rockstar_gta_vi_media": "owner_provided_Rockstar_attribution_separate_Release_packs_and_demo_captures",
                "open_meteo_attribution": "credit_control_native_fixture_accepted_ipad2_ipad4_live_provider_unverified",
                "open_meteo_live_integration": "not_accepted_tls_1202_unresolved",
                "open_meteo_legal_clearance": "not_claimed"
            },
            "source_baseline": baseline,
            "version_control_revision": "not_recorded",
            "created_utc": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
            "included_files": copied,
            "source_hashes_before_sha256": hashes_before,
            "source_hashes_after_sha256": hashes_after,
            "copied_hashes_sha256": copied_hashes,
            "excluded_categories": [
                "Apple SDKs, Theos, Logos, vendored toolchains and framework binaries",
                "installers, SSH material, connection logs, known-host data and device state",
                "compiled historical apps and prior release archives",
                "Full GTA VI original/app-ready media packs are separate Release attachments; selected attributed native demo captures are included",
                "unreviewed fonts and unrelated artwork files; the pinned OFL Anton face and license are explicitly included",
                "license drafts and other files outside the explicit allowlist",
            ],
            "sensitive_scan": {
                "status": "passed",
                "categories_found": {},
                "checks": [
                    "workstation home paths",
                    "private key and common credential patterns",
                    "email addresses",
                    "nonprotocol IPv4 literals",
                ],
                "limitations": "not a full security, privacy, hostname, or IPv6 review",
            },
            "git_initialized": False,
            "network_used": False,
            "signed_or_installed": False,
            "build_artifact_included": False,
        }
        report_data = (json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        create_file(output / "OPEN_SOURCE_EXPORT_REPORT.json", report_data)
    except Exception:
        print("Export stopped after creating a partial candidate; it was not deleted automatically.", file=sys.stderr)
        raise

    try:
        display = output.relative_to(SCRIPT_ROOT)
        display_text = f"./{display.as_posix()}"
    except ValueError:
        display_text = f"<custom-output>/{output.name}"
    print(f"Local candidate prepared at {display_text}; license=MIT_for_Wizard_authored_code; third-party assets retain their separate rights.")
    print("Review OPEN_SOURCE_EXPORT_REPORT.json for the exact included source/demo files and separate third-party rights.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
