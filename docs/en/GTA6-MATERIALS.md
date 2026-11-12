[简体中文](../open-source/GTA6-MATERIALS.md) · [繁體中文](../zh-TW/GTA6-MATERIALS.md) · **English** · [日本語](../ja/GTA6-MATERIALS.md)

# GTA VI materials: sources and rights

Copyright in GTA VI images, videos, screenshots and their thumbnails, transcodes and crops belongs to **Rockstar Games and applicable rights holders**. These materials are managed separately from Wizard-authored code and are not licensed by the project’s MIT License. This project is not affiliated with, sponsored by or endorsed by Rockstar Games.

## Distribution status and media packs

As checked on 2026-11-13, [v0.2.0-preview.5](https://github.com/rexchen1803/wizard/releases/tag/v0.2.0-preview.5) is public and both media packs below can be downloaded without signing in. The manifest's `download_url` fields are pinned to this version; verify their sizes and SHA-256 values after downloading.

| Media pack | Contents recorded in the manifest | Intended use |
| --- | --- | --- |
| `wizard-gta6-gallery-20261112.zip` | 464 files: 230 gallery catalog entries, 228 landscape images, 2 MP4 trailers and 230 thumbnails, with 460 media references. | Optional Wizard gallery. |
| `gta6-original-materials-20261112.zip` | 350 files: 343 original JPEGs, 2 MKV videos, 2 SRT subtitle files and supporting package files. | Original-material archive and reference for later work. |

The [media manifest](../../assets/media/MANIFEST.json) records byte size, SHA-256 and package contents. Each archive includes a per-file manifest, copyright attribution and a usage note. Original filenames are preserved; the App gallery manages categories, short display labels and stable keys separately. The authorship of the two SRT files has not been independently verified, so they are not represented as official Rockstar subtitles.

Source checks, filename matching and category records do not prove every file’s byte-level provenance and do not grant redistribution rights. Each file remains subject to its applicable rights.

## Official Rockstar sources

The project owner assembled the materials from Rockstar’s public media and download pages:

- [GTA VI Artwork & Wallpapers](https://www.rockstargames.com/VI/media/artwork-wallpapers)
- [GTA VI Media](https://www.rockstargames.com/VI/media)
- [GTA VI Videos](https://www.rockstargames.com/VI/media/videos)
- [Rockstar Games Legal Terms](https://www.rockstargames.com/legal/)

The project’s source-file records include 27 wallpaper compositions and 142 size or logo variants, 138 game screenshots, 51 Ultimate Edition images and 12 Vintage Vice City Pack images. The gallery selects one landscape image from each wallpaper composition and retains all screenshots and content-pack images. Rockstar’s pages may change; the exact scope described here is fixed by the [media manifest](../../assets/media/MANIFEST.json) and each archive’s per-file manifest.

## Repository demonstrations and license scope

The repository’s [demo provenance guide](../../assets/demo/README.en.md) identifies the bundled App captures: the current eight `*-miami.jpg` files and `clock-font-system.jpg` are native captures from build `20261112.41` in an iPad (8th generation) Simulator running iOS 18; the `*-ipad2.png` files are earlier physical-device screenshots from build `20261111.36`. GTA VI imagery in those captures remains the property of Rockstar Games and applicable rights holders; it is not covered by Wizard’s MIT code license.

The media packs exclude user photos, preferences, device backups, connection information, F1 videos, historical game audio, fonts and Apple SDKs. See the [installation guide](../open-source/INSTALL.md) for installation and runtime conditions, and [ATTRIBUTION.md](../../assets/media/ATTRIBUTION.md) for the consolidated attribution record.

## App fallback image and promotional artwork

The current App build includes `App/Resources/ViceCity.jpg`, sourced from `ULTIMATE_EDITION_VICE_CITY_STYLE_01.jpg`. The repository copy is byte-identical to the source file: 3840 × 2160 pixels, SHA-256 `c255874fee509eae0baa6f546861e483ec0b32efbfe8d013ec36888013d923c9`. The App uses it only as the fallback display image when no external gallery catalog is present. The README’s promotional artwork and native captures also include attributed Rockstar material. These images and derivatives are outside the MIT license. The App separately includes an SIL OFL font; no Rockstar font files are distributed.

## Related records

- [Media manifest and checksums](../../assets/media/MANIFEST.json)
- [Consolidated material attribution](../../assets/media/ATTRIBUTION.md)
- [Demo capture sources and metadata](../../assets/demo/README.en.md)
- [Third-party licenses and service terms](../../THIRD_PARTY.md)
