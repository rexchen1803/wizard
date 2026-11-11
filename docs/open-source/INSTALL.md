# Device setup and runtime files

## Validation status

This source tree builds an unsigned app and supports a separately packaged `.deb` preview for prepared rootful devices. Start with the [public installation guide](../INSTALL.md) for downloads, Agent prompts and current package behavior. No jailbreak utility, Apple SDK or device credentials are included. Build and export commands perform no device operations.

Local evidence as of 2026-11-11:

| Environment | Verified scope | Still pending |
| --- | --- | --- |
| iPad 2, iPad2,4, iOS 9.3.5 | Controlled update of an existing prepared installation through build `20261111.30`; launch, menu, gallery and preference preservation; scoped motion, calendar swipe and editor rollback integration; physical system Photos selection and actual image import | Fresh installation, physical accessibility and remaining interaction tests |
| iPad 4, iPad3,4, iOS 10.3.3 | Controlled update through build `20261111.30`; launch/menu/gallery, physical calendar pinch/drag/Cancel with exact2x raster restoration,280 native resource checks, local/remote video timing and physical video display; own preferences/media preserved | Fresh installation, physical accessibility and broader daily-use confirmation |
| iPad Air, iPad4,1, iOS 12.5.8 | User-operated recovery and existing-install update to `20261111.36` arm64; native main/menu/gallery/category/Locate and visual review; media subsequently synchronized to the same228 images/2 trailers, all file hashes checked, original settings retained except the matching index/key update | Remaining physical interaction/accessibility/full-playback/daily-use acceptance; the earlier app update lacks a pre-update hash of the actual50-key domain, while the subsequent media sync has its own complete live-domain baseline |
| Stock iOS sideloading | No verified installation | Signing, external storage access and private-framework behavior |

The Air result applies to this recovered, prepared installation. It does not establish a fresh or stock-device installation path. A historical stable-v1 installer tested a different build on one prepared iPad 2; it is not an installer for this candidate. The scoped source36 category checks on iPad2/4 supplement the source30 results in the table; their public scope is summarized in [COMPATIBILITY.md](../COMPATIBILITY.md).

Air's282 native ImageIO/AVFoundation resource checks apply to its earlier141-row catalog. The subsequent230-row sync is verified by full file-hash equality and native gallery/category/Locate rendering, not a fresh exhaustive decode or full playback of all460 referenced resources.

## Updating an existing prepared installation

The verified local workflow requires an already registered, working `com.rex.wizardsystem` installation, an active compatible jailbreak/unsandboxed environment, a trusted device channel, sufficient system-partition staging space, and the signing tools already validated on that device. It does not configure those prerequisites.

The tested update sequence is:

1. Read the hardware model, OS, installed bundle version, source fingerprint, executable hash and exact Wizard process. Preserve the external media tree and app preferences, including the separate power preferences. Verify the live runtime container and discover every exact `com.rex.wizardsystem.plist` domain; InstallationProxy can name a stale container for a jailbroken system app. Record hashes before modifying the app.
2. Build with [the build guide](README.md#build). Match all seven build-input hashes to the generated `BUILD-METADATA.txt`; verify the output architectures and executable hash. The iPad 2/4 update workflow extracts the `armv7` slice from the universal binary; the verified Air update uses `arm64`.
3. Clone the existing `WizardSystem.app` to a new staging directory on the same filesystem. Replace only the staged executable and `Info.plist`; retain the installed artwork and other bundle resources. The local iPad 2/4 workflow uses root:wheel ownership, executable mode `0755`, plist mode `0644`, and the device's existing `ldid -S` signing operation. This signing result is specific to the prepared devices above.
4. Verify the staged signed executable and the unchanged live executable, `Info.plist` and app-defaults digest. The local driver also backs up app and power preference files; it does not hash the entire live bundle or prove post-launch power-preference equality. Stop the exact verified Wizard process, retain the live bundle as a named rollback, and move the staged bundle into its place. Use the existing registered launch path. A failed transaction must restore that rollback before trying to launch again.
5. Read back the installed build, source fingerprint and signed executable hash. Check launch, gallery count/selection, imported photos, favorites, playback and saved layout. Confirm preferences and media retain the expected contents, and inspect the actual screen. A process or HTTP response alone does not prove successful use.

Only one controlled Wizard restart is inherent in this sequence; it also needs space for the staged bundle and retained rollback. Keep a complete original bundle and the immediate predecessor until acceptance. To roll back, stop the verified candidate process and restore the intact predecessor bundle using the same controlled transaction, preserving media and preferences. Restore saved preferences only when that recovery is explicitly intended; normal updates retain the current values.

The external media directory is not replaced during an app update. Historical installers which replace both the app and that directory can discard imports and are unsuitable for this workflow. No general-purpose installation command is supplied for unprepared or stock devices. Fresh installation, registration and filesystem provisioning remain unverified.

## Runtime layout

The app reads external resources under `/var/mobile/Media/iPadWizard/app`. These files are separate from `WizardSystem.app`:

```text
app/
  wallpapers.generated.js       optional wallpaper catalog
  assets/
    user/                       imported JPEGs and generated thumbnails
    wallpapers/                 example location for your own catalog images
    video/                      optional local videos
    audio/                      optional local audio
    depth/                      optional background/foreground image pairs
  home-status.json               optional integration input
  cast-state.json                optional integration input
```

`wallpapers/` is an example location, not a required directory name. Catalog paths can use other relative locations beneath the media root. The running app needs read access to supplied files and write/traverse access to `assets/user` or to its parents when creating it. The tested app process runs as mobile UID 501; the source does not provision ownership, permissions or sandbox access.

The source handles an absent catalog by loading any readable user imports. With no usable images, it clears the wallpaper background while continuing to build the clock UI. Imports attempt to create `assets/user` recursively and fail if the primary image cannot be written. These are source-inspected behaviors; a fresh, media-free installation has not yet passed native acceptance.

### Optional catalog

`wallpapers.generated.js` can contain a JSON array directly. The parser extracts the first `[` through the last `]`; a JavaScript wrapper is not required. For your own files:

```json
[
  {
    "key": "my-photo",
    "type": "image",
    "src": "assets/wallpapers/photo.jpg",
    "label": "My photo"
  },
  {
    "key": "my-video",
    "type": "video",
    "src": "assets/wallpapers/poster.jpg",
    "video": "assets/video/clip.mp4",
    "label": "My video"
  }
]
```

Supply those files yourself; the example includes no media. Each row requires a usable relative `src`. `type` defaults to `image` and accepts only `image` or `video`; video rows also require `video`. `thumb` defaults to `src`. Optional fields are `fileName`, `label`, numeric `width`/`height`, `themeClass` and `themeName`. Defaults are an empty filename/label/theme name, zero dimensions and `theme-sunset`.

Use unique, stable `key` values so catalog rearrangement can retain wallpaper identity. An omitted key falls back to the original array position; duplicate keys are skipped. The parser strips query suffixes and rejects absolute paths, colons and lexical traversal outside the root. It does not check file existence or resolve filesystem symlinks. See [the parser](../../App/IWMediaCatalog.h) for the exact contract.

The current gallery also reads an optional string `category`: `artwork`, `people`, `places`, `ultimate`, `vintage`, `video`, `user` or `other`. Categories are separate from display names and stable keys. Video rows are classified as videos and imported `user-` keys as system photos; missing or unknown category values remain visible under Other. The category control filters the gallery and can combine with favorites; it does not reorder or renumber the underlying catalog.

The scoped builds20261111.35/36 updates and gallery captures are summarized in [COMPATIBILITY.md](../COMPATIBILITY.md). That update retained system-partition headroom by hard-linking eight immutable bundle resources between each new live bundle and its retained predecessor; the executable and Info.plist were created separately. Future resource replacements must use new files/atomic replacement rather than mutate those shared resource inodes. The full source30 bundle is also backed up locally. This optimization does not provision a fresh device.

### Imports and optional assets

Imports write `assets/user/user-<milliseconds>-<lowercase UUID>.jpg` and a sibling ending in `-thumb.jpg`. The app caps the full image's long edge at 3840 pixels and generates a 640×360 thumbnail. Loading scans decodable `.jpg` imports, skips thumbnail files and tries to recreate missing thumbnails. Back up both files. Deletion removes Wizard's imported copy, leaving the original Photos asset intact.

The optional local video buttons use `assets/video/gta6-trailer-1080p-ipad2-test.mp4` and `assets/video/gta6-trailer-2-1080p-ipad.mp4`; local music uses `assets/audio/love-is-a-long-road-preview.m4a`. Depth mode uses matching `assets/depth/<key>-bg.jpg` and `<key>-fg.png`, with a legacy GTA fallback pair. These paths describe existing code and do not grant rights to distribute those assets. Missing optional assets do not become part of the source export.

Wallpaper identity, favorites, framing and layout are stored in the app's `NSUserDefaults` domain `com.rex.wizardsystem`, separately from the external media tree. Power integration also uses `com.rex.wizardpower.plist` and `com.rex.wizardsystem.power.plist` under `/var/mobile/Library/Preferences`. Preserve those files when applicable; copying only media is not a complete state backup.

Read [privacy and network behavior](PRIVACY.md) and [third-party attribution](../../THIRD_PARTY.md) before supplying assets or enabling integrations. Weather, power and the partial SOAP control interfaces retain their separate implementation and device-acceptance limits.
