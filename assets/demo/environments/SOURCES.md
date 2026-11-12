# Lifestyle scene sources

The four images are illustrative environment compositions. Their entire App display comes from the unchanged native PNG recorded in [the capture manifest](../screens/CAPTURE-METADATA.json): Wizard build **20261112.41**, iPad (8th generation) Simulator / iOS 18.0. They are not physical-device photographs or evidence that this build runs on the pictured legacy hardware.

| Image | Environment | Hardware appearance reference | Native screen |
| --- | --- | --- | --- |
| [Warm study](website-study.jpg) | Existing personal website Wizard illustration, reused at the owner's request. | Existing classic iPad-style device; exact model unspecified. | [City at night](../screens/night-city.png) |
| [Daylight desk](daylight-desk.jpg) | Generated environment with hardware refinement. | White/silver [iPad 2](https://support.apple.com/en-ie/111990), 2011. | [Island minimal](../screens/island-minimal.png) |
| [Bedside](linen-bedside.jpg) | Generated environment with hardware refinement. | Black/silver [iPad (4th generation)](https://support.apple.com/en-us/111993), 2012. | [Sunset artwork](../screens/sunset-poster.png) |
| [Blue-hour console](dusk-console.jpg) | Generated environment with hardware refinement. | Space gray [iPad Air (1st generation)](https://support.apple.com/en-ie/112020), 2013. | [Green retreat](../screens/green-retreat.png) |

Apple's product images and specifications were used for shape reference only. The broad iPad 2/4 bezels, older home-button glyph and slimmer first-generation Air form were compared with those references. These are generated hardware illustrations, not calibrated engineering renders or Apple product photography. The Apple reference images themselves are not redistributed in this tree.

## Screen integrity

[SCENES.json](SCENES.json) records each retained environment plate, source PNG SHA-256, four display corners, perspective mapping, final JPEG hash and dimensions. The native PNG remains available without any photo composition or JPEG encoding. Each complete 4:3 source screen is mapped once by a CSS homography; no screen crop, type replacement, color filter, invented widget or additional UI layer is applied. The final scene JPEG includes ordinary browser resampling and JPEG encoding.

The original website image was `wizard-feature.jpg`, SHA-256 `01ea17a3bb25078f8adf13dba8904ffbd548ab52f4890456b581e199a023958f`. Its entire unverified screen plane is covered by the current App capture. Only the surrounding environment is reused; the landscape export crops the room independently of the screen.

## Reproduction

Run from the repository root with Python 3:

```sh
python3 scripts/build-lifestyle.py --out /tmp/wizard-lifestyle-html
```

The output directory must not already exist. Open the generated HTML in a browser with a 1536 × 1024 content viewport and device scale factor 1, wait for both images to finish loading, and capture the content viewport. The script checks source/capture hashes, source dimensions, projection corners and capture identity. It does not connect to or install on a device. The selected plates are retained in [plates](plates); the [prompt set](PROMPTS.md) records the built-in imagegen environment and hardware prompts.

## Rights

GTA VI images inside the native screens and their derivatives remain copyright Rockstar Games and applicable rights holders, excluded from Wizard's MIT source-code license. The personal website illustration is owner-supplied reference material; no independent authorship or redistribution-rights verification is claimed. Apple names and hardware designs belong to their respective owners; no Apple or Rockstar endorsement is implied. See [the shared material attribution](../../media/ATTRIBUTION.md).


## Privacy scan scope

The export scanner reads PNG ancillary metadata and decodes compressed text/profile chunks with a bounded size. Malformed or oversized compressed metadata blocks the export. Compressed `IDAT` pixel data is not interpreted as plain contact text; the original native pixel content and image metadata are reviewed separately. This preserves the exact native PNG files instead of changing their encoding to avoid accidental byte patterns.
