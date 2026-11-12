[简体中文](../zh-CN/DEVELOPMENT.md) · [繁體中文](../zh-TW/DEVELOPMENT.md) · [English](../open-source/README.md) · **日本語**

# Wizard ソースと貢献ガイド

このリポジトリには、旧世代 iPad 向けのネイティブ Objective-C/UIKit アプリ Wizard、ホスト回帰検査、パッケージ／インストールツール、任意の電源 tweak が含まれます。アプリ本体と tweak は別コンポーネントです。

現在のソース候補は **0.2.0 / build 20261112.41** で、ソースと Simulator のビルドは通過しています。ソース／リソース指紋は `cdcbce40e799e4277d318953b1e2cf057cbfb116f70a9c1e5228f6afaee05e91`です。ビルド41は実機にインストールされていません。ソースリポジトリは公開されていますが、GitHub Releases はすべて下書き状態です。素材の manifest に記録された添付ファイルも、一般公開されているとは限りません。

Wizard が作成したコードにはルートの [MIT License](../../LICENSE) が適用されます。第三者のアート、フォント、ユーザー取り込み画像、その他の素材には適用されません。[第三者素材の説明](THIRD_PARTY.md)と[GTA VI 素材ガイド](GTA6-MATERIALS.md)を参照してください。

<a id="build"></a>

## ビルド

macOS、Apple Clang、Xcode command-line tools、Apple の開発ツールから取得した iPhoneOS SDK でビルドします。SDK はリポジトリにもソースの書き出し物にも含まれません。

```sh
IOS_SDK="/path/to/iPhoneOS9.3.sdk" ./scripts/build-ipad.sh
```

確認済み SDK は iPhoneOS 9.3 です。スクリプトは最小対応 OS を iOS 9.0 とする `armv7`／`arm64` 用の**未署名** `WizardSystem.app` を作成します。これらはビルド対象の設定であり、すべての iOS 9〜12 端末で動作する証拠ではありません。新しい SDK によるビルド、特に旧 `armv7` と MediaPlayer の動作は未検証です。

ビルドはコンパイラと SDK の詳細、コンパイルコマンドのひな形、ソース入力のハッシュ、アプリの plist に記録する統合指紋、出力ハッシュ、アーキテクチャ、警告を `BUILD-METADATA.txt` に記録します。コンパイル中に、許可リストにあるソースとリソースが変わっていないことを確認します。`nm -u -j` で未定義 シンボル を調べ、検査エラーや解決されない アプリ固有の `IW` シンボル があれば停止します。非公開システムシンボル用の旧 リンカーオプション `dynamic_lookup` は残っています。ホストビルドの成功は、実機でシンボルの存在や動作を証明しません。スクリプトは署名もインストールもしません。

過去の build `20261112.39` では、ビルドスクリプトがリンクした `CoreText` がメタデータのフレームワーク一覧から漏れていました。テンプレートは修正済みです。この記載漏れによって、当時のアプリのソース指紋、パッケージ、同梱フォントが変わったわけではありません。

既定では `.private-audit` 内に新しい出力フォルダーを作ります。出力先は `--out PATH` で指定します。指定先は事前に存在していてはいけません。スクリプトは既存の出力を消去しません。ビルドには確認済みのアプリアイコンと起動画像、帰属表示付き `ViceCity.jpg` の代替壁紙、静的 OFL ライセンスの `Anton-Regular.ttf` とライセンスが含まれます。そのためアプリには第三者素材も含まれます。コンパイルに別の GTA VI 素材パックやプロプライエタリフォントは不要です。Rockstar アートは MIT ライセンス対象外です。[素材ガイド](GTA6-MATERIALS.md)を参照してください。

ビルド41 では時計編集パネルに「ポスター／標準」の2択を追加します。既定の「ポスター」は同梱 Anton、「標準」はシステムフォントです。「Done」で保存し、「Cancel」で変更前に戻します。ソースと Simulator のビルドは通過しましたが、古い物理 iPad での描画は未確認です。

## ホスト側の検査

CI は GitHub の `macos-15` 実行環境で動きます。リポジトリのルートから実行する同一の検査:

```sh
python3 scripts/check-repository.py
python3 tests/repository-regressions.py
python3 tests/package-regressions.py
/bin/sh -n scripts/install-wizard.sh
bash -n scripts/build-ipad.sh scripts/build-power.sh
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

最後の8コマンドはホスト上のソース回帰スイートです。先行するコマンドは追跡対象ファイル、リポジトリ検査ツールの回帰、パッケージとインストーラーのテスト用データ、shell 構文を確認します。スイートはテスト用データ、抽出した本番メソッド、UI の代替オブジェクトを使います。CI は端末向け アプリをビルドせず、Apple SDK を取得・再配布しません。署名、インストール、ネイティブ表示、実機上での非公開 API 解決を確認せず、実機での受け入れに代わるものではありません。

<a id="native-simulator-preview"></a>

## Simulator のネイティブプレビュー

プレビューは、Xcode とともにインストール済みの Simulator SDK 用にビルドする別の iPad App です。

```sh
python3 scripts/build-preview.py --out build-preview
```

スクリプトは識別子 `com.rex.wizard.preview`、iOS 18 以降を対象とする ad-hoc 署名済み `WizardPreview.app` を作り、`PREVIEW-METADATA.json` にソース／リソース指紋を記録します。アプリをインストールしたり、Simulator を起動したりはしません。プレビュー用メディアはアプリのコンテナ内の `Documents/WizardMedia` にあります。端末版は引き続き `/var/mobile/Media/iPadWizard/app` を使います。

専用の Simulator を選び、ネイティブ UIKit 表示を確認してキャプチャを作成します。[キャプチャ出典](CAPTURES.md)の8枚の `*-miami.jpg` は、iOS 18 の iPad（第8世代）Simulator で ビルド41 を動かして撮影したものです。[時計編集画面で「標準」を選んだ画像](../../assets/demo/clock-font-system.jpg)も、実際のアプリ画面をそのまま撮影しています。そこにある `*-ipad2.png` 3枚は build `20261111.36` の古い実機画像で、現行候補を示しません。どちらの画像も古い iOS との互換性を証明しません。[互換性](COMPATIBILITY.md)に証拠一覧があります。

プレビューは `WizardPreviewCommands` から許可された画面遷移コマンドを最大8つ受け取ります。例:

```sh
xcrun simctl launch --terminate-running-process SIMULATOR_UDID com.rex.wizard.preview \
  -WizardPreviewCommands "main,settingsmenu"
xcrun simctl io SIMULATOR_UDID screenshot settings.png
```

キャプチャ前に、指定した各画面遷移の完了を待ちます。例: `main,menu`、`main,themesmenu`、`main,gallery,gallerycategories`、`main,clockedit`。この Simulator 専用の起動方法は実際の App 操作を呼び出し、外部 URL の確認ダイアログを避けます。端末版を変更せず、実機インストールを許可するものでもありません。

## 実行時とインストールの境界

アプリは通常のアプリコンテナ外にあるメディアと設定パスを前提とします。`App/main.m` はメディアと状態に `/var/mobile/Media/iPadWizard/app`、電源設定に `/var/mobile/Library/Preferences` を使います。Apple 非公開の BackBoardServices、GraphicsServices、SpringBoardServices フレームワークのシンボルを動的に解決します。

この旧式の構成はソースから読み取れるもので、plist による許可ではありません。新規インストールと通常の iOS 端末への直接導入は未検証です。端末作業の前に[端末設定と実行時ファイル](INSTALL.md)で限定された準備済み端末の更新範囲と前提条件を確認してください。コンパイル、ホストテスト、Simulator キャプチャの成功は、インストールや実機受け入れではありません。

別コンポーネントの `App/WizardPowerTweak/` は Apple 非公開の SpringBoard API を使い、ロック、起動、表示動作を変える場合があります。`scripts/build-power.sh` は `armv7` と `arm64` 向けにビルドしますが、署名、インストール、実行時互換性の確認はしません。コア アプリのインストーラーは tweak を入れません。[コンポーネントガイド](../../App/WizardPowerTweak/README.md)を参照してください。

## プライバシーとサービス連携

ビルドや配布の前に[プライバシーとネットワーク動作](PRIVACY.md)を読んでください。アプリは利用者が選んだ写真を取り込み、ローカルネットワークのメディア制御サービスを公開し、指定 URL を再生できます。`App/Info.plist` では `NSAllowsArbitraryLoads=true` です。この設定はセキュリティレビューでも、すべてのネットワーク経路が動くという保証でもありません。

天気カードにはプロバイダー帰属表示の操作があります。合成テストデータを使ったネイティブ検査は実際のプロバイダーとの互換性を証明しません。Open-Meteo との通信と法的な許可は未検証です。連携内容を変更・説明する前に[第三者の条件](THIRD_PARTY.md)を確認してください。

## ローカルソースの書き出し準備

元のワークスペースから実行します。

```sh
python3 scripts/prepare-open-source.py
```

`--out PATH` で、まだ存在しない出力先を選べます。書き出しツールは確認済みの許可リストをコピーし、`OPEN_SOURCE_EXPORT_REPORT.json` を作成して、一般的な作業用パスや認証情報のパターンを検査します。この検査だけでプライバシーやセキュリティを完全に確認できるわけではありません。Git の初期化、ネットワークアクセス、署名、インストール、公開は行いません。iPhoneOS SDK、端末の非公開情報、認証情報、ユーザー写真はソースの書き出しに含まれません。

## ライセンスと帰属

Wizard 作成コードにはルートの MIT License が適用されます。Google Material のパスデータにはルート `NOTICE` 内の Apache 2.0 表示が別途適用されます。同梱ディスプレイフォントと SIL OFL 1.1 ライセンスは `App/Resources` に別ファイルで含まれます。GTA VI の画像、動画、スクリーンショット、派生素材は Rockstar Games および該当する権利者の所有物で、MIT ライセンス対象外です。[GTA VI 素材ガイド](GTA6-MATERIALS.md)、[キャプチャ出典](CAPTURES.md)、[第三者素材の説明](THIRD_PARTY.md)を参照してください。
