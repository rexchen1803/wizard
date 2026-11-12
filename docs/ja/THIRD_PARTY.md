[简体中文](../zh-CN/THIRD_PARTY.md) · [繁體中文](../zh-TW/THIRD_PARTY.md) · [English](../../THIRD_PARTY.md) · **日本語**

# 第三者素材とビルド要件

**Wizard 作成コードのライセンス: MIT。** 適用範囲はルートの [`LICENSE`](../../LICENSE) を参照してください。Wizard 作成コードだけに適用されます。第三者素材には各自の権利が適用され、このファイルによって再許諾されません。

## Google Material 由来のベクターパス

iPad App のソースには Google Material icon 由来のベクター描画パスがあります。固定 revision の公式 [`material-design-icons` リポジトリ](https://github.com/google/material-design-icons/tree/10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7) はアイコンを Apache License 2.0 で公開しています。上流の [`LICENSE`](https://github.com/google/material-design-icons/blob/10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7/LICENSE) は `licenses/Material-Icons-Apache-2.0.txt` に含まれます。

固定したソース一覧は [MATERIAL-ICONS.md](../open-source/MATERIAL-ICONS.md) にあります。`IWMaterialPathForButton` の35種類は、上流の SVG 33ファイルに対応し、固定済みのパスデータを使います。ゲーム専用だった旧 Pet と Leaderboard の描画パスは削除済みです。描画はローカルの Core Graphics コードで行い、Google の SVG、フォント、画像バイナリは含みません。Theme ボタンには独自の3色描画処理を残しています。帰属と変更の詳細はルート [`NOTICE`](../../NOTICE) を参照してください。Apache 2.0 ライセンスは App ライセンスとは別です。

固定リビジョンではリポジトリのルートに `LICENSE` があります。対応 SVG のパスまたは上位ディレクトリには、別の `NOTICE`、`COPYING`、著作権ファイルは見つかりませんでした。保持した対応関係は、既に確認済みの2026-11-10一覧と照合して2026-11-12に確認し、保持パスのデータに変更はありません。これは利用可能なソース証拠の記録であり、法的許可を主張するものではありません。

## Apple SDK と system framework

`build-ipad.sh` はビルダーが Apple の開発ツールから取得した iPhoneOS SDK の UIKit、Foundation、AVFoundation、MediaPlayer、CoreMotion、CoreLocation、CoreMedia、CoreText、QuartzCore、CoreGraphics、CoreFoundation を使います。この候補には Apple SDK、フレームワークのバイナリ、SDK のヘッダー は含まれません。Apple の開発ツールから SDK を取得し、適用される Apple の条件に従ってください。

ソースは画面表示とロック操作のため、Apple 非公開の `BackBoardServices`、`GraphicsServices`、`SpringBoardServices` フレームワークも動的に開きます。ビルドでは `dynamic_lookup` を維持します。コンパイル成功は、実行時のシンボルの有無や通常の iOS 端末での動作は確認しません。App の `/var/mobile/Media` と `/var/mobile/Library/Preferences` パスは、過去の脱獄済み／sandbox 外への配置前提を反映します。[README](../open-source/README.md)を参照してください。通常の sideload は未検証です。

## Theos と電源 tweak

任意の `WizardPowerTweak` ソースは含まれますが、Theos、Logos、同梱 header／library、非公開 workspace の Makefile／toolchain は含まれません。非公開 workspace の Theos パッケージ metadata は Theos を GPL-3.0-or-later としています。Theos でビルドする人は、自身のコピーについてライセンスを取得し遵守する必要があります。メイン App の build script は addon をビルドしません。任意の `scripts/build-power.sh` は Apple clang で現行ソースを直接ビルドします。Theos を必要とせず、再配布もしません。実行時注入と電源動作には別途実機受け入れが必要です。

## 除外素材

ソースの書き出しでは意図的に、ローカル iOS SDK と同梱ビルドツール、非公開／端末用 installer、SSH 素材、接続ログ、known-host data、端末状態ファイル、過去のコンパイル済み App、Git source に含める元データ／全メディア集、権利未確認の font と artwork、無関係な workspace 内容を除外します。`assets/demo` の選定済みネイティブデモキャプチャは Rockstar の帰属表示付きで含まれます。フルメディアパックは GitHub Releases の下書きへの添付として別管理です。書き出しレポートには Wizard 作成コードの MIT 範囲、第三者メディアの除外、ソース／export 範囲と Release 公開状態をそれぞれ記録します。プレビューは新規インストール、稼働中の天気サービス、物理端末全般の受け入れを主張しません。

## 天気プロバイダー

任意の天気アダプターは評価用に残しており、稼働中のサービス連携としては受け入れられていません。天気カードには、Open-Meteo を示し、[CC BY 4.0 license](https://open-meteo.com/en/licence) にリンクして、Wizard による変更を記す サービス提供元を示すクレジット表示と説明画面があります。以前のビルドでは、iPad 2 と iPad 4 で合成テスト用データを使った限定確認を行い、カードと詳細画面のネイティブ画像を記録しました。これらは build 39 の実機証拠ではありません。iPad Air での受け入れは保留中です。この表示は Open-Meteo への実接続を証明しません。以前の端末リクエストは TLS error `-1202` となり、証明書の信頼設定は変更していません。

Open-Meteo の現行[利用条件](https://open-meteo.com/en/terms)では、無料の hosted API は非商用利用向けで、CC BY 4.0 のデータ条件への同意が必要とされています。[ライセンスページ](https://open-meteo.com/en/licence)では適切なクレジット表示、ライセンスへのリンク、変更内容の明記が求められます。商用 hosted API には別の契約条件があります。プロバイダー条件は Wizard のアプリライセンスとは別です。ソース候補は、将来の配布が特定の接続先や利用条件に適合することを証明せず、法的許可も主張しません。稼働中の天気サービスを有効にする・配布する前に、プロバイダー条件を再確認して必要な許可を取得してください。条件とライセンスの確認日: 2026年11月12日。

## Rockstar Games GTA VI メディア

GTA VI と表示されるすべての画像・動画と、切り抜き、形式変換、切り出しなどの派生素材は Rockstar Games と該当する権利者に帰属します。この包括的な帰属記録は、素材が Rockstar の公式サイトから公開ダウンロードされたというプロジェクト所有者の説明を記録しています。公式 [Artwork & Wallpapers](https://www.rockstargames.com/VI/media/artwork-wallpapers)、[GTA VI media](https://www.rockstargames.com/VI/media)、[videos](https://www.rockstargames.com/VI/media/videos) ページは [GTA6-MATERIALS.md](GTA6-MATERIALS.md) にリンクされています。公開ダウンロードによって MIT 権利が付与されたり、このプロジェクトでの再配布が許可されたりするわけではありません。

Rockstar の[法的条件](https://www.rockstargames.com/legal/)と[著作権コンテンツ掲載ポリシー](https://support.rockstargames.com/articles/7bNaeoMFTV0iUDGhStTXvz/policy-on-posting-copyrighted-rockstar-games-material)を確認してください。帰属表示は再配布許可でも公式推奨でもありません。ここでは法的許可を主張しません。

任意ギャラリーパッケージには画像228枚、保持した GTA VI trailer 2本とそのサムネイルが含まれます。全 artwork と原本は別の Release ドラフトメディアパックです。正確な一覧と出所確認の限界は [GTA6-MATERIALS.md](GTA6-MATERIALS.md) と[メディア manifest](../../assets/media/MANIFEST.json)を参照してください。原素材パック内の SRT 2本は作者が独立確認されておらず、Rockstar 公式字幕とは主張しません。ユーザー取り込み素材は Rockstar 帰属の対象外です。

## Anton ディスプレイフォント

変更されていない静的 `App/Resources/Anton-Regular.ttf` は Copyright 2020 The Anton Project Authors で、[App/Resources/Anton-OFL.txt](../../App/Resources/Anton-OFL.txt) に含まれる SIL Open Font License 1.1 で配布されます。出典: 固定 revision `cee74d7ca45d66d5c1878c828645c862f2788d2d` の [Google Fonts](https://github.com/google/fonts/tree/cee74d7ca45d66d5c1878c828645c862f2788d2d/ofl/anton)。SHA256: `a4ba3a92350ebb031da0cb47630ac49eb265082ca1bc0450442f4a83ab947cab`。Font とライセンスは App に同梱され、MIT ソースライセンスとは別です。README のディスプレイ文字にも同じ書体を使う場合があります。

## Noto CJK の宣伝用文字

README の宣伝用文字は言語別に Noto Sans CJK SC、TC、JP の Regular／Bold を使って輪郭化します。簡体字中国語には SC、繁体字中国語には TC、日本語には JP を使います。これらのフォントは任意のアート生成入力で、アプリには同梱されません。アプリ画面内の日本語・中国語は、各端末のシステムフォントで表示します。上流の[ライセンス](../../licenses/NotoSansCJK-OFL.txt)、固定ソース revision、入力 checksum、生成手順は[README アート出典](../../assets/readme/SOURCES.md)に記録されています。

## 同梱ディスプレイフォントとプロモーション画像

確認済みの `App/Resources/ViceCity.jpg` は代替壁紙として含まれ、選定された提供画像は README アートとネイティブキャプチャに使われています。元ファイル名と checksum は[素材帰属記録](../../assets/media/ATTRIBUTION.md)にあります。これらの画像と派生物の著作権は Rockstar Games と該当する権利者に帰属し、MIT ライセンス対象外です。フルメディアパックは Release 添付として別管理です。Rockstar 独自 font は同梱されません。
