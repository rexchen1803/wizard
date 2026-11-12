# Third-party materials and build requirements

[简体中文](docs/zh-CN/THIRD_PARTY.md) · [繁體中文](docs/zh-TW/THIRD_PARTY.md) · **English** · [日本語](docs/ja/THIRD_PARTY.md)

**Wizard-authored code license: MIT.** See the root [`LICENSE`](LICENSE), which applies to Wizard-authored code only. Third-party materials remain subject to their own rights and are not relicensed by that file.

## Google Material-derived vector paths

The iPad app source contains vector drawing paths from Google Material icons. The official [`material-design-icons` repository at the pinned revision](https://github.com/google/material-design-icons/tree/10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7) makes the icons available under Apache License 2.0; its upstream [`LICENSE`](https://github.com/google/material-design-icons/blob/10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7/LICENSE) is included at `licenses/Material-Icons-Apache-2.0.txt`.

The pinned source inventory is in [MATERIAL-ICONS.md](docs/open-source/MATERIAL-ICONS.md). In `IWMaterialPathForButton`, 35 variants map to 33 upstream SVG files, all using the pinned path data. The former game-only Pet and Leaderboard paths have been removed. Drawing stays in local Core Graphics code; no Google SVG, font, or image binary is included. The Theme button retains its custom three-color drawing branch. See the root [`NOTICE`](NOTICE) for attribution and modification details. The accompanying Apache 2.0 license is separate from the app license.

At the pinned revision, the repository root contains a `LICENSE`; no separate `NOTICE`, `COPYING`, or copyright file was found at the mapped SVG paths or their ancestors. The retained mapping was checked on 2026-11-12 against the previously verified 2026-11-10 inventory; retained path data is unchanged. This records the available source evidence and does not claim legal clearance.

## Apple SDK and system frameworks

`build-ipad.sh` uses UIKit, Foundation, AVFoundation, MediaPlayer, CoreMotion, CoreLocation, CoreMedia, CoreText, QuartzCore, CoreGraphics and CoreFoundation from an iPhoneOS SDK supplied by the builder. No Apple SDK, framework binary, or SDK header is included in this candidate. Obtain the SDK through Apple’s development tools and follow the applicable Apple terms.

The source also dynamically opens private `BackBoardServices`, `GraphicsServices`, and `SpringBoardServices` frameworks for display and lock operations. The build retains `dynamic_lookup`; the compile does not validate runtime symbol availability or stock-device behavior. The app’s `/var/mobile/Media` and `/var/mobile/Library/Preferences` paths reflect a historical jailbroken/unsandboxed deployment assumption; see [README](docs/open-source/README.md). Stock sideloading is unvalidated.

## Theos and the power tweak

The optional `WizardPowerTweak` source is included, but Theos, Logos, vendored headers, libraries, and the private workspace Makefile/toolchain are not. The private workspace’s Theos package metadata identifies Theos as GPL-3.0-or-later; anyone building with Theos must obtain and comply with the license for their own copy. The main App build script does not build the addon. The optional `scripts/build-power.sh` entry builds the current source directly with Apple clang; it does not need or redistribute Theos. Runtime injection and power behavior require separate device acceptance.

## Excluded materials

The source export intentionally excludes the local iOS SDK and vendored build tools; private/device installers, SSH material, connection logs, known-host data, and device-state files; compiled historical apps; the original/full media collections from Git source; fonts and artwork with unverified rights; and unrelated workspace content. Selected native demonstration captures in `assets/demo` are included with Rockstar attribution, and the full media packs are separate GitHub Release-draft attachments. The export report records the MIT license scope for Wizard-authored code, separately records third-party media exclusions, and records the source/export scope separately from release publication. The preview release does not claim fresh-install, live-weather or complete physical-device acceptance.

## Weather provider

The optional weather adapter is retained for evaluation and is not accepted as a live provider integration. The weather card now exposes a localized provider-credit control and information sheet identifying Open-Meteo, linking the [CC BY 4.0 licence](https://open-meteo.com/en/licence), and noting Wizard's modifications. Bounded synthetic-fixture runs and native card/detail captures were accepted on earlier builds on iPad 2 and iPad 4; they are not current-build physical-device evidence. Air acceptance remains pending. This control does not prove a live Open-Meteo connection: the earlier device request returned TLS error `-1202`, and no trust override was applied.

Open-Meteo's current [terms](https://open-meteo.com/en/terms) say its free hosted API is for non-commercial use and require acceptance of CC BY 4.0 data terms; its [licence page](https://open-meteo.com/en/licence) requires appropriate credit, a licence link, and an indication of changes. Commercial hosted API use has separate subscription terms. These provider terms are separate from Wizard's application licence. The source candidate does not establish that a future deployment qualifies for a particular endpoint or use, and no legal clearance is claimed. Recheck the provider terms and obtain any required authorization before enabling or distributing live weather. Provider terms and licence rechecked November 12, 2026.

## Rockstar Games GTA VI media

All GTA VI-labelled images and videos, including crops, transcodes, cutouts, and other derived media, are attributed to Rockstar Games and the other applicable rights holders. This broad attribution records the project owner's statement that the materials came from Rockstar's official website public downloads. The official [Artwork & Wallpapers](https://www.rockstargames.com/VI/media/artwork-wallpapers), [GTA VI media](https://www.rockstargames.com/VI/media), and [videos](https://www.rockstargames.com/VI/media/videos) pages are linked in [GTA6-MATERIALS.md](docs/open-source/GTA6-MATERIALS.md). Public downloads do not grant MIT rights or, by themselves, authorize redistribution in this project.

Consult Rockstar's [Legal Terms](https://www.rockstargames.com/legal/) and [copyright posting policy](https://support.rockstargames.com/articles/7bNaeoMFTV0iUDGhStTXvz/policy-on-posting-copyrighted-rockstar-games-material) for its content requirements. Attribution is not redistribution permission or official endorsement; no legal clearance is claimed here.

The optional gallery package contains 228 images, 2 retained GTA VI trailers and their thumbnails; full artwork and original files remain separate Release-draft media packs. Exact inventory and provenance limits are in [GTA6-MATERIALS.md](docs/en/GTA6-MATERIALS.md) and the [media manifest](assets/media/MANIFEST.json). The two SRT files in the originals pack have independently unverified authorship and are not claimed as official Rockstar subtitles. User imports are outside this Rockstar attribution.

## Anton display font

The unmodified static `App/Resources/Anton-Regular.ttf` is Copyright 2020 The Anton Project Authors and distributed under the SIL Open Font License 1.1, included at [App/Resources/Anton-OFL.txt](App/Resources/Anton-OFL.txt). Source: [Google Fonts, pinned revision cee74d7ca45d66d5c1878c828645c862f2788d2d](https://github.com/google/fonts/tree/cee74d7ca45d66d5c1878c828645c862f2788d2d/ofl/anton). SHA256: `a4ba3a92350ebb031da0cb47630ac49eb265082ca1bc0450442f4a83ab947cab`. The font and license are bundled with the App; the font is separate from the MIT source license. README display lettering may be rendered from the same face.

## Noto CJK promotional lettering

README reading text and CJK lettering are outlined from locale-specific Noto Sans CJK SC, TC and JP Regular and Bold under SIL OFL 1.1. The font files are optional artwork-generation inputs and are not bundled in the App. The verbatim [upstream license](licenses/NotoSansCJK-OFL.txt), pinned source revision, input checksums and generation instructions are recorded in [README artwork sources](assets/readme/SOURCES.md).

## Bundled display and promotional images

The reviewed `App/Resources/ViceCity.jpg` is included as a fallback wallpaper, and selected supplied images appear in README artwork and native captures. The original filename and checksum are recorded in [material attribution](assets/media/ATTRIBUTION.md). These images and derivatives retain Rockstar Games and applicable rights-holder copyright; they are excluded from the MIT license. Full media packs remain separate Release attachments. No proprietary Rockstar fonts are bundled.
