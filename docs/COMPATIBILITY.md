# Compatibility

This guide separates source/build evidence from installations and device behavior. The current source candidate is **Wizard 0.2.0 / build 20261112.39**. It has host regressions and local build evidence, but build `20261112.39` has not been installed on a physical iPad.

## Current evidence

| Target | Evidence | Boundary |
| --- | --- | --- |
| iOS 9 and later | The source declares iOS 9.0 as its minimum. Candidate build `20261112.39` built locally and from a clean source export with an iPhoneOS 9.3 SDK for `armv7` and `arm64`. | A deployment target and successful compile do not establish runtime compatibility across later iOS versions. Newer SDK builds are not verified. |
| iPad (8th generation) Simulator, iOS 18.0 | Build `20261112.39` uses the installed iPhoneSimulator 27.1 SDK. Native captures cover home, gallery, categories, menus, clock/date/calendar editing, empty state and a local synthetic weather panel. Source/resource fingerprint matches the device build. | Simulator rendering is separate from iOS 9–12 device behavior; the weather fixture does not verify live forecasts. See [capture provenance](../assets/demo/README.md). |
| macOS host checks | Eight host regression suites run with Apple Clang and Python 3. The CI workflow is configured for GitHub's `macos-15` runner. | They use fixtures, extracted production logic, and UI doubles. They do not install the app or prove native device behavior. The earlier source37 hosted workflow passed; current-candidate CI evidence is linked in its commit checks. |
| iPad 2, iPad2,4, iOS 9.3.5 | Earlier build `20261111.30` was updated on an existing prepared installation for scoped launch, menu, gallery, preference, motion, calendar, editor, and photo-import checks. | Build `.37` is not installed. Fresh install, stock iOS sideloading, accessibility, and remaining interactions are unverified. |
| iPad 4, iPad3,4, iOS 10.3.3 | Earlier build `20261111.30` was updated on an existing prepared installation for scoped UI, calendar, video, and media-resource checks. | Build `.37` is not installed. Fresh install, stock iOS sideloading, accessibility, and broad daily use are unverified. |
| iPad Air, iPad4,1, iOS 12.5.8 | Earlier build `20261111.36` was updated on an existing recovered, prepared installation. Scoped UI and media synchronization checks were recorded. | Build `.37` is not installed. This does not validate fresh installation, stock iOS sideloading, full playback, accessibility, or broad daily use. |
| Stock iOS or fresh install | No verified installation path. | Signing, registration, external storage access, and private-framework behavior are not established for stock devices or first-time setup. |

The earlier device evidence comes from the project-local audit record and applies only to the listed prepared installations and tested scopes. See [device setup and runtime files](open-source/INSTALL.md) for the detailed update prerequisites and evidence. A guarded rootful .deb is provided as a Release attachment; its physical installation remains unverified.

## Build requirements

The optional device-target build requires macOS, Apple Clang, and an iPhoneOS SDK obtained through Apple's development tools. The SDK is not included. The verified local SDK is iPhoneOS 9.3; newer SDK and legacy armv7 compatibility remain unverified. See the [build guide](open-source/README.md#build).

GitHub Actions runs only host regressions on a current macOS runner. It does not fetch or redistribute Apple's SDK, create a signed build, or run a device-target build. A green CI result is source-level evidence only.

## Known runtime constraints

The app expects external media and preference paths outside a normal application container and dynamically looks up private Apple framework symbols. The optional power tweak also uses private SpringBoard APIs. These assumptions are not evidence that the app or tweak works on an unmodified device. Review [privacy and network behavior](open-source/PRIVACY.md) and [third-party material terms](../THIRD_PARTY.md) before enabling integrations or distributing changes.

## Bundled display font

Build `20261112.39` includes the unmodified static `Anton-Regular.ttf` and its OFL 1.1 license in both device and Simulator App bundles. The font is declared in `UIAppFonts` and registered with Core Text; the display selector uses `Anton-Regular` before system fallbacks. Native capture evidence records the actual clock font name and confirms its file comes from the App bundle. Package checks reject missing or different font/license bytes and missing font registration. This removes dependence on the old system-font preference list; the prepared iOS 9–12 devices still require separate runtime acceptance.

## Simulator video boundary

The current iOS 18 Simulator check displayed the themed transport and volume controls and advancing media time, but its screen capture did not contain decoded video imagery. A frame extracted from the same silent video fixture was valid. This observation does not establish a cause or physical-device playback behavior; it is not accepted playback evidence. The source keeps the legacy device playback path. AirPlay decoration now disappears when the system reports no selectable wireless route, rather than leaving an empty ring.
