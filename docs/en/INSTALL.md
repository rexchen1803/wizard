# Install Wizard

[简体中文](../INSTALL.md) · [繁體中文](../zh-TW/INSTALL.md) · **English** · [日本語](../ja/INSTALL.md)

This guide covers the Wizard 0.2.0 / build `20261112.41` preview package, source build, optional gallery, and rollback. The package is intended only for an already prepared **rootful jailbroken iPad**. It does not install a jailbreak or power tweak, change certificates, network, or system-trust settings, or launch the app automatically.

## Download status

The source repository is public; all GitHub Releases remain drafts. `v0.2.0-preview.5` has not been published, so there is currently no public `releases/download/...` endpoint. An authorized maintainer can sign in and inspect drafts from the [Releases page](https://github.com/rexchen1803/wizard/releases); that page is a maintainer entry point, not a public download, and does not guarantee that an attachment is available. If you cannot access a required attachment, stop. Do not publish a Release, change repository visibility, or substitute `latest`. Making the repository public does not publish draft Releases or their attachments.

After `v0.2.0-preview.5` is published, the build41 package and manifest will use these fixed filenames and paths:

| File | Fixed filename | Fixed URL after publication (not available now) |
| --- | --- | --- |
| Wizard Debian package | `wizard_0.2.0-20261112.41_iphoneos-arm.deb` | `https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.5/wizard_0.2.0-20261112.41_iphoneos-arm.deb` |
| Package manifest | `wizard_0.2.0-20261112.41_iphoneos-arm.deb.manifest.json` | `https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.5/wizard_0.2.0-20261112.41_iphoneos-arm.deb.manifest.json` |

Proceed only when both the exact `.deb` and its matching manifest are available through an authorized source. Verify the `.deb` against `artifact_sha256` in the manifest. On macOS, run `shasum -a 256 wizard_0.2.0-20261112.41_iphoneos-arm.deb`. Stop if the version, filename, or hash differs; do not mix a package and manifest from different releases. The packaging script generates the manifest and artifact hash for each output; this repository does not hard-code a build41 `.deb` hash that can replace the downloaded manifest.

## Device scope and prerequisites

The installer accepts only these exact model and iOS pairs:

| Device | Model identifier | iOS |
| --- | --- | --- |
| iPad 2 | `iPad2,4` | `9.3.5` |
| iPad 4 | `iPad3,4` | `10.3.3` |
| iPad Air | `iPad4,1` | `12.5.8` |

The device must also have a rootful jailbreak, root access, a writable `/Applications` directory that is not a symlink, a Debian package environment, and `ldid`, `uicache`, `killall`, `sysctl`, and `sw_vers`. `uicache` must support both `-p` registration and `-u` unregistration. Stock iOS, rootless jailbreaks, iPhones, and unlisted device or OS versions are rejected. Do not bypass the checks by changing a reported model or OS version.

Package-structure checks and the installer's local fixture checks do not establish on-device installation, signing, registration, or launch acceptance. Earlier evidence from specific prepared devices is summarized in the [compatibility table](../COMPATIBILITY.md); it does not prove a fresh build41 installation. Physical-device acceptance for build41 is still pending.

## Install the preview package

After the exact files above are available from an authorized source:

1. Download `wizard_0.2.0-20261112.41_iphoneos-arm.deb` and its matching `.manifest.json`. The future URL shown above is not currently usable while the Release is a draft. Maintainers can open the draft from the [Releases page](https://github.com/rexchen1803/wizard/releases). Stop if the attachment cannot be obtained.
2. Verify the `.deb` against `artifact_sha256` in its manifest. Use only the manifest for that package; do not use `latest`, another Release, or a renamed package.
3. On the authorized target iPad, install the package using Filza or the local `.deb` workflow supported by Cydia, Sileo, or Zebra. An already authorized root terminal on the device can also run:

   ```sh
   dpkg -i ./wizard_0.2.0-20261112.41_iphoneos-arm.deb
   ```

The package hooks first check the model, OS, rootful environment, package manager, required tools, and app path. The installer uses the existing device `ldid` to ad-hoc sign the unsigned app, then registers it with `uicache`. During an update, it sends Wizard one `TERM` command and retains the previous app bundle intact as `WizardSystem.rollback-<build>-<UTC>.app` before placing the candidate app. A fresh install has no previous app to retain. The installer does not launch Wizard, reboot the device, or respring.

The package does not replace `/var/mobile/Media/iPadWizard/app`, Wizard preferences, or existing rollback bundles. If signing, file placement, or registration fails, the installer restores or retains the candidate, previous app, and recovery directories according to the branch that failed. Preserve the error state and report the original error; do not force a respring, delete recovery directories, or clean user data. A successful install means the installer completed; the user must open Wizard manually and accept the app separately.

## Build from source

The source repository is public and can be cloned over HTTPS without signing in. A source build requires macOS, Apple Clang, and an iPhoneOS SDK obtained through Apple's developer tools. The Apple SDK is not included in this repository. The validated SDK is iPhoneOS 9.3; armv7 and legacy MediaPlayer compatibility with newer SDKs has not been verified.

```sh
git clone https://github.com/rexchen1803/wizard.git
cd wizard
IOS_SDK="/path/to/iPhoneOS9.3.sdk" ./scripts/build-ipad.sh --out /tmp/WizardSystem-build
python3 scripts/package-release.py \
  --app /tmp/WizardSystem-build/WizardSystem.app \
  --out /tmp/wizard_0.2.0-20261112.41_iphoneos-arm.deb
```

The output app directory, `.deb`, and adjacent manifest must not already exist. The packager requires the filename to match the app version and build; it checks the `armv7` and `arm64` architectures, bundle ID, resources, and source fingerprint, then writes `artifact_sha256` into the newly generated manifest. `--dry-run` prints the package structure and hashes without writing the package files. Building and packaging do not connect to a device or install anything. The [build and regression guide](../open-source/README.md#build) describes source validation limits. [WizardPower source notes](../../App/WizardPowerTweak/README.md) have a separate build entry point; the Wizard package does not install that tweak.

## Optional GTA VI gallery

The gallery and original-media packages are also draft attachments for the unpublished `v0.2.0-preview.5` Release. There is currently no public download endpoint. Use them only if a maintainer or authorized user can obtain the exact draft attachments; stop if they are unavailable. Do not publish a Release or change repository visibility.

| File | Contents | Size | SHA-256 |
| --- | --- | ---: | --- |
| `wizard-gta6-gallery-20261112.zip` | 230 gallery catalog items, 228 images, 2 videos, and thumbnails | 258,253,713 bytes | `b8bd883b81a0a76086217ce3c27091d83b0b8261dcbabae49c88abb67aef3eba` |
| `gta6-original-materials-20261112.zip` | 343 original JPEGs, 2 MKV videos, and 2 SRT files | 755,809,316 bytes | `182cb83aaf463dc22004f750a4e51a2419ef50eb2da851aba9c6d456d89aea0b` |

The [local manifest](../../assets/media/MANIFEST.json) records the expected sizes and SHA-256 values for these exact files. Their fixed paths after publication are below; **they are not available now**:

```text
https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.5/wizard-gta6-gallery-20261112.zip
https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.5/gta6-original-materials-20261112.zip
```

Install the app gallery only if you separately choose and authorize it. First make a complete backup of `/var/mobile/Media/iPadWizard/app`, then merge the ZIP's `app/` contents into that directory. Preserve the existing `assets/user` directory and preferences; do not delete or replace the entire `app` directory. If the transfer tool changes permissions, adjust only the newly copied files; do not recursively change existing user directories. Reopen Wizard and check the original wallpapers, favorites, crops, imported photos, and categories. The original-media archive is for collecting and creating material; it is not the device gallery package. See the [media notes](../open-source/GTA6-MATERIALS.md) and [attribution record](../../assets/media/ATTRIBUTION.md). Rockstar media is not covered by Wizard's MIT code license.

## Rollback and removal

After an update, record the exact rollback directory printed by the installer. In an authorized root terminal on the device, replace the placeholder in this example with that exact path:

```sh
/usr/lib/wizard-installer/install-wizard.sh rollback "/Applications/WizardSystem.rollback-<build>-<UTC>.app"
```

Rollback retains the current candidate as `WizardSystem.failed-rollback-<UTC>.app`, restores the selected `WizardSystem.rollback-*` or `WizardSystem.uninstalled-*` bundle, and registers it again. It does not launch the app or restart SpringBoard. If rollback fails, preserve all directories and report the error; do not guess which directory to delete or overwrite.

Uninstall the Debian package only when the task explicitly requests it. Use the package manager or run this command in an authorized root terminal on the device:

```sh
dpkg -r com.rex.wizardsystem
```

The removal hook unregisters only a Wizard app whose build matches the package, and retains its complete bundle as `WizardSystem.uninstalled-<build>-<UTC>.app`. If the installed app has a different build, that app is preserved, but the package manager may still remove this package and its helper. Removal does not clear media, preferences, or existing rollback bundles. To restore an archived app, reinstall the same fixed `.deb` to restore the helper, then pass the actual `WizardSystem.uninstalled-*` path to `rollback`. Clearing personal media or preferences is a separate operation and is not part of ordinary removal.

The App bundle includes the attributed Vice City default wallpaper; Wizard can display it without an external gallery. The full gallery is optional.
