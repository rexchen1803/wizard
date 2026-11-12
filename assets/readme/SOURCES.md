# README artwork sources

The Simplified Chinese, Traditional Chinese, English and Japanese READMEs use the same illustrated composition, with separate desktop and narrow-screen panels for each language. Each panel is an SVG with outlined lettering and embedded, unmodified JPEG inputs. The surrounding layout is promotional artwork; the embedded App views are actual iPad Simulator captures from build `20261112.41`, not physical-device screenshots. Localized pages retain the original mixed Chinese/English App interface text in those images. Their provenance is recorded in [CAPTURE-METADATA.json](../demo/CAPTURE-METADATA.json).

## Artwork

The owner supplied these GTA VI files. Copyright remains with Rockstar Games and applicable rights holders; the images and derived panels are excluded from the MIT license. See [material attribution](../media/ATTRIBUTION.md). The collection's official-source references do not establish an independent byte-for-byte match for each supplied file.

| Input | SHA256 |
| --- | --- |
| `GTAVI_Artwork_Wallpapers/Jason_and_Lucia_01/Jason_and_Lucia_01_landscape.jpg` | `613da4597a6c63da703fd3bc5c82a4ba606d4dc03739ed77fe0b7317d6adc4ab` |
| `GTAVI_Screenshots/Places/Vice City/Vice_City_01.jpg` | `6cf14b23ae2c205799067464904f8c9dc99f87935632ef6924b87f59af7a6225` |

The App's bundled `ViceCity.jpg` remains the separately attributed chair photograph selected for the native build. No App pixels or display fonts are replaced in the embedded captures.

## Type

Latin display lettering uses the exact [Anton-Regular.ttf](../../App/Resources/Anton-Regular.ttf) bundled in the App; see [its license](../../App/Resources/Anton-OFL.txt). Promotional CJK lettering uses locale-specific Noto Sans CJK SC, TC and JP, separate from the App's native system CJK controls. The Noto fonts are optional artwork-generation inputs, not App resources. Both families use SIL OFL 1.1. [Noto license](../../licenses/NotoSansCJK-OFL.txt).

Pinned Noto source revision: [`f8d157532fbfaeda587e826d4cd5b21a49186f7c`](https://github.com/notofonts/noto-cjk/tree/f8d157532fbfaeda587e826d4cd5b21a49186f7c).

| Input within that repository | SHA256 |
| --- | --- |
| `Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf` | `2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b` |
| `Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Bold.otf` | `b5f0d1a190a7f9b43c310a8850630af12553df32c4c050543f9059732d9b4c0a` |
| `Sans/OTF/TraditionalChinese/NotoSansCJKtc-Regular.otf` | `dce08bd4fd91aa8aa76ed8fea4b694c2dfb8550f67871e326843212ddbeb88b4` |
| `Sans/OTF/TraditionalChinese/NotoSansCJKtc-Bold.otf` | `3ee160e5015106e3ec1a394301df54fa9bbbf8a251519984aec5c0abc50840c0` |
| `Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf` | `68a3fc98800b2a27b371f2fb79991daf3633bd89309d4ffaa6946fd587f375b5` |
| `Sans/OTF/Japanese/NotoSansCJKjp-Bold.otf` | `e53dcb0dcb2922e45d01aae1ebd2f382bb81d4229b18b6b883bd170678af1f76` |
| `Sans/LICENSE` | `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2` |

## Rebuild the artwork

Use Python 3 with `fonttools==4.60.2`, the pinned fonts above, and the separately supplied original artwork. Font installation is unnecessary. From the repository root:

```sh
python3 scripts/build-showcase.py \
  --cjk-regular /path/to/NotoSansCJKsc-Regular.otf \
  --cjk-bold /path/to/NotoSansCJKsc-Bold.otf \
  --traditional-regular /path/to/NotoSansCJKtc-Regular.otf \
  --traditional-bold /path/to/NotoSansCJKtc-Bold.otf \
  --japanese-regular /path/to/NotoSansCJKjp-Regular.otf \
  --japanese-bold /path/to/NotoSansCJKjp-Bold.otf \
  --hero-art /path/to/Jason_and_Lucia_01_landscape.jpg \
  --city-art /path/to/Vice_City_01.jpg \
  --out assets/readme
```

The generator writes all 56 panels for four languages and checks capture/source/font identity, input image digests, canvas bounds, missing localized translations and content overlap. It aligns visible glyph outlines to common content rails and writes the exact geometry and digests to `LAYOUT.json`. A passing generator still requires visual review of all four complete GitHub pages at desktop and phone widths. It does not build or install the App.

Localized campaign text is maintained in [COPY.json](COPY.json). Native date-language IDs remain independent of the README display order.


## Original website illustration

The owner requested reuse of `assets/demo/website-original.jpg` exactly as it appears in the personal website’s existing Wizard illustration. SHA-256: `01ea17a3bb25078f8adf13dba8904ffbd548ab52f4890456b581e199a023958f`. Its original screen, framing and lettering are unchanged. It is an illustrative website image, separate from the current-build native App captures. The four READMEs display this same file without a generated replacement.
