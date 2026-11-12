[简体中文](../zh-CN/CONTRIBUTING.md) · [繁體中文](../zh-TW/CONTRIBUTING.md) · [English](../../CONTRIBUTING.md) · **日本語**

# 貢献ガイド

Wizard の改善にご協力いただきありがとうございます。変更を提案する前に、[互換性ガイド](COMPATIBILITY.md)、[プライバシーの説明](PRIVACY.md)、[第三者素材の注意事項](THIRD_PARTY.md)を確認してください。

## 問題を報告する

GitHub の不具合報告フォームまたは機能要望フォームを使ってください。不具合の場合は Wizard の version／build、iPad の機種、iOS のバージョン、インストール環境、再現手順を記載してください。ログやスクリーンショットからユーザー名、ホームパス、ネットワークアドレス、認証情報、シリアル番号、UDID、非公開のインストール詳細、個人メディアを削除してください。

## 変更を準備する

変更範囲を絞り、ホスト上で動作を検証できる場合は回帰検査を含めます。UI 変更では、ソースやビルドの証拠とは分けて、検査した機種と OS を明記してください。ホスト回帰検査やコンパイル成功を実機受け入れとして説明しないでください。

App のビルドには Apple iPhoneOS SDK が必要ですが、リポジトリには含まれません。SDK、署名素材、インストーラー、端末記録、取り込み写真、出所と配布権を記録していないメディアを追加しないでください。Wizard 作成コードには MIT が適用されます。第三者素材とコードにはそれぞれの条件が適用されます。

## 検査を実行する

ホストスイートには macOS、Apple Clang、Python 3 が必要です。リポジトリのルート から実行します。

```sh
python3 scripts/check-repository.py
python3 tests/repository-regressions.py
python3 tests/package-regressions.py
python3 tests/native-regressions.py
./App/tests/run-http-transport-regressions.sh
./App/tests/run-weather-service-regressions.sh
python3 App/tests/cast-lifecycle-regressions.py
python3 App/tests/media-lifecycle-regressions.py
python3 App/tests/gallery-media-regressions.py
python3 App/tests/menu-layout-regressions.py
python3 App/tests/power-edge-regressions.py
```

これらの検査はホスト上のテスト用データと代替オブジェクトを使って、ソースの動作を確認します。アプリをインストールせず、ネイティブ描画、Apple 非公開システムシンボル、署名、通常の iOS 端末、新規インストールも検証しません。任意の 複数アーキテクチャ向けの端末用ビルド は[ビルドガイド](../open-source/README.md#build)に記載されています。Apple の開発ツールから取得した iPhoneOS SDK が必要です。

## Pull request

Pull request のテンプレート を使い、利用者に見える変更を要約し、実行した検査を列挙して、ソース／ビルド証拠と実機証拠を分けてください。第三者素材を追加する場合は、追加前に帰属表示とライセンス記録を更新してください。検証済み証拠を超える製品の主張、互換性の約束、変更履歴を書かないでください。
