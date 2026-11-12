[简体中文](../zh-CN/DEVELOPMENT.md) · English

# Wizard source and contributor guide

This repository contains Wizard, a legacy native Objective-C/UIKit iPad App, its host regression checks, packaging and installation tools, and an optional power tweak. The core App and the tweak are separate components.

The App source candidate is **0.2.0 / build 20261112.39** with source/resource fingerprint `3a5cc824911e76b0f4dc45a2d555136474e293b2a753f239fdd082b809a0802f`. As checked on 2026-11-12, this build had not been installed on a physical iPad. The GitHub repository was private and all three Releases were drafts; the media manifest records prepared draft assets, not public download availability.

Wizard-authored code is licensed under the root [MIT License](../../LICENSE). That license does not cover third-party artwork, fonts, user imports or other assets. See [third-party notices](../../THIRD_PARTY.md) and the [GTA VI materials guide](../en/GTA6-MATERIALS.md).

## Build

Build on macOS with Apple Clang, Xcode command-line tools and an iPhoneOS SDK obtained through Apple's development tools. The SDK is not included in this repository or in a source export.

```sh
IOS_SDK="/path/to/iPhoneOS9.3.sdk" ./scripts/build-ipad.sh
```

The verified SDK is iPhoneOS 9.3. The script creates an **unsigned** `WizardSystem.app` for `armv7` and `arm64`, with a minimum deployment target of iOS 9.0. These settings describe the build target; they do not prove runtime compatibility on every iOS 9–12 device. Newer SDK builds, including legacy `armv7` and MediaPlayer behavior, remain unverified.

The build writes compiler and SDK details, a compile-command template, source-input hashes, a combined fingerprint in the App plist, output hashes, architectures and warnings to `BUILD-METADATA.txt`. It checks that allowlisted source and resource inputs do not change during compilation. It inspects undefined symbols with `nm -u -j` and stops on inspection errors or unresolved App-owned `IW` symbols. The legacy `dynamic_lookup` linker option remains for private system symbols; a successful host build cannot establish their presence or behavior on a device. The script does not sign or install the App.

The historical build 20261112.39 metadata template omitted `CoreText` from its recorded framework list, although the build script linked it. The script’s template has been corrected; this description error did not change the App source fingerprint, packaged App or bundled font.

By default, output goes to a new directory under `.private-audit`. To choose a destination, pass `--out PATH`; the path must not exist. The script never clears an existing output directory. The build includes the reviewed App icons and launch images, the attributed `ViceCity.jpg` fallback image, and the static OFL-licensed `Anton-Regular.ttf` with its license. The App therefore includes third-party material; compiling it does not require a separate GTA VI media pack or a proprietary font. Rockstar artwork remains outside the MIT license; see the [materials guide](../en/GTA6-MATERIALS.md).

## Run the host checks

The CI workflow runs on GitHub's `macos-15` runner. From the repository root, the same checks are:

```sh
python3 scripts/check-repository.py
python3 tests/repository-regressions.py
python3 tests/package-regressions.py
/bin/sh -n scripts/install-wizard.sh
bash -n scripts/build-ipad.sh scripts/build-power.sh
python3 tests/native-regressions.py
./App/tests/run-http-transport-regressions.sh
./App/tests/run-weather-service-regressions.sh
python3 App/tests/cast-lifecycle-regressions.py
python3 App/tests/media-lifecycle-regressions.py
python3 App/tests/gallery-media-regressions.py
python3 App/tests/menu-layout-regressions.py
python3 App/tests/power-edge-regressions.py
```

The last eight commands are the host source-regression suites. The earlier commands check tracked repository contents, repository-checker regressions, package and installer fixtures, and shell syntax. The suites use fixtures, extracted production methods and UI doubles. CI does not build a device-target App or download/redistribute an Apple SDK. The checks do not sign or install the App, validate native rendering, resolve private system APIs on a device, or replace physical-device acceptance.

## Native simulator preview

The preview is a separate iPad App for the Simulator SDK already installed with Xcode:

```sh
python3 scripts/build-preview.py --out build-preview
```

It creates an ad-hoc-signed `WizardPreview.app` with identifier `com.rex.wizard.preview`, target iOS 18 or later, and a source/resource fingerprint in `PREVIEW-METADATA.json`. The script does not install the App or boot a Simulator. Preview media lives in `Documents/WizardMedia` inside the preview App's container; device builds continue to use `/var/mobile/Media/iPadWizard/app`.

Use a dedicated Simulator selected for this project to inspect native UIKit rendering and make captures. The eight `*-miami.jpg` captures in [demo provenance](../../assets/demo/README.en.md) come from an iPad (8th generation) Simulator running iOS 18. The three `*-ipad2.png` images there are earlier physical screenshots from build `20261111.36`; they do not show the current candidate. Neither capture set proves compatibility across older iOS versions. See [Compatibility](../COMPATIBILITY.md) for the evidence matrix.

The preview accepts up to eight allowlisted scene commands through `WizardPreviewCommands`. For example:

```sh
xcrun simctl launch --terminate-running-process SIMULATOR_UDID com.rex.wizard.preview \\
  -WizardPreviewCommands "main,settingsmenu"
xcrun simctl io SIMULATOR_UDID screenshot settings.png
```

Wait for each requested transition before capturing. Example command sequences include `main,menu`, `main,themesmenu`, `main,gallery,gallerycategories` and `main,clockedit`. This Simulator-only entry invokes real App actions and avoids external URL confirmation dialogs. It does not change the device build or authorize device installation.

## Runtime and installation boundaries

The App expects external media and preference paths outside a normal application container. `App/main.m` uses `/var/mobile/Media/iPadWizard/app` for media and state and reads or writes power preferences under `/var/mobile/Library/Preferences`. It dynamically resolves symbols from Apple private BackBoardServices, GraphicsServices and SpringBoardServices frameworks.

This legacy layout is inferred from the source, not granted by the plist. Fresh installation and stock-iOS sideloading have not been validated. Review [device setup and runtime files](INSTALL.md) for the limited prepared-device update scope and prerequisites before any device work. A successful compile, host test or Simulator capture is not installation or physical acceptance.

The separate `App/WizardPowerTweak/` component uses private SpringBoard APIs and can change lock, wake and display behavior. `scripts/build-power.sh` builds it for `armv7` and `arm64`; it does not sign, install or establish runtime compatibility. The core App installer does not install the tweak. See its [component guide](../../App/WizardPowerTweak/README.md).

## Privacy and service integrations

Read [privacy and network behavior](PRIVACY.md) before building or distributing. The App imports user-selected photos, exposes a local-network media-control service and can play supplied URLs. `App/Info.plist` sets `NSAllowsArbitraryLoads=true`; that setting is not a security review or a claim that every network path works.

The weather card includes a provider-credit control. Native checks with a synthetic fixture do not establish live-provider compatibility. Open-Meteo transport and legal clearance remain unverified; review [third-party terms](../../THIRD_PARTY.md) before changing or describing the integration.

## Prepare a local source export

From the original workspace:

```sh
python3 scripts/prepare-open-source.py
```

Use `--out PATH` to choose a destination that does not exist. The exporter copies a reviewed allowlist, writes `OPEN_SOURCE_EXPORT_REPORT.json` and checks for common workstation paths and credential patterns. These checks are not a complete privacy or security review. The exporter does not initialize Git, access the network, sign, install or publish. The iPhoneOS SDK, private device state, credentials and user photos are not part of the source export.

## Licensing and attribution

Wizard-authored code uses the root MIT License. Google Material path data retains its separate Apache 2.0 notice in root `NOTICE`. The bundled display font and its SIL OFL 1.1 license are included as separate files in `App/Resources`. GTA VI images, videos, screenshots and derived media remain the property of Rockstar Games and applicable rights holders; they are not licensed under MIT. See the [GTA VI materials guide](../en/GTA6-MATERIALS.md), [demo capture provenance](../../assets/demo/README.en.md) and [third-party notices](../../THIRD_PARTY.md).
