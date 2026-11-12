[简体中文](../../assets/demo/README.md) · [繁體中文](../zh-TW/CAPTURES.md) · [English](../../assets/demo/README.en.md) · **日本語**

# デモキャプチャの出典

## 現行の Miami プレビュー

`*-miami.jpg` は、iOS 18.0 の **iPad（第8世代）Simulator** で build **20261112.41** を実行し、UIKit から直接取得した画像です。元の PNG は 2160×1620 ピクセルです。Web 用 JPEG も同じ寸法で、画質85で保存されています。アプリの操作画面を重ねたり、追加で描画したりしていません。PNG と JPEG のハッシュ、画面遷移コマンド、ソース指紋は [CAPTURE-METADATA.json](../../assets/demo/CAPTURE-METADATA.json) にあります。

- [ホーム](../../assets/demo/home-miami.jpg): 外部カタログがない状態で、同梱 Vice City 画像を表示。
- [ギャラリー](../../assets/demo/gallery-miami.jpg)と[カテゴリ](../../assets/demo/categories-miami.jpg): メディアパックの230項目と代替画像を含むデモ用カタログ、計231項目。ユーザー写真は含みません。
- [メインメニュー](../../assets/demo/menu-miami.jpg)、[設定](../../assets/demo/settings-miami.jpg)、[テーマ](../../assets/demo/themes-miami.jpg)。
- [時計編集](../../assets/demo/clock-edit-miami.jpg)と[カレンダー](../../assets/demo/calendar-miami.jpg)。

これらの画像と `armv7 + arm64` 対応ビルドは、ソース／リソース指紋 `cdcbce40e799e4277d318953b1e2cf057cbfb116f70a9c1e5228f6afaee05e91` を共有しています。Simulator 版は端末版とは別のアプリ識別子と、サンドボックス内のメディア保存先を使います。再現方法は[ネイティブ Simulator プレビュー](DEVELOPMENT.md#native-simulator-preview)を参照してください。Simulator の表示は旧世代 iPad の実機動作を証明しません。各言語の README は実際のアプリ画像を使い、画面内の中国語と英語の表示をそのまま残しています。

## 追加レイアウトと生活シーン

次の6枚は build **20261112.41** を **iPad（第8世代）Simulator / iOS 18.0** で撮影した未加工のネイティブ画面 PNG です：[夕景ポスター](../../assets/demo/screens/sunset-poster.png)、[島のミニマル](../../assets/demo/screens/island-minimal.png)、[夜の街](../../assets/demo/screens/night-city.png)、[街並みとカレンダー](../../assets/demo/screens/city-calendar.png)、[緑の休息](../../assets/demo/screens/green-retreat.png)、[パームドライブ](../../assets/demo/screens/palm-drive.png)。寸法、ハッシュ、Simulator の出典は[キャプチャメタデータ](../../assets/demo/screens/CAPTURE-METADATA.json)を参照してください。

生活シーン：[ウェブサイトの書斎](../../assets/demo/environments/website-study.jpg)、[日差しのデスク](../../assets/demo/environments/daylight-desk.jpg)、[リネンのベッドサイド](../../assets/demo/environments/linen-bedside.jpg)、[夕暮れのコンソール](../../assets/demo/environments/dusk-console.jpg)。ウェブサイトの書斎は提供された背景を使い、以前の画面を現在の App キャプチャで完全に置き換えています。他の3点は生成した環境イラストです。各シーンの App 画面は元キャプチャを同じ配置で投影しており、UI の創作や描き直しはありません。iPad 2、iPad 4、初代 iPad Air の形状はイメージ表現であり、これらの実機で build 41 が動作したことや互換性、実機受け入れを示すものではありません。構図と素材の記録は[SCENES.json](../../assets/demo/environments/SCENES.json)にあります。

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
