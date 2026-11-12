# Local data and network behavior

[简体中文](../zh-CN/PRIVACY.md) · [繁體中文](../zh-TW/PRIVACY.md) · **English** · [日本語](../ja/PRIVACY.md)

This describes the iPad source candidate, not an App Store privacy declaration or proof of device acceptance.

## Photos and preferences

Wizard can import a photo selected through the system picker. It writes a resized JPEG and a thumbnail to `/var/mobile/Media/iPadWizard/app/assets/user`. Favorites, wallpaper framing, clock/calendar layout and settings are stored on the device. Deleting a user-imported wallpaper removes Wizard's copy; it does not delete the original from Photos. Bundled media and user-imported media are separate.

The reviewed source export contains no personal photos, media library, preferences, device snapshots, SSH keys or connection credentials. It includes the licensed Anton display font, Wizard-authored launch images and an attributed Vice City fallback wallpaper; historical theme fonts, music and full video/media packs are excluded. You can run the clock and import your own photos without the optional external wallpaper catalog.

## Cast and remote playback

Cast is off on launch. The Cast control asks before opening the local-network receiver; toggling it again or backgrounding the App closes it. While enabled, it listens for HTTP on port8199 and SSDP discovery on UDP1900. Discovery uses a random session identifier rather than the vendor device identifier. DLNA has no sender authentication; use a trusted local network and do not forward its ports.

Each submitted HTTP(S) playback URL requires approval on the iPad before fetching. The prompt shows only its host. Closing the request also closes the receiver. URLs with embedded usernames/passwords or more than4096 characters are rejected; inactive or stopped receivers ignore requests. After approval, the iPad connects directly to the selected media server, which receives normal connection information and any query tokens supplied by the sender. HTTP local media remains supported through `NSAllowsArbitraryLoads`.

The SOAP surface is partial: Play/Pause/Stop/Seek do not control playback; transport and position responses are fixed placeholders. An HTTP success does not establish playback. Media catalog paths reject traversal and symlink descendants at load time while retaining stable lexical identities; this does not protect against privileged concurrent filesystem replacement.

## Weather

Weather is optional. When enabled, Wizard asks for location permission and sends latitude/longitude to the Open-Meteo HTTPS forecast endpoint. Reverse geocoding uses Apple's location services to obtain a city name. The on-device cache stores coordinates, city, weather and fetch time so it can show cached conditions and retry with cached coordinates if location is unavailable. Disabling weather stops location updates and scheduled refreshes. The evaluation provider's current terms and attribution must be reviewed before distribution.

## Diagnostics and optional integrations

Physical-device diagnostic state requires the temporary `wizardsystem-debug` marker. The separate Simulator preview can record test state. Diagnostic state may include wallpaper and playback URLs; redact it before sharing. Cast logs require the marker and record hosts/status rather than full playback URLs, query tokens or request bodies. Weather and performance diagnostics retain their separate opt-in markers. Logs, user media and device records are excluded from the source export.

On device, the `wizardsystem` URL scheme accepts only the exact launch route `wizardsystem://main`, retained for the optional power add-on. External settings and power-control commands are rejected. Simulator diagnostics use a separate allowlisted CLI path; they are not device IPC permissions.

Experimental file interfaces and the optional WizardPower tweak retain the documented rootful environment requirements. The installer does not install the tweak or enable privileged integrations.


The optional power add-on no longer registers remote Darwin lock, wake or status requests; local hardware power-edge automation remains. Its diagnostic log requires the temporary `wizardpower-debug` marker.

## Validation limits

Code inspection, host regressions and clean export scans are separate from a three-device data-flow review. Remote server behavior, an installed device's configuration, and third-party additions need their own verification. Recheck this document when network, storage, telemetry or diagnostic behavior changes.
