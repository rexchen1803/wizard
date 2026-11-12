# Compatibility and validation status

[简体中文](zh-CN/COMPATIBILITY.md) · English

This guide separates build evidence, host checks, Simulator captures and physical-device operation. It describes the **Wizard 0.2.0 / build 20261112.39** source candidate as checked on 2026-11-12. That build has not been installed on a physical iPad. Its App source/resource fingerprint is `3a5cc824911e76b0f4dc45a2d555136474e293b2a753f239fdd082b809a0802f`.

## Evidence by environment

| Environment | Verified evidence | What it does not establish |
| --- | --- | --- |
| Device build target | The App declares iOS 9.0 as its minimum deployment target. Build `20261112.39` compiled locally with the iPhoneOS 9.3 SDK for `armv7` and `arm64`. | The deployment target and compile do not establish compatibility across iOS 9–12, later iOS releases, or any device runtime. |
| iPad (8th generation) Simulator, iOS 18.0 | The separate Simulator preview was built from the same App source/resource fingerprint with the installed iPhoneSimulator 27.1 SDK. The eight `*-miami.jpg` files are native UIKit captures. | Simulator rendering does not establish physical-device behavior or compatibility with iOS 9–12. |
| macOS host and CI | The candidate code at commit `922a0158315519cb4faeb8e37abb8da447ef9103` has a successful GitHub CI run on the `macos-15` runner. CI runs repository and package checks, shell syntax checks, and eight host regression commands. | Host fixtures, extracted production methods and UIKit doubles do not build or install the device App or prove native rendering, signing, private-symbol resolution or device behavior. |
| iPad 2, `iPad2,4`, iOS 9.3.5 | Earlier build `20261111.30` was updated on an existing prepared installation. Recorded checks covered launch, menus, gallery, preference preservation, scoped motion, calendar and editor flows, and physical photo selection/import. | This is earlier-build evidence on a prepared installation. It does not cover build `.39`, fresh installation, stock iOS, accessibility or all interactions. |
| iPad 4, `iPad3,4`, iOS 10.3.3 | Earlier build `20261111.30` was updated on an existing prepared installation. Recorded checks covered scoped UI, calendar, video and media-resource behavior. | This is earlier-build evidence on a prepared installation. It does not cover build `.39`, fresh installation, stock iOS, accessibility or broad daily use. |
| iPad Air, `iPad4,1`, iOS 12.5.8 | Earlier build `20261111.36` was updated on an existing recovered, prepared installation. Scoped UI and media synchronization checks were recorded. | This is earlier-build evidence on a prepared installation. It does not cover build `.39`, fresh installation, stock iOS, full playback, accessibility or broad daily use. |
| Current build on physical iPad | No physical iPad has received build `20261112.39`. | No current-build physical acceptance is claimed. |
| Fresh install or stock iOS | No verified installation path. The available installation evidence is limited to prepared, rootful or unsandboxed devices. | Signing, registration, external storage access and private-framework behavior are not established for stock devices or first-time setup. |

The prepared-device scopes and their prerequisites are documented in [Device setup and runtime files](open-source/INSTALL.md). The `home-ipad2.png`, `gallery-ipad2.png` and `categories-ipad2.png` images in [demo capture provenance](../assets/demo/README.en.md) are earlier physical-device records from build `20261111.36`; they are not screenshots of build `20261112.39`. The current `*-miami.jpg` captures are from the iPad 8 Simulator.

## Build and host checks

The verified device-target SDK for this candidate is iPhoneOS 9.3. The SDK must come from Apple development tools and is not included in the source tree or export. Newer SDK builds are unverified, including their interaction with legacy MediaPlayer interfaces and `armv7`. See the [source build guide](open-source/README.md#build).

CI is a macOS host job. It runs the repository checker and its regression cases, package/installer fixtures, shell syntax checks, and these eight host regression commands:

```sh
python3 tests/native-regressions.py
./App/tests/run-http-transport-regressions.sh
./App/tests/run-weather-service-regressions.sh
python3 App/tests/cast-lifecycle-regressions.py
python3 App/tests/media-lifecycle-regressions.py
python3 App/tests/gallery-media-regressions.py
python3 App/tests/menu-layout-regressions.py
python3 App/tests/power-edge-regressions.py
```

These checks are useful for source regressions. They are not a substitute for install, launch, interaction, media, accessibility or long-running checks on each intended device and OS.

## Runtime constraints and optional component

The core App reads media and preference files beneath `/var/mobile/Media/iPadWizard/app` and `/var/mobile/Library/Preferences`, outside a normal application container. It dynamically resolves symbols from Apple private `BackBoardServices`, `GraphicsServices` and `SpringBoardServices` frameworks. A host build cannot show that these symbols resolve or behave correctly on a target device.

The optional `WizardPower` tweak is a separate component. It is not part of the core App’s installation path and it uses private SpringBoard APIs. Its build, installation and runtime acceptance must be reviewed separately; see the [tweak guide](../App/WizardPowerTweak/README.md).

The iOS 18 Simulator video check showed themed controls and advancing media time, but its capture contained no decoded video image. A frame extracted from the same silent fixture was valid. This does not identify the cause or establish physical-device playback. The legacy device playback path remains in the source, and no universal iOS 9–12 playback claim is made.

## Bundled display font

Build `20261112.39` includes the unchanged static `Anton-Regular.ttf` and its SIL OFL 1.1 license in both device and Simulator App bundles. `UIAppFonts` registers the font, and the Simulator capture metadata records the resolved name `Anton-Regular` and verifies that it came from the App bundle. Package checks reject missing or changed font/license bytes and missing registration. This verifies the packaged font input; it does not establish identical rendering on older physical iPads.

## Related references

- [Source build and contributor guide](open-source/README.md)
- [Device setup and runtime files](open-source/INSTALL.md)
- [Simulator and historical capture provenance](../assets/demo/README.en.md)
- [Third-party materials and licenses](../THIRD_PARTY.md)
