#!/usr/bin/env python3
"""Build a separate, ad-hoc-signed native iPad Simulator preview. Never installs."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import platform
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
INPUTS = (
    "main.m", "Info.plist", "IWMediaCatalog.h", "IWHTTPTransport.h",
    "IWWeatherService.h", "IWWeatherService.m", "IWFrameProbe.h",
    "Resources/Icon-76.png", "Resources/Icon-76@2x.png", "Resources/Icon-83.5@2x.png",
    "Resources/Default-Landscape.png", "Resources/Default-Landscape@2x.png",
    "Resources/ViceCity.jpg",
)
FRAMEWORKS = (
    "UIKit", "Foundation", "AVFoundation", "MediaPlayer", "CoreMotion", "CoreMedia",
    "QuartzCore", "CoreGraphics", "CoreLocation", "CoreFoundation",
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True, help="new output directory")
    args = parser.parse_args()
    output = args.out.absolute()
    if sys.platform != "darwin":
        parser.error("macOS and Apple's installed Simulator SDK are required")
    if output.exists() or output.is_symlink():
        parser.error("output must not exist")
    arch = {"arm64": "arm64", "x86_64": "x86_64"}.get(platform.machine())
    if not arch:
        parser.error("unsupported simulator host architecture")
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    source = ROOT / "App"
    snapshots = {}
    for name in INPUTS:
        path = source / name
        if path.is_symlink() or not path.is_file():
            parser.error(f"missing regular reviewed input: {name}")
        snapshots[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    fingerprint_bytes = "".join(f"{name} {digest}\n" for name, digest in snapshots.items()).encode()
    fingerprint = hashlib.sha256(fingerprint_bytes).hexdigest()
    app = output / "WizardPreview.app"
    app.mkdir(parents=True)
    info = plistlib.loads((source / "Info.plist").read_bytes())
    info.update(CFBundleIdentifier="com.rex.wizard.preview", CFBundleDisplayName="Wizard Preview",
                MinimumOSVersion="18.0", WizardSourceFingerprint=fingerprint,
                WizardBuildChannel="simulator-preview")
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    for name in INPUTS:
        if name.startswith("Resources/"):
            shutil.copyfile(source / name, app / Path(name).name)
    command = ["xcrun", "clang", "-target", f"{arch}-apple-ios18.0-simulator", "-fobjc-arc",
               "-isysroot", sdk, "-I", str(source), str(source / "main.m"),
               str(source / "IWWeatherService.m")]
    for framework in FRAMEWORKS:
        command.extend(["-framework", framework])
    command.extend(["-Wl,-undefined,dynamic_lookup", "-o", str(app / "WizardSystem")])
    result = subprocess.run(command, text=True, capture_output=True)
    (output / "clang.stderr").write_text(result.stderr)
    if result.returncode:
        raise SystemExit(f"Simulator compile failed; inspect {output / 'clang.stderr'}")
    for name, digest in snapshots.items():
        if hashlib.sha256((source / name).read_bytes()).hexdigest() != digest:
            raise SystemExit("Build inputs changed; discard this preview and rebuild")
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
    metadata = {
        "kind": "native-simulator-preview", "bundle_id": info["CFBundleIdentifier"],
        "build": info["CFBundleVersion"], "source_fingerprint": fingerprint,
        "architecture": arch, "minimum_simulator_os": "18.0", "sdk": Path(sdk).name,
        "media_root": "Documents/WizardMedia", "inputs_sha256": snapshots,
        "physical_device_acceptance": False, "installed": False,
        "command": command,
    }
    (output / "PREVIEW-METADATA.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps({"app": str(app), "build": info["CFBundleVersion"], "fingerprint": fingerprint}))


if __name__ == "__main__":
    main()
