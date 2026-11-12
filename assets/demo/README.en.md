# Demonstration capture provenance

[简体中文](README.md) · [繁體中文](../../docs/zh-TW/CAPTURES.md) · **English** · [日本語](../../docs/ja/CAPTURES.md)

## Current Miami preview

The `*-miami.jpg` images are native UIKit output from build **20261112.41** on an **iPad (8th generation) Simulator / iOS 18.0**. Original PNGs are 2160×1620; web JPEGs preserve those dimensions with quality 85 encoding. No App controls were composited, added or redrawn. Original PNG and web-image digests, scene commands and the source fingerprint are in [CAPTURE-METADATA.json](CAPTURE-METADATA.json).

- [Home](home-miami.jpg): the built-in Vice City image with no external catalog.
- [Gallery](gallery-miami.jpg) and [categories](categories-miami.jpg): a demonstration catalog with the 230 media-pack entries plus the selected fallback image, 231 items total. No user photos were included.
- [Main menu](menu-miami.jpg), [settings](settings-miami.jpg) and [themes](themes-miami.jpg).
- [Clock editing](clock-edit-miami.jpg) and [calendar](calendar-miami.jpg).

These captures and the `armv7 + arm64` device build share the same source/resource fingerprint. The Simulator has a separate App identifier and sandbox media directory. Reproduction is documented under [Native simulator preview](../../docs/open-source/README.md#native-simulator-preview). Simulator rendering does not establish operation on legacy physical iPads. The English README preserves these actual App images with their original mixture of Chinese and English UI text.

## More layouts and lifestyle scenes

These six unmodified PNGs are native captures of build **20261112.41** on an **iPad (8th generation) Simulator / iOS 18.0**: [Sunset poster](screens/sunset-poster.png), [island minimal](screens/island-minimal.png), [night city](screens/night-city.png), [city calendar](screens/city-calendar.png), [green retreat](screens/green-retreat.png) and [palm drive](screens/palm-drive.png). Dimensions, digests and Simulator provenance are in the [capture metadata](screens/CAPTURE-METADATA.json).

Lifestyle scenes: [website study](environments/website-study.jpg), [daylight desk](environments/daylight-desk.jpg), [linen bedside](environments/linen-bedside.jpg) and [dusk console](environments/dusk-console.jpg). Website study reuses the user-supplied setting with its old screen fully replaced by a current App capture; the other three are generated environment illustrations. Each App screen is a deterministic projection of an original capture above, with no invented or redrawn UI. The iPad 2, iPad 4 and first-generation iPad Air forms are illustrative; these scenes do not show build 41 running on those physical devices or establish compatibility or device acceptance. Composition and source records are in [SCENES.json](environments/SCENES.json).

## Display font

The current build bundles the static `Anton-Regular.ttf` and its OFL 1.1 license. Capture metadata records the actual clock font name, font-file SHA256 and bundled-file origin. CJK controls use system fonts. The historical source36 device images retain their original appearance.

Long-press the time and choose **Clock font → Poster / System**. Poster uses bundled Anton; System uses iOS monospaced digits. Done saves; Cancel restores the previous selection. The [System font editor capture](clock-font-system.jpg) shows the actual selector.

## Historical physical-device images

These source36 PNGs retain their original pixels, captured on iPad2,4 / iOS9.3.5 on 2026-11-11:

- [Historical home](home-ipad2.png)
- [Historical gallery](gallery-ipad2.png)
- [Historical categories](categories-ipad2.png)

They document the earlier build and do not establish physical-device acceptance of the current Miami build.

## Rights

GTA VI content in these captures belongs to Rockstar Games and applicable rights holders. The images are excluded from Wizard's MIT code license. See [material attribution](../media/ATTRIBUTION.md).
