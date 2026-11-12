# 第三方素材與建置需求

[简体中文](../zh-CN/THIRD_PARTY.md) · **繁體中文** · [English](../../THIRD_PARTY.md) · [日本語](../ja/THIRD_PARTY.md)

Wizard 自有程式碼採用根目錄的 [MIT License](../../LICENSE)。該授權不涵蓋第三方程式碼、字型、圖片、影片或其他素材；它們保留各自權利與條款。

## Google Material 圖示路徑

App 的部分矢量繪圖路徑來自 Google Material 圖示，固定到 [`material-design-icons` revision `10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7`](https://github.com/google/material-design-icons/tree/10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7)，按 Apache 2.0 分發。[上游授權副本](../../licenses/Material-Icons-Apache-2.0.txt)和根目錄 [NOTICE](../../NOTICE)保留署名與改動說明。

`IWMaterialPathForButton` 的 35 種變體對應 33 個上游 SVG，保留的路徑使用固定版本資料。原遊戲專用 Pet 和 Leaderboard 路徑已移除。繪製由本機 Core Graphics 完成，不包含 Google SVG、字型或圖片二進位檔；主題按鈕保留自製三色繪製分支。逐項來源見[圖示清單](../open-source/MATERIAL-ICONS.md)。

固定版本根目錄有 `LICENSE`；對應 SVG 路徑與上級目錄中未找到獨立 `NOTICE`、`COPYING` 或著作權檔案。保留路徑於2026-11-12按此前核對清單復核，資料未變。這是來源記錄，不構成法律授權結論。

## Apple SDK 與系統框架

裝置建置使用自行提供的 iPhoneOS SDK，連結 UIKit、Foundation、AVFoundation、MediaPlayer、CoreMotion、CoreLocation、CoreMedia、CoreText、QuartzCore、CoreGraphics 與 CoreFoundation。儲存庫不含 Apple SDK、框架二進位檔或 SDK 標頭檔；請透過 Apple 開發工具取得 SDK，並遵守其使用條款。

App 還會動態開啟 `BackBoardServices`、`GraphicsServices` 與 `SpringBoardServices` 私有框架，用於顯示和鎖屏操作。建置保留 `dynamic_lookup`，編譯成功不證明裝置上的符號可用。媒體與偏好位於 `/var/mobile/Media` 和 `/var/mobile/Library/Preferences`，體現歷史越獄/非沙盒部署假設。原版裝置側載尚未驗證，見[開發指南](DEVELOPMENT.md)。

## 可選電源插件與 Theos

儲存庫包含 `WizardPowerTweak` 原始碼，但不含 Theos、Logos、第三方標頭檔、庫或私有工作區工具鏈。歷史工具鏈記錄中的 Theos 採用 GPL-3.0-or-later；選擇使用 Theos 的建置者需自行取得並遵守其版本授權。主 App 的建置不會建置此外掛。可選 `scripts/build-power.sh` 直接使用 Apple Clang，無需散佈 Theos。插件注入、電源和執行相容性需要單獨驗收。

## 匯出範圍

經過審查的原始碼匯出排除 Apple SDK、第三方工具鏈、私有裝置安裝器、SSH 材料、連接日誌、known-host 資料、裝置狀態、歷史編譯產物、完整原始媒體套件、權利未經核實的字型/圖片，以及無關工作區內容。`assets/demo` 中的選定原生截圖保留 Rockstar 署名，完整素材包單獨作為 Release 附件提供。匯出報告分別記錄程式碼授權與第三方排除項。預覽版不承諾首次安裝、即時天氣或完整裝置驗收。

## 天氣服務

可選天氣轉接器保留用於評估，即時 Open-Meteo 接入尚未驗收。天氣卡提供在地化署名入口與說明頁，標示 Open-Meteo、[CC BY 4.0](https://open-meteo.com/en/licence)及 Wizard 的在地化和精簡處理。此前 iPad 2/4 的合成 fixture和原生天氣卡與詳細頁檢查僅適用於當時的建置；Air 的對應檢查未完成。早期實際請求出現 TLS `-1202`，沒有繞過系統信任。

Open-Meteo 的[服務條款](https://open-meteo.com/en/terms)將免費代管 API 限於非商業用途，並要求接受 CC BY 4.0 資料條款；[資料授權](https://open-meteo.com/en/licence)要求適當署名、授權連結和改動說明。商業代管服務另有訂閱條款。2026-11-12已重新核對這兩個頁面；不據此聲稱未來部署已滿足服務條件或取得法律授權。

## Rockstar Games GTA VI 素材

GTA VI 圖片、影片、裁切、轉碼、縮略圖與其他衍生內容歸 Rockstar Games 及相關權利人。素材來源陳述由專案所有者提供，指向 Rockstar 的公開下載頁面：[Artwork & Wallpapers](https://www.rockstargames.com/VI/media/artwork-wallpapers)、[媒體](https://www.rockstargames.com/VI/media)、[影片](https://www.rockstargames.com/VI/media/videos)。檔名清單核對不等於逐檔案位元組來源或再分發授權，即使可公開下載，這些內容也不會因此改採 MIT 授權。

相關權利要求見 Rockstar 的[法律條款](https://www.rockstargames.com/legal/)與[著作權內容發佈政策](https://support.rockstargames.com/articles/7bNaeoMFTV0iUDGhStTXvz/policy-on-posting-copyrighted-rockstar-games-material)。專案署名不構成授權或官方背書。

目前圖庫包有228張圖片、2段 GTA VI 預告片和相應縮略圖，另有獨立原始素材包；完整檔案範圍及字幕來源限制見[素材說明](GTA6-MATERIALS.md)和[素材清單](../../assets/media/MANIFEST.json)。原始包中的兩份 SRT 作者未經獨立覈實，不聲稱是 Rockstar 官方字幕。使用者匯入內容不歸入這份 Rockstar 署名。

## 字型

App 的靜態 `Anton-Regular.ttf` 保留原始位元組，Copyright 2020 The Anton Project Authors，採用 [SIL OFL 1.1](../../App/Resources/Anton-OFL.txt)。來源固定到 [Google Fonts revision `cee74d7ca45d66d5c1878c828645c862f2788d2d`](https://github.com/google/fonts/tree/cee74d7ca45d66d5c1878c828645c862f2788d2d/ofl/anton)，SHA-256 為 `a4ba3a92350ebb031da0cb47630ac49eb265082ca1bc0450442f4a83ab947cab`。字型與授權隨 App 打包，獨立於 MIT。README 的拉丁顯示字使用同一字型。

README 的閱讀文字和中文標題分別使用 Noto Sans CJK SC、TC 與 JP 的 Regular/Bold 字型轉為輪廓，採用 [OFL 1.1](../../licenses/NotoSansCJK-OFL.txt)。Noto 字型僅為可選宣傳圖生成輸入，不打入 App。固定來源、驗證值與重現方法見[宣傳圖來源](../../assets/readme/SOURCES.md)。

## 預設桌布與宣傳圖

`App/Resources/ViceCity.jpg` 是內建預設桌布，來自所提供的 `ULTIMATE_EDITION_VICE_CITY_STYLE_01.jpg`。原圖名稱與驗證值見[素材署名](../../assets/media/ATTRIBUTION.md)。README 和原生截圖也包含已提供素材；這些內容與衍生圖保留 Rockstar 及相關權利人著作權，排除在 MIT 之外。不分發 Rockstar 專有字型。
