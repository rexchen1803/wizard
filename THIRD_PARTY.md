# Third-party materials and build requirements

**Wizard-authored code license: MIT.** See the root [`LICENSE`](LICENSE), which applies to Wizard-authored code only. Third-party materials remain subject to their own rights and are not relicensed by that file.

## Google Material-derived vector paths

The iPad app source contains vector drawing paths from Google Material icons. The official [`material-design-icons` repository at the pinned revision](https://github.com/google/material-design-icons/tree/10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7) makes the icons available under Apache License 2.0; its upstream [`LICENSE`](https://github.com/google/material-design-icons/blob/10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7/LICENSE) is included at `licenses/Material-Icons-Apache-2.0.txt`.

The pinned source inventory is in [MATERIAL-ICONS.md](docs/open-source/MATERIAL-ICONS.md). In `IWMaterialPathForButton`, 35 variants map to 33 upstream SVG files, all using the pinned path data. The former game-only Pet and Leaderboard paths have been removed. Drawing stays in local Core Graphics code; no Google SVG, font, or image binary is included. The Theme button retains its custom three-color drawing branch. See the root [`NOTICE`](NOTICE) for attribution and modification details. The accompanying Apache 2.0 license is separate from the app license.

At the pinned revision, the repository root contains a `LICENSE`; no separate `NOTICE`, `COPYING`, or copyright file was found at the mapped SVG paths or their ancestors. The retained mapping was checked on 2026-11-12 against the previously verified 2026-11-10 inventory; retained path data is unchanged. This records the available source evidence and does not claim legal clearance.

## Apple SDK and system frameworks

`build-ipad.sh` uses UIKit, Foundation, AVFoundation, MediaPlayer, and CoreMotion, CoreLocation, CoreMedia, QuartzCore, CoreGraphics and CoreFoundation from an iPhoneOS SDK supplied by the builder. No Apple SDK, framework binary, or SDK header is included in this candidate. Obtain the SDK through Apple’s development tools and follow the applicable Apple terms.

The source also dynamically opens private `BackBoardServices`, `GraphicsServices`, and `SpringBoardServices` frameworks for display and lock operations. The build retains `dynamic_lookup`; the compile does not validate runtime symbol availability or stock-device behavior. The app’s `/var/mobile/Media` and `/var/mobile/Library/Preferences` paths reflect a historical jailbroken/unsandboxed deployment assumption; see [README](docs/open-source/README.md). Stock sideloading is unvalidated.

## Theos and the power tweak

The optional `WizardPowerTweak` source is included, but Theos, Logos, vendored headers, libraries, and the private workspace Makefile/toolchain are not. The private workspace’s Theos package metadata identifies Theos as GPL-3.0-or-later; anyone building with Theos must obtain and comply with the license for their own copy. The main App build script does not build the addon. The optional `scripts/build-power.sh` entry builds the current source directly with Apple clang; it does not need or redistribute Theos. Runtime injection and power behavior require separate device acceptance.

## Excluded materials

The source export intentionally excludes the local iOS SDK and vendored build tools; private/device installers, SSH material, connection logs, known-host data, and device-state files; compiled historical apps; the original/full media collections from Git source; fonts and artwork with unverified rights; and unrelated workspace content. Selected native demonstration captures in `assets/demo` are included with Rockstar attribution, and the full media packs are separate GitHub Release attachments. The export report records the MIT license scope for Wizard-authored code, separately records third-party media exclusions, and records the source/export scope separately from release publication. The preview release does not claim fresh-install, live-weather or complete physical-device acceptance.

## Weather provider

The optional weather adapter is retained for evaluation and is not accepted as a live provider integration. The weather card now exposes a localized provider-credit control and information sheet identifying Open-Meteo, linking the [CC BY 4.0 licence](https://open-meteo.com/en/licence), and noting Wizard's modifications. Bounded synthetic-fixture runs and native card/detail captures have been accepted on iPad 2 and iPad 4; Air acceptance remains pending. This control does not prove a live Open-Meteo connection: the earlier device request returned TLS error `-1202`, and no trust override was applied.

Open-Meteo's current [terms](https://open-meteo.com/en/terms) say its free hosted API is for non-commercial use and require acceptance of CC BY 4.0 data terms; its [licence page](https://open-meteo.com/en/licence) requires appropriate credit, a licence link, and an indication of changes. Commercial hosted API use has separate subscription terms. These provider terms are separate from Wizard's application licence. The source candidate does not establish that a future deployment qualifies for a particular endpoint or use, and no legal clearance is claimed. Recheck the provider terms and obtain any required authorization before enabling or distributing live weather. Checked November 11, 2026.

## Rockstar Games GTA VI media

All GTA VI-labelled images and videos, including crops, transcodes, cutouts, and other derived media, are attributed to Rockstar Games and the other applicable rights holders. This broad attribution records the project owner's statement that the materials came from Rockstar's official website public downloads. The official [Artwork & Wallpapers](https://www.rockstargames.com/VI/media/artwork-wallpapers), [GTA VI media](https://www.rockstargames.com/VI/media), and [videos](https://www.rockstargames.com/VI/media/videos) pages are linked in [GTA6-MATERIALS.md](docs/open-source/GTA6-MATERIALS.md). Public downloads do not grant MIT rights or, by themselves, authorize redistribution in this project.

Rockstar's [Legal Terms](https://www.rockstargames.com/legal/) reserve rights to its content and restrict copying or distribution absent separate express written terms, subject to applicable law. Its [copyright posting policy](https://support.rockstargames.com/articles/7bNaeoMFTV0iUDGhStTXvz/policy-on-posting-copyrighted-rockstar-games-material) describes limited, occasional non-commercial fan uses; the policy says it does not apply to digital publishing. No legal clearance is claimed here.

The full Rockstar artwork, screenshot and trailer collections are distributed separately as attributed Release media packs. The source repository includes their manifests and selected native demo captures under the same third-party rights exception; these are not relicensed under MIT. Historical metadata snapshots before the local media refresh record 137 GTA VI image entries, 2 GTA VI trailer entries, and 2 separate F1 video entries in the iPad 2 catalog; the iPad 4 catalog records 136 GTA VI image entries, 2 GTA VI trailer entries, and the same 2 F1 entries. The 2026-11-11 media refresh now records 228 images and two retained GTA VI trailers per device, with F1 entries removed; its current source/name/key mapping and scoped receipt are linked from GTA6-MATERIALS.md. The source doc distinguishes the owner's broad provenance statement from independently matched file-to-URL records. The F1 entries and user imports are not attributed to Rockstar by this record.

## Bundled display and promotional images

The reviewed `App/Resources/ViceCity.jpg` is included as a fallback wallpaper, and selected supplied images appear in README artwork and native captures. The original filename and checksum are recorded in [material attribution](assets/media/ATTRIBUTION.md). These images and derivatives retain Rockstar Games and applicable rights-holder copyright; they are excluded from the MIT license. Full media packs remain separate Release attachments. No proprietary Rockstar fonts are bundled.
