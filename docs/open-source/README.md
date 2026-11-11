# iPad Wizard source candidate

**Release channel: public-source preview.** Wizard-authored code is licensed under MIT in the root `LICENSE` (`Copyright (c) 2026 Rex`). That license does not cover third-party materials. Google Material path data remains under its separate Apache 2.0 notice and license. GTA VI images, videos and derived edits are attributed to Rockstar Games and applicable rights holders. Selected attributed captures are included for demonstration; full media packs are separate Release attachments. The weather card has a localized provider-credit control, with native synthetic-fixture and visual checks accepted on iPad 2 and iPad 4. Live-provider compatibility and remaining device/runtime gates remain open.

This tree contains the complete Wizard app source, owned icon resources, public packaging/install tools, optional power-addon source, regression tests and documentation. The repository includes attributed native demonstration captures. App binaries and separate GTA VI media packs are provided as Release attachments; Apple SDKs, private device state, credentials and user photos are excluded.

## Build

The current local source candidate is **0.2.0 / 20261111.37**. Mini-games and their audio, menu, lifecycle and test integration have been removed. This candidate has not been installed on a device; the prior device records describe earlier builds.

Build on macOS with Xcode Command Line Tools and an iPhoneOS SDK you obtained through Apple’s development tools. The SDK is not bundled. From the repository root:

```sh
IOS_SDK="/path/to/iPhoneOS9.3.sdk" ./scripts/build-ipad.sh
```

The verified SDK is iPhoneOS 9.3. Newer SDK compatibility is unverified, particularly the retired MediaPlayer interfaces and armv7 support.

The script creates an unsigned `WizardSystem.app` for `armv7` and `arm64`, with a minimum deployment target of iOS 9.0. It records the compiler, SDK name, compile command template, warnings, source snapshot hashes, a combined fingerprint injected into the built plist, output hashes, and architectures in `BUILD-METADATA.txt`. The script fails if any allowlisted build input changes while compiling. It also uses `nm -u -j` to reject undefined app-owned `IW` functions and Objective-C classes, metaclasses and ivars in each architecture. `NM` may select a compatible executable supporting those flags and symbol-names-only output. Symbol inspection or matching errors stop the build. The legacy `dynamic_lookup` linker flag remains for private system symbols; a host build does not prove those symbols resolve on-device. The script does not sign or install the app.

By default, output goes to a new private audit directory. To select a location, pass `--out PATH`; that path must not already exist. The script never clears an existing output directory. No proprietary font, launch image or media file is needed to compile. The reviewed Wizard icons and owned landscape launch images in `App/Resources` are bound into the source snapshot and copied into the App. Native screenshots and full media packs retain separate attribution.

The original private workspace has a local SDK fallback at `.local/toolchains/iPhoneOS9.3.sdk` for development only. An exported source candidate has no SDK fallback and requires `IOS_SDK`.

## Device setup

See [device setup and runtime files](INSTALL.md) for the verified existing-install update scope, rollback sequence, required filesystem access, optional catalog schema and imported-photo layout. Fresh installation and stock-iOS sideloading remain unverified. Historical installers do not install this candidate.

## Legacy runtime assumptions

The source reflects a historical jailbroken or unsandboxed iPad deployment model. This is an inference from the code, not a property granted by the plist. `App/main.m` uses `/var/mobile/Media/iPadWizard/app` for app assets, user media, and state files, and reads/writes power preferences under `/var/mobile/Library/Preferences`. Those paths are outside an ordinary app container.

The app dynamically opens Apple private `BackBoardServices`, `GraphicsServices`, and `SpringBoardServices` frameworks and resolves symbols used for display and lock operations. A successful host compile does not show that the symbols exist or work at runtime. The optional tweak also uses private SpringBoard APIs.

`App/Info.plist` identifies an iPad-only app (`UIDeviceFamily` 2), sets a minimum OS of 9.0 and a development build channel, and sets `NSAllowsArbitraryLoads=true` for App Transport Security. This configuration does not demonstrate stock-device sideload compatibility. The public source candidate contains no installer or entitlement evidence for the external storage and private API access. **Stock iOS sideloading has not been validated.**

## Regression check

Run the source regression checks with:

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

The checks execute extracted production methods with controlled dependencies; they do not replace physical-device testing. Calendar cases cover Gregorian year rollover, reduced spatial motion, transition cleanup and the unchanged return-to-today dissolve using UIKit view/animation doubles. Menu checks execute extracted production main/theme/settings menu geometry and background input guards using host UIKit doubles; they cover retained actions, ordering, touch-target sizes, overlap and landscape panel bounds, not native rendering. Gallery checks also exercise the production deletion-confirmation method with controlled UIKit doubles: trash taps do not delete, Cancel retains mixed selections, and a changed selection or reloaded gallery invalidates a stale confirmation. No installation, signing, or device operation is performed by the build or export scripts. Device and private-symbol runtime acceptance remains outstanding.

## Privacy and limitations

Read [PRIVACY.md](PRIVACY.md) before building or distributing. The app imports user-selected photos, exposes a local-network media control service, and can play URLs supplied to it. This candidate is not a claim of independent privacy, security, or runtime acceptance.

`App/WizardPowerTweak/` is an optional experimental component. `scripts/build-power.sh` builds its source directly with clang for both architectures; see [its guide](../../App/WizardPowerTweak/README.md). It uses private SpringBoard APIs and can change lock, wake and display behavior. The App installer does not install it; runtime compatibility and safe configuration remain separate review work.

## Licensing

Wizard-authored code uses the MIT License in root `LICENSE`. Its scope excludes Rockstar media, user imports, and other third-party assets. Google Material path data has a separate Apache 2.0 license and attribution in root `NOTICE`. GTA VI owner-supplied attribution, official source pages, and per-file matching limits are documented in [GTA6-MATERIALS.md](GTA6-MATERIALS.md). The weather-credit control passed native synthetic-fixture and visual checks on iPad 2 and iPad 4; no live weather connection or legal clearance is claimed. The Open-Meteo free hosted API terms restrict use to non-commercial purposes; see [Third-party materials and build requirements](../../THIRD_PARTY.md) for the provider terms, CC BY 4.0 link, and live TLS limitation. The export remains `do_not_publish` pending runtime and other release gates.

## Prepare a local export candidate

From the original workspace, run:

```sh
python3 scripts/prepare-open-source.py
```

Or select a new destination with `--out PATH`. The destination must not already exist. The exporter copies a reviewed allowlist into `App/`, adds the build and documentation files, writes `OPEN_SOURCE_EXPORT_REPORT.json`, and checks workstation home paths, private-key/common credential patterns, email addresses, and nonprotocol IPv4 literals. This is not a full security or privacy review. It does not initialize Git, access the network, sign, install, or publish anything.

## Performance diagnostics

The opt-in frame probe records main-run-loop display-link delivery, interval p95 and delays. It checks the fixed global marker `/tmp/wizardsystem-performance-debug` on both iPad families. Reports, screenshots, and state files go under `NSTemporaryDirectory()`; on iPad 4 those outputs use the app container's temporary directory, separate from the global marker. Reports include version/build and source fingerprint. Check that `applicationState` is 0 and `windowHidden` is false when interpreting foreground samples. These samples do not measure compositor-presented frame rate; native interaction, displayed video and long-running stability require separate checks. Remove temporary diagnostics after testing.

The power-edge harness uses a virtual scheduler and fake lock manager. It does not build/inject a SpringBoard tweak or establish private-API compatibility.

The marker-gated local-video audit can use an owned fixture. Its optional `wizardsystem-local-video-fixture` file lives in `NSTemporaryDirectory()` and contains exactly 20 lowercase hexadecimal bytes, with UID 501 ownership and mode `0600`. It selects `/var/mobile/Media/iPadWizard/.wizard-local-video-audit-<nonce>/fixture.mp4`: the private root must have UID 501 ownership and mode `0700`, and the regular UID 501 file must be nonempty, at most 2 MiB, and on the parent's filesystem. The marker, private root and fixture file must not be symbolic links. Invalid inputs stop the diagnostic. Without the nonce marker, the diagnostic retains its original local-video input. The terminal report records actual monotonic sample intervals and read-only output-volume values. Remove the owned fixture and any markers created for the test after capture.
