[简体中文](../../assets/demo/README.md) · [繁體中文](../zh-TW/CAPTURES.md) · [English](../../assets/demo/README.en.md) · **日本語**

# デモキャプチャの出典

## 現行の Miami プレビュー

`*-miami.jpg` は、iOS 18.0 の **iPad（第8世代）Simulator** で build **20261112.41** を実行し、UIKit から直接取得した画像です。元の PNG は 2160×1620 ピクセルです。Web 用 JPEG も同じ寸法で、画質85で保存されています。アプリの操作画面を重ねたり、追加で描画したりしていません。PNG と JPEG のハッシュ、画面遷移コマンド、ソース指紋は [CAPTURE-METADATA.json](../../assets/demo/CAPTURE-METADATA.json) にあります。

- [ホーム](../../assets/demo/home-miami.jpg): 外部カタログがない状態で、同梱 Vice City 画像を表示。
- [ギャラリー](../../assets/demo/gallery-miami.jpg)と[カテゴリ](../../assets/demo/categories-miami.jpg): メディアパックの230項目と代替画像を含むデモ用カタログ、計231項目。ユーザー写真は含みません。
- [メインメニュー](../../assets/demo/menu-miami.jpg)、[設定](../../assets/demo/settings-miami.jpg)、[テーマ](../../assets/demo/themes-miami.jpg)。
- [時計編集](../../assets/demo/clock-edit-miami.jpg)と[カレンダー](../../assets/demo/calendar-miami.jpg)。

これらの画像と `armv7 + arm64` 対応ビルドは、ソース／リソース指紋 `cdcbce40e799e4277d318953b1e2cf057cbfb116f70a9c1e5228f6afaee05e91` を共有しています。Simulator 版は端末版とは別のアプリ識別子と、サンドボックス内のメディア保存先を使います。再現方法は[ネイティブ Simulator プレビュー](DEVELOPMENT.md#native-simulator-preview)を参照してください。Simulator の表示は旧世代 iPad の実機動作を証明しません。各言語の README は実際のアプリ画像を使い、画面内の中国語と英語の表示をそのまま残しています。

## 時計フォントのキャプチャ

build 41 には静的 `Anton-Regular.ttf` と OFL 1.1 ライセンスが同梱されています。時計編集画面の[「標準」フォントのキャプチャ](../../assets/demo/clock-font-system.jpg)は、システムフォントを選んだ状態を示す実際の Simulator 画像です。`*-miami.jpg` のホーム、メニュー、時計編集画像では、既定の「ポスター」フォントが使われています。キャプチャのメタデータには、実際に使われたフォント名とフォントファイルの SHA256、アプリ同梱フォントかどうかが記録されています。「標準」ではシステムフォント `.SFUI-Bold` が使われ、アプリには同梱されません。日本語や中国語などの表示にはシステムフォントを使います。build 41 はソースと Simulator のビルドを通過していますが、実機受け入れはありません。

## 過去の実機画像

以下の build 36 の PNG は、2026-11-11 に iPad2,4 / iOS 9.3.5 で撮影した実機画像です。画素は撮影時のまま保持しています。

- [過去のホーム画面](../../assets/demo/home-ipad2.png)
- [過去のギャラリー](../../assets/demo/gallery-ipad2.png)
- [過去のカテゴリ](../../assets/demo/categories-ipad2.png)

これらは過去の build を記録したもので、現行 build 41 の実機受け入れを証明しません。

## 権利

これらの画像内の GTA VI 素材は Rockstar Games および該当する権利者に帰属します。Wizard の MIT コードライセンス対象外です。[素材帰属記録](../../assets/media/ATTRIBUTION.md)を参照してください。
