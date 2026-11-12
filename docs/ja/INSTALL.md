[简体中文](../INSTALL.md) · [繁體中文](../zh-TW/INSTALL.md) · [English](../en/INSTALL.md) · **日本語**

# Wizard のインストール

このガイドでは、Wizard 0.2.0 / build `20261112.41` の候補パッケージ、ソースからのビルド、任意のギャラリー、ロールバックを説明します。パッケージは、準備済みの rootful 脱獄 iPad だけを対象とします。脱獄の導入、電源 tweak のインストール、証明書・ネットワーク・システムの信頼設定の変更、アプリの自動起動は行いません。build 41 は実機で受け入れられていません。

## ダウンロード状況

ソースリポジトリは公開されていますが、GitHub Releases はすべて下書き状態です。`v0.2.0-preview.5` は未公開の下書きのため、現在使える公開 `releases/download/...` URL はありません。許可されたメンテナーは[リリースページ](https://github.com/rexchen1803/wizard/releases)で下書きを確認できます。このページはメンテナー用の入口で、公開ダウンロード先ではありません。また、添付ファイルを取得できる保証もありません。必要な添付ファイルを取得できなければ中止してください。リリースの公開、リポジトリの公開設定変更、`latest` への置き換えはしないでください。リポジトリを公開しても、下書きのリリースや添付ファイルは公開されません。

公開後に使う build 41 の固定ファイル名と URL は次のとおりです。リリースは下書きのため、URL は現在利用できません。

| ファイル | 固定ファイル名 | 公開後の固定 URL（現在は利用不可） |
| --- | --- | --- |
| Wizard の Debian パッケージ | `wizard_0.2.0-20261112.41_iphoneos-arm.deb` | `https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.5/wizard_0.2.0-20261112.41_iphoneos-arm.deb` |
| パッケージ manifest | `wizard_0.2.0-20261112.41_iphoneos-arm.deb.manifest.json` | `https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.5/wizard_0.2.0-20261112.41_iphoneos-arm.deb.manifest.json` |

確定した `.deb` と対応 manifest の両方を、許可された取得元から入手できるまでは進めないでください。`.deb` の SHA-256 を manifest の `artifact_sha256` と照合します。macOS では次のとおり確認します。

```sh
shasum -a 256 wizard_0.2.0-20261112.41_iphoneos-arm.deb
```

バージョン、ファイル名、ハッシュが一致しない場合は中止し、異なる Release のパッケージと manifest を組み合わせないでください。パッケージ作成スクリプトは出力ごとに manifest と成果物ハッシュを作ります。

## 対象機器と前提条件

インストーラーが受け付けるモデルと iOS の組み合わせは次のとおりです。

| 機器 | モデル識別子 | iOS |
| --- | --- | --- |
| iPad 2 | `iPad2,4` | `9.3.5` |
| iPad 4 | `iPad3,4` | `10.3.3` |
| iPad Air | `iPad4,1` | `12.5.8` |

さらに rootful 脱獄、root 権限、シンボリックリンクではない書き込み可能な `/Applications`、Debian パッケージ環境、および `ldid`、`uicache`、`killall`、`sysctl`、`sw_vers` が必要です。`uicache` は登録用 `-p` と登録解除用 `-u` の両方に対応している必要があります。通常の iOS、rootless 脱獄、iPhone、一覧にない機種や OS は拒否されます。報告された機種名や OS を書き換えてチェックを回避しないでください。

パッケージ構造の検査とインストーラーのローカルテスト用データによる検査は、実機へのインストール、署名、登録、起動を証明しません。特定の準備済み端末での過去の証拠は[互換性表](COMPATIBILITY.md)に記載されていますが、build 41 のインストールを証明するものではありません。

## プレビューパッケージのインストール

固定されたファイルを許可済みの取得元から入手し、ハッシュを確認してから進んでください。

1. `wizard_0.2.0-20261112.41_iphoneos-arm.deb` と `wizard_0.2.0-20261112.41_iphoneos-arm.deb.manifest.json` を取得します。上記の URL はリリースが未公開のため現在利用できません。[リリースページ](https://github.com/rexchen1803/wizard/releases)で下書きの添付ファイルを確認できるのは、許可されたメンテナーに限られます。添付を取得できなければ中止してください。
2. その `.deb` の `artifact_sha256` を対応 manifest と照合します。`latest`、別 Release、名前を変更したパッケージは使わないでください。
3. 許可された対象 iPad で Filza、または Cydia、Sileo、Zebra が対応するローカル `.deb` 手順を使います。すでに許可された端末 root ターミナルから実行する場合:

   ```sh
   dpkg -i ./wizard_0.2.0-20261112.41_iphoneos-arm.deb
   ```

パッケージの処理は、機種、OS、rootful 環境、パッケージ管理環境、必要なツール、アプリのパスを最初に確認します。インストーラーは端末に既存の `ldid` で未署名アプリに ad-hoc 署名を行い、`uicache` で登録します。更新時は Wizard に `TERM` を1回送り、候補を配置する前に既存アプリ全体を `WizardSystem.rollback-<build>-<UTC>.app` として保持します。新規インストールには保持対象の旧アプリはありません。Wizard の起動、端末再起動、respring は行いません。

パッケージは `/var/mobile/Media/iPadWizard/app`、Wizard の設定、既存の rollback バンドルを置き換えません。署名、ファイル配置、登録に失敗した場合、失敗した処理分岐に応じて候補、旧アプリ、復旧ディレクトリを復元または保持します。エラー状態をそのまま保ち、元のエラーを報告してください。respring の強制、復旧ディレクトリの削除、ユーザーデータの整理は行わないでください。インストール成功はインストーラーの完了を意味するだけです。利用者が Wizard を手動で起動し、別途受け入れを判断します。

## ソースからビルド

ソースリポジトリは公開されており、サインインせずに HTTPS で clone できます。ソースビルドには macOS、Apple Clang、Apple の開発ツールから取得した iPhoneOS SDK が必要です。Apple SDK はこのリポジトリに含まれません。確認済み SDK は iPhoneOS 9.3 です。新しい SDK と armv7、旧 MediaPlayer の互換性は未検証です。

```sh
git clone https://github.com/rexchen1803/wizard.git
cd wizard
IOS_SDK="/path/to/iPhoneOS9.3.sdk" ./scripts/build-ipad.sh --out /tmp/WizardSystem-build
python3 scripts/package-release.py \
  --app /tmp/WizardSystem-build/WizardSystem.app \
  --out /tmp/wizard_0.2.0-20261112.41_iphoneos-arm.deb
```

出力先の App ディレクトリ、`.deb`、隣接する manifest は、まだ存在していてはいけません。パッケージ作成ツールはアプリのバージョンと build に合うファイル名を要求し、`armv7` と `arm64`、bundle ID、リソース、ソース fingerprint を検査して、新たに生成する manifest に `artifact_sha256` を書き込みます。`--dry-run` はパッケージを書き込まず、構造とハッシュを表示します。ビルドとパッケージ作成は端末に接続せず、インストールもしません。[ビルドと回帰検査ガイド](DEVELOPMENT.md#build)にソース検証の限界があります。[WizardPower のソース説明](../../App/WizardPowerTweak/README.md)には別のビルド入口があります。Wizard パッケージは tweak をインストールしません。

## 任意の GTA VI ギャラリー

ギャラリーと原素材パッケージも未公開 Release のドラフト添付です。現在利用できる公開ダウンロード URL はありません。メンテナーまたは許可された利用者が正確なドラフト添付を取得できる場合だけ使用し、取得できなければ中止してください。Release の公開やリポジトリの公開設定変更はしないでください。

| ファイル | 内容 | サイズ | SHA-256 |
| --- | --- | ---: | --- |
| `wizard-gta6-gallery-20261112.zip` | カタログ230項目、画像228枚、動画2本とサムネイル | 258,253,713 bytes | `b8bd883b81a0a76086217ce3c27091d83b0b8261dcbabae49c88abb67aef3eba` |
| `gta6-original-materials-20261112.zip` | 原本 JPEG 343枚、MKV 2本、SRT 2本 | 755,809,316 bytes | `182cb83aaf463dc22004f750a4e51a2419ef50eb2da851aba9c6d456d89aea0b` |

[ローカル manifest](../../assets/media/MANIFEST.json)には、これらのファイルの期待サイズと SHA-256 が記録されています。公開後の固定パスは以下ですが、現時点で利用できません。リポジトリの公開と、下書きの添付ファイルの公開は別です。

```text
https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.5/wizard-gta6-gallery-20261112.zip
https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.5/gta6-original-materials-20261112.zip
```

アプリのギャラリーを導入する場合は、別途選択して許可してください。最初に `/var/mobile/Media/iPadWizard/app` 全体の完全なバックアップを作成し、ZIP 内の `app/` の内容をそのディレクトリにマージします。既存の `assets/user` と設定を保持し、`app` 全体を削除・置換しないでください。転送ツールが権限を変更した場合は、新しくコピーしたファイルだけを調整します。既存のユーザーディレクトリを再帰的に変更しないでください。Wizard を再度開き、元の壁紙、お気に入り、切り抜き、取り込み写真、カテゴリを確認します。原素材アーカイブは素材収集・制作向けで、端末用ギャラリーパッケージではありません。[素材ガイド](GTA6-MATERIALS.md)と[帰属記録](../../assets/media/ATTRIBUTION.md)を参照してください。Rockstar 素材は Wizard の MIT コードライセンスの対象外です。

## ロールバックと削除

更新後は、インストーラーが表示した正確な rollback ディレクトリを記録します。端末の許可済み root ターミナルで、例の記号を実際の正確なパスに置き換えてください。

```sh
/usr/lib/wizard-installer/install-wizard.sh rollback "/Applications/WizardSystem.rollback-<build>-<UTC>.app"
```

ロールバックでは、現在の候補を `WizardSystem.failed-rollback-<UTC>.app` として保持し、選択した `WizardSystem.rollback-*` または `WizardSystem.uninstalled-*` バンドルを復元して再登録します。アプリを起動せず、SpringBoard も再起動しません。失敗した場合はすべてのディレクトリを保持し、エラーを報告してください。削除または上書きするディレクトリを推測しないでください。

タスクでアンインストールが明示的に要求された場合に限り、Debian パッケージを削除します。パッケージマネージャーを使うか、端末の許可済み root ターミナルで次を実行します。

```sh
dpkg -r com.rex.wizardsystem
```

削除フックは、パッケージと build が一致する Wizard アプリだけを登録解除し、完全なバンドルを `WizardSystem.uninstalled-<build>-<UTC>.app` として保持します。インストール済みアプリの build が異なる場合はそのアプリを保持しますが、パッケージマネージャーがこのパッケージと補助ツールを削除することはあります。メディア、設定、既存 rollback バンドルは消去しません。保存済みアプリを復元するには、同じ固定 `.deb` を再インストールして補助ツールを戻し、実在する `WizardSystem.uninstalled-*` パスを `rollback` に渡します。個人メディアや設定の消去は別の操作であり、通常の削除には含まれません。

App バンドルには帰属表示のある Vice City の既定壁紙が含まれています。外部ギャラリーがなくても表示できます。ギャラリー全体の導入は任意です。
