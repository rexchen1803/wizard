# Security policy

[简体中文](docs/zh-CN/SECURITY.md) · [繁體中文](docs/zh-TW/SECURITY.md) · **English** · [日本語](docs/ja/SECURITY.md)

Wizard is a source project for legacy iPads. The app uses external media paths, local-network media controls, and private Apple frameworks; review the [privacy notes](docs/open-source/PRIVACY.md) and [compatibility limits](docs/COMPATIBILITY.md) before use.

## Report a vulnerability

Please use [GitHub's private vulnerability reporting](https://github.com/rexchen1803/wizard/security/advisories/new) when it is enabled for this repository. Do not post an unpatched vulnerability, credentials, private logs, device identifiers, or personal media in a public issue. Include the affected source revision or Wizard build, the iPad model and iOS version if relevant, and a concise reproduction. Redact personal and network details.

If private reporting is unavailable, do not publish exploit details in an issue; wait until a private reporting route is available. No response-time or support commitment is made.

## Security review scope

Review the core App, optional power add-on, installer and release exporter together. Removing a UI or URL route does not disable a background listener or privileged IPC receiver. Require explicit opt-in for network controls and diagnostics, and retain the source/build/device evidence boundaries.

## Supported versions

There is no supported device release at this time. The current source candidate is documented in the [compatibility guide](docs/COMPATIBILITY.md); host regression results do not establish device security or runtime support.
