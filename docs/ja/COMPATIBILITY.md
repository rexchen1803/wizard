[简体中文](../zh-CN/COMPATIBILITY.md) · [繁體中文](../zh-TW/COMPATIBILITY.md) · [English](../COMPATIBILITY.md) · **日本語**

# 互換性と検証状況

このガイドでは、ソース／ビルドの確認、ホスト検査、Simulator の画像、実機操作を区別します。2026-11-12 時点の **Wizard 0.2.0 / build 20261112.41 候補**を説明します。ソースと Simulator のビルドは通過しています。build 41 は物理 iPad にインストールされておらず、実機受け入れもありません。現行候補の App のソース／リソース指紋は `cdcbce40e799e4277d318953b1e2cf057cbfb116f70a9c1e5228f6afaee05e91`です。

## 環境ごとの証拠

| 環境 | 確認済みの証拠 | 証明しないこと |
| --- | --- | --- |
| 端末向けビルド | App の最小対応 OS は iOS 9.0。build `20261112.41` は iPhoneOS 9.3 SDK で `armv7` と `arm64` 向けにビルドされた。 | 最小対応 OS の設定とコンパイル成功は、iOS 9〜12、より新しい iOS、または実機での動作を保証しない。 |
| iPad（第8世代）Simulator、iOS 18.0 | ビルド41候補の Simulator ビルドを確認。8枚の `*-miami.jpg` と「標準」フォント画像の計9枚は、ソース／リソース指紋 `cdcbce40e799e4277d318953b1e2cf057cbfb116f70a9c1e5228f6afaee05e91` で作成された UIKit のネイティブキャプチャ。 | Simulator の表示は、実機動作や iOS 9〜12 との互換性を証明しない。 |
| macOS ホストと CI | [`macos-15` workflow](https://github.com/rexchen1803/wizard/actions/workflows/ci.yml) は、リポジトリ検査、パッケージ検査、シェル構文検査、9つのホスト回帰スイートを実行する。 | CI は端末向け App をビルドしない。ホスト上の検査結果は、実機へのインストール、ネイティブ表示、署名、非公開システムシンボル、実機動作を証明しない。 |
| iPad 2、`iPad2,4`、iOS 9.3.5 | 以前の build `20261111.30` を準備済み端末に更新し、起動、メニュー、ギャラリー、設定保持、限定したモーション、カレンダー、編集画面、実機での写真選択・取り込みを記録。 | 以前の build を準備済み環境で確認した証拠。build 39/40、新規インストール、通常の iOS、アクセシビリティ、全操作をカバーしない。 |
| iPad 4、`iPad3,4`、iOS 10.3.3 | 以前の build `20261111.30` を準備済み端末に更新し、限定した画面、カレンダー、動画、メディア読み込みの動作を記録。 | 以前の build を準備済み環境で確認した証拠。build 39/40、新規インストール、通常の iOS、アクセシビリティ、日常利用全般をカバーしない。 |
| iPad Air、`iPad4,1`、iOS 12.5.8 | 以前の build `20261111.36` を、復旧済みの準備端末に更新し、限定した画面とメディア同期を確認。 | 以前の build を準備済み環境で確認した証拠。build 39/40、新規インストール、通常の iOS、全動画再生、アクセシビリティ、日常利用全般をカバーしない。 |
| 現行ビルドの実機 | build `20261112.41` を物理 iPad に入れた記録はない。 | 現行候補の実機受け入れは主張しない。 |
| 新規インストールまたは通常の iOS 環境 | 検証済みのインストール経路はない。既存のインストール証拠は、準備済みの rootful 環境または通常のアプリ用サンドボックス外に限られる。 | 通常の端末や初回設定での署名、登録、外部ストレージアクセス、Apple 非公開フレームワークの動作は未確認。 |

準備済み端末の範囲と前提条件は[端末設定と実行時ファイル](INSTALL.md)にあります。[デモキャプチャ記録](CAPTURES.md)の `home-ipad2.png`、`gallery-ipad2.png`、`categories-ipad2.png` は build `20261111.36` の過去の実機記録で、build 39/40 の画像ではありません。現行の `*-miami.jpg` と時計フォント画像は、iPad（第8世代）Simulator のキャプチャです。

## ビルドとホスト検査

端末向けビルドで確認済みの SDK は iPhoneOS 9.3 です。SDK は Apple の開発ツールから取得してください。ソースには含まれません。新しい SDK のビルドは、旧 MediaPlayer インターフェースと `armv7` を含め未検証です。[ソースビルドガイド](DEVELOPMENT.md#build)を参照してください。

CI の workflow は macOS ホスト上で実行されます。主なホスト回帰検査コマンドは次のとおりです。

```sh
python3 tests/native-regressions.py
./App/tests/run-http-transport-regressions.sh
./App/tests/run-weather-service-regressions.sh
python3 App/tests/cast-lifecycle-regressions.py
python3 App/tests/media-lifecycle-regressions.py
python3 App/tests/gallery-media-regressions.py
python3 App/tests/menu-layout-regressions.py
python3 App/tests/power-edge-regressions.py
python3 App/tests/security-regressions.py
```

これらの検査はソースの回帰を見つけるのに役立ちます。対象とする機種・OS ごとのインストール、起動、操作、メディア、アクセシビリティ、長時間動作の確認に代わるものではありません。

## 実行時の制約と任意コンポーネント

アプリ本体は通常のアプリコンテナ外にある `/var/mobile/Media/iPadWizard/app` と `/var/mobile/Library/Preferences` のメディア・設定ファイルを読みます。Apple 非公開の `BackBoardServices`、`GraphicsServices`、`SpringBoardServices` フレームワークからシンボルを動的に解決します。ホストビルドでは、対象端末でのシンボル解決や動作を確認できません。

任意の `WizardPower` tweak は別コンポーネントで、Apple 非公開の SpringBoard API を使います。ビルド、インストール、実行時の受け入れは個別に確認が必要です。[tweak ガイド](../../App/WizardPowerTweak/README.md)を参照してください。

iOS 18 Simulator で動画を確認した際、テーマ付きコントロールと進む再生時刻は見えましたが、キャプチャには動画の映像が表示されませんでした。同じ無音テスト動画から抽出したフレームは有効でした。原因は特定されず、実機再生も証明されていません。旧端末の再生経路はソースに残っていますが、iOS 9〜12 のすべての環境で再生できるとは限りません。

## 同梱フォントと切り替え

build `20261112.41` は、変更されていない静的 `Anton-Regular.ttf` と SIL OFL 1.1 ライセンスを端末版・Simulator 版 App に同梱しています。`UIAppFonts` がフォントを登録します。時計編集画面には「ポスター／標準」の2択があり、既定の「ポスター」は同梱 Anton、「標準」はシステムフォントを使います。`*-miami.jpg` は「ポスター」、[専用キャプチャ](../../assets/demo/clock-font-system.jpg)は「標準」の実際の Simulator 表示です。キャプチャのメタデータには、実際に使われたフォント名と App バンドル内のファイル由来が記録されています。これらの画像は実機での描画を証明しません。

## 関連資料

- [ソースビルドと貢献ガイド](DEVELOPMENT.md)
- [端末設定と実行時ファイル](INSTALL.md)
- [Simulator と過去のキャプチャ出典](CAPTURES.md)
- [第三者素材とライセンス](THIRD_PARTY.md)
