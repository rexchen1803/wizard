# Changelog

[简体中文](docs/zh-CN/CHANGELOG.md) · [繁體中文](docs/zh-TW/CHANGELOG.md) · **English** · [日本語](docs/ja/CHANGELOG.md)

Notable changes to Wizard are listed here. Build and device evidence are described separately in the [compatibility guide](docs/COMPATIBILITY.md).

## Unreleased

- Add a macOS host CI workflow and repository-content checks.
- Add contributor, security, and compatibility guidance.

## 0.2.0 preview 4 — 20261112.40

- Add Poster / System font selection to clock editing, with saved preferences, cancellation and reset.
- Reflow editor controls when switching between time and date, including bottom-edge clamping.
- Add Traditional Chinese and Japanese presentation and guides, ordered Simplified Chinese, Traditional Chinese, English, Japanese.
- Refresh native Simulator captures from build40; keep historical physical-device images separately attributed.
- Repository remains private and Releases remain drafts. No physical-device acceptance is claimed for build40.

## 0.2.0 preview 3 — 20261112.39

- Bundle the static OFL-licensed Anton display face and license in the App, device/Simulator builds and package; capture the actual resolved clock font and bundled file origin.
- Reject missing, changed or unregistered display fonts during packaging.
- Correct descriptive build-metadata output for CoreText and the bundled attributed resources; App inputs remain unchanged.
- Rebuild the complete GitHub showcase on a shared Miami grid, with desktop/phone compositions, Chinese/English versions, real same-build captures and paired installation/development guides.
- Repository and Releases remain private/draft pending explicit publication confirmation. Physical-device rendering remains a separate acceptance step.

## 0.2.0 preview 2 — 20261112.38

- Reworked native display surfaces and the GitHub presentation around the GTA VI Miami visual direction.
- Added the attributed Vice City artwork as a no-catalog fallback; existing catalog identities, user imports and saved layouts are retained.
- Added a separate native Simulator preview build for reproducible visual captures.
- Updated package validation to bind the exact reviewed artwork. Physical-device installation and runtime acceptance remain separate.

## 0.2.0-preview.1 — candidate

- Remove unfinished mini-games and their audio, menu, lifecycle, and test integration.
- Ask for confirmation before deleting imported photos.
- Candidate build `20261111.37`; this build has not been installed on a device and is not a supported device release.
