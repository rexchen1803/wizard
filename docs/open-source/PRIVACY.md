# Local data and network behavior

This describes the iPad source candidate, not an App Store privacy declaration or proof of device acceptance.

## Photos and preferences

Wizard can import a photo selected through the system picker. It writes a resized JPEG and a thumbnail to `/var/mobile/Media/iPadWizard/app/assets/user`. Favorites, wallpaper framing, clock/calendar layout and settings are stored on the device. Deleting a user-imported wallpaper removes Wizard's copy; it does not delete the original from Photos. Bundled media and user-imported media are separate.

The public source package contains no personal photos, media library, preferences, device snapshots, SSH keys or connection credentials. It does not contain the historical theme fonts, launch artwork, music or videos. You can run the clock and import your own photos without the optional bundled wallpaper catalog.

## Cast and remote playback

The current implementation starts a DLNA/UPnP receiver with the app. It listens for HTTP on port 8199 and SSDP discovery on UDP port 1900, and sends local discovery announcements. The receiver advertises a device name and a vendor-derived device identifier. These endpoints are intended for a trusted local network and do not implement sender authentication. Do not expose them through a router port forward.

A Cast sender can provide a remote media URL. The iPad contacts that media server directly to play it; that server receives the normal connection information and any credentials or tokens embedded in the sender's URL. `NSAllowsArbitraryLoads` is currently enabled to support older devices and HTTP local media sources. This is a documented compatibility behavior, not a general guarantee that every source will play.

The advertised SOAP surface is partial. URL submissions reach the player, but `Play`, `Pause`, `Stop` and `Seek` actions are not connected to playback controls. `GetTransportInfo` returns a fixed `PLAYING` response; `GetPositionInfo` returns zero duration/position, and volume/mute queries also return fixed values. These interfaces remain available for future implementation. An HTTP success or status response does not establish the actual playback state.

## Weather

Weather is optional. When enabled, Wizard asks for location permission and sends latitude/longitude to the Open-Meteo HTTPS forecast endpoint. Reverse geocoding uses Apple's location services to obtain a city name. The on-device cache stores coordinates, city, weather and fetch time so it can show cached conditions and retry with cached coordinates if location is unavailable. Disabling weather stops location updates and scheduled refreshes. The evaluation provider's current terms and attribution must be reviewed before distribution.

## Diagnostics and optional integrations

Diagnostic state can be written under `/tmp`, including wallpaper, playback URLs and user interface state. Touch and Cast log writes require the temporary `wizardsystem-debug` opt-in marker; Cast logs can include private playback URLs. Performance and in-process video-control diagnostics require their temporary performance marker. Weather diagnostics use their separate opt-in marker. They can contain private information. Inspect and redact diagnostics before sharing them; the publication exporter excludes historical logs and device state.

The legacy `wizardsystem` custom URL scheme accepts app controls, settings changes and power-integration commands. Some legacy commands are available without a diagnostic marker. These are separate from the local-network Cast endpoints.

Home/status file interfaces and experimental controls remain in the source. Their presence does not establish that an external integration has been configured. The separately included WizardPower tweak uses privileged SpringBoard behavior and its own on-device preferences; it is optional and is not installed by building or exporting the app.

## Validation limits

Code inspection, host regressions and clean export scans are separate from a three-device data-flow review. Remote server behavior, an installed device's configuration, and third-party additions need their own verification. Recheck this document when network, storage, telemetry or diagnostic behavior changes.
