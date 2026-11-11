# Compatibility

This guide separates source/build evidence from installations and device behavior. The current source candidate is **Wizard 0.2.0 / build 20261111.37**. It has host regressions and local build evidence, but build `20261111.37` has not been installed on a device.

## Current evidence

| Target | Evidence | Boundary |
| --- | --- | --- |
| iOS 9 and later | The source declares iOS 9.0 as its minimum. Candidate build `20261111.37` built locally and from a clean source export with an iPhoneOS 9.3 SDK for `armv7` and `arm64`. | A deployment target and successful compile do not establish runtime compatibility across later iOS versions. Newer SDK builds are not verified. |
| macOS host checks | Eight host regression suites run with Apple Clang and Python 3. The CI workflow is configured for GitHub's `macos-15` runner. | They use fixtures, extracted production logic, and UI doubles. They do not install the app or prove native device behavior. The hosted workflow has not yet supplied a run result. |
| iPad 2, iPad2,4, iOS 9.3.5 | Earlier build `20261111.30` was updated on an existing prepared installation for scoped launch, menu, gallery, preference, motion, calendar, editor, and photo-import checks. | Build `.37` is not installed. Fresh install, stock iOS sideloading, accessibility, and remaining interactions are unverified. |
| iPad 4, iPad3,4, iOS 10.3.3 | Earlier build `20261111.30` was updated on an existing prepared installation for scoped UI, calendar, video, and media-resource checks. | Build `.37` is not installed. Fresh install, stock iOS sideloading, accessibility, and broad daily use are unverified. |
| iPad Air, iPad4,1, iOS 12.5.8 | Earlier build `20261111.36` was updated on an existing recovered, prepared installation. Scoped UI and media synchronization checks were recorded. | Build `.37` is not installed. This does not validate fresh installation, stock iOS sideloading, full playback, accessibility, or broad daily use. |
| Stock iOS or fresh install | No verified installation path. | Signing, registration, external storage access, and private-framework behavior are not established for stock devices or first-time setup. |

The earlier device evidence comes from the project-local audit record and applies only to the listed prepared installations and tested scopes. See [device setup and runtime files](open-source/INSTALL.md) for the detailed update prerequisites and evidence. No installer or signed app is included.

## Build requirements

The optional device-target build requires macOS, Apple Clang, and an iPhoneOS SDK obtained through Apple's development tools. The SDK is not included. The verified local SDK is iPhoneOS 9.3; newer SDK and legacy armv7 compatibility remain unverified. See the [build guide](open-source/README.md#build).

GitHub Actions runs only host regressions on a current macOS runner. It does not fetch or redistribute Apple's SDK, create a signed build, or run a device-target build. A green CI result is source-level evidence only.

## Known runtime constraints

The app expects external media and preference paths outside a normal application container and dynamically looks up private Apple framework symbols. The optional power tweak also uses private SpringBoard APIs. These assumptions are not evidence that the app or tweak works on an unmodified device. Review [privacy and network behavior](open-source/PRIVACY.md) and [third-party material terms](../THIRD_PARTY.md) before enabling integrations or distributing changes.
