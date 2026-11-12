# 示範截圖來源

[简体中文](../../assets/demo/README.md) · **繁體中文** · [English](../../assets/demo/README.en.md) · [日本語](../ja/CAPTURES.md)

## Build 41 Miami 預覽

`*-miami.jpg` 來自 build **20261112.41** 在 **iPad（第 8 代）模擬器 / iOS 18.0** 中的原生 UIKit 畫面。原始截圖為 2160 × 1620 PNG；網頁圖片維持相同像素尺寸，以 JPEG quality 85 編碼，未合成、新增或重繪 App 介面。原始 PNG 的 SHA-256、網頁圖片雜湊值、場景命令和原始碼指紋記錄在 [CAPTURE-METADATA.json](../../assets/demo/CAPTURE-METADATA.json)；build 41 的原始碼與資源指紋為 `cdcbce40e799e4277d318953b1e2cf057cbfb116f70a9c1e5228f6afaee05e91`。

- [主畫面](../../assets/demo/home-miami.jpg)：未安裝外部圖庫時顯示內建 Vice City 預設圖。
- [圖庫](../../assets/demo/gallery-miami.jpg)、[分類](../../assets/demo/categories-miami.jpg)：示範資料夾由 230 項素材包加上選用的預設圖組成，共 231 項；未加入使用者照片。
- [主選單](../../assets/demo/menu-miami.jpg)、[設定](../../assets/demo/settings-miami.jpg)、[主題](../../assets/demo/themes-miami.jpg)。
- [時鐘編輯](../../assets/demo/clock-edit-miami.jpg)、[行事曆](../../assets/demo/calendar-miami.jpg)。
- [系統字型](../../assets/demo/clock-font-system.jpg)：時鐘字型選為「系統」時的原生畫面。

模擬器截圖與 `armv7 + arm64` 裝置建置使用相同的原始碼與資源指紋；模擬器使用獨立 App 識別碼和沙盒媒體路徑。建置入口及重現步驟見[原生模擬器預覽](DEVELOPMENT.md#建置原生模擬器預覽)。模擬器檢查不替代舊款實體 iPad 的執行驗收。

## 字型來源

build 41 候選沿用 App 已打包的靜態開源字型 `Anton-Regular.ttf` 與 OFL 1.1 授權。時鐘編輯面板新增「海報」與「系統」兩種字型選項；「海報」預設使用 Anton-Regular。截圖中繼資料記錄實際解析的字型名稱、字型檔案 SHA-256 與字型是否來自 App 套件；系統選項畫面見上方 [系統字型](../../assets/demo/clock-font-system.jpg) 截圖。中文控制項使用系統字型。build `20261111.36` 的實體裝置截圖保留當時外觀，不作為 build 41 的驗收證據。

## 保留的舊版實體裝置宣傳圖


以下 build `20261111.36` 原始 PNG 保持原像素，來自 iPad2,4 / iOS9.3.5，拍攝於 2026-11-11：

- [舊版主畫面](../../assets/demo/home-ipad2.png)
- [舊版圖庫](../../assets/demo/gallery-ipad2.png)
- [舊版分類](../../assets/demo/categories-ipad2.png)

它們是舊版實體裝置記錄，不能作為目前 Miami 建置的實體裝置驗收。

## 署名

GTA VI 圖片和截圖中的相應素材著作權屬於 Rockstar Games 與相關權利人；這些示範圖片不適用 Wizard 的 MIT 原始碼授權。具體原圖和權利範圍見[素材署名](../../assets/media/ATTRIBUTION.md)。

## 網站演示原圖

[個人網站原始演示圖](../../assets/demo/website-original.jpg)依原檔保留，未更換螢幕、裁切或重繪。它保留網站原有示意畫面，獨立作為環境展示，不計入目前建置的原生擷取。
