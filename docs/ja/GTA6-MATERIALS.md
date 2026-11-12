[简体中文](../open-source/GTA6-MATERIALS.md) · [繁體中文](../zh-TW/GTA6-MATERIALS.md) · [English](../en/GTA6-MATERIALS.md) · **日本語**

# GTA VI 素材: 出典と権利

GTA VI の画像、動画、スクリーンショット、サムネイル、トランスコード、切り抜きの著作権は **Rockstar Games および該当する権利者**に帰属します。これらの素材は Wizard 作成コードと分けて管理し、プロジェクトの MIT License では許諾されません。本プロジェクトは Rockstar Games と提携・協賛・公認関係にありません。

## 配布状況とメディアパック

2026-11-12 の確認時点で GitHub リポジトリは非公開で、GitHub Releases はすべてドラフトでした。以下のメディアパックはドラフトの `v0.2.0-preview.5`に記録され、公開ダウンロードできません。manifest の `download_url` はドラフト用 URL であり、一般に取得できるリンクではありません。

| メディアパック | manifest に記録された内容 | 用途 |
| --- | --- | --- |
| `wizard-gta6-gallery-20261112.zip` | 464 files: ギャラリーカタログ230項目、横長画像228枚、MP4 trailer 2本、サムネイル230枚、メディア参照460件。 | Wizard の任意ギャラリー。 |
| `gta6-original-materials-20261112.zip` | 350 files: 原本 JPEG 343枚、MKV 動画2本、SRT 字幕2本、補助パッケージファイル。 | 原素材の保管と後続作業の参考。 |

[メディア manifest](../../assets/media/MANIFEST.json)にはバイトサイズ、SHA-256、パッケージ内容が記録されています。各アーカイブにはファイル別 manifest、著作権帰属、利用上の注意が含まれます。原ファイル名を保持し、App のギャラリーではカテゴリ、短い表示名、安定キーを別々に管理します。SRT 2本の作者は独立検証されていないため、Rockstar 公式字幕とは表記しません。

ソース確認、ファイル名の一致、カテゴリ記録は、全ファイルの byte 単位の出所を証明せず、再配布権も与えません。各ファイルには該当する権利が適用されます。

## Rockstar 公式ソース

プロジェクト所有者は、Rockstar の公開メディア／ダウンロードページから素材を集めました。

- [GTA VI Artwork & Wallpapers](https://www.rockstargames.com/VI/media/artwork-wallpapers)
- [GTA VI Media](https://www.rockstargames.com/VI/media)
- [GTA VI Videos](https://www.rockstargames.com/VI/media/videos)
- [Rockstar Games Legal Terms](https://www.rockstargames.com/legal/)

プロジェクトのソース記録には、壁紙構図27種とサイズ／ロゴ違い142種、ゲーム画面138枚、Ultimate Edition 画像51枚、Vintage Vice City Pack 画像12枚が含まれます。ギャラリーには各壁紙構図の横長画像を1枚ずつ選び、ゲーム画面とコンテンツパック画像はすべて保持します。Rockstar のページは更新される場合があります。ここに記載した正確な範囲は[メディア manifest](../../assets/media/MANIFEST.json)と各アーカイブのファイル別 manifest で定まります。

## リポジトリ内デモとライセンス範囲

リポジトリの[デモ出典ガイド](CAPTURES.md)には、同梱 App キャプチャの出典を記載しています。現行の8枚の `*-miami.jpg` と `clock-font-system.jpg` は、iOS 18 の iPad（第8世代）Simulator で build `20261112.41` を動かして撮影したネイティブ画像です。`*-ipad2.png` は build `20261111.36` の過去の実機スクリーンショットです。キャプチャ内の GTA VI 画像は引き続き Rockstar Games および該当する権利者の所有物で、Wizard の MIT コードライセンス対象外です。

メディアパックからはユーザー写真、設定、端末バックアップ、接続情報、F1 動画、過去のゲーム音声、フォント、Apple SDK を除外しています。インストールと実行条件は[インストールガイド](INSTALL.md)、統合帰属記録は[ATTRIBUTION.md](../../assets/media/ATTRIBUTION.md)を参照してください。

## App の代替画像とプロモーションアート

現在の build 20261112.41 には `ULTIMATE_EDITION_VICE_CITY_STYLE_01.jpg` 由来の `App/Resources/ViceCity.jpg` が含まれます。リポジトリ内コピーは原本と byte 単位で同一です: 3840 × 2160 pixel、SHA-256 `c255874fee509eae0baa6f546861e483ec0b32efbfe8d013ec36888013d923c9`。App は外部ギャラリーカタログがない場合の代替表示画像としてのみ使用します。README のプロモーションアートとネイティブキャプチャにも帰属表示付き Rockstar 素材が含まれます。これらの画像と派生物は MIT ライセンス対象外です。App には別途 SIL OFL フォントが含まれます。Rockstar のフォントファイルは配布していません。

## 関連記録

- [メディア manifest と checksum](../../assets/media/MANIFEST.json)
- [素材の統合帰属記録](../../assets/media/ATTRIBUTION.md)
- [デモキャプチャの出典と metadata](CAPTURES.md)
- [第三者ライセンスとサービス条件](THIRD_PARTY.md)
