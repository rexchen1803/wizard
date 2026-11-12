[简体中文](../open-source/GTA6-MATERIALS.md) · **繁體中文** · [English](../en/GTA6-MATERIALS.md) · [日本語](../ja/GTA6-MATERIALS.md)

# GTA VI 素材來源與權利說明

GTA VI 圖片、影片、截圖及其縮圖、轉碼和裁切的著作權屬於 **Rockstar Games 與相關權利人**。這些素材與 Wizard 自有程式碼分開管理，不受專案 MIT License 授權。本專案與 Rockstar Games 沒有隸屬、贊助或認可關係。

## 散佈狀態與素材包

截至 2026-11-13，[v0.2.0-preview.5](https://github.com/rexchen1803/wizard/releases/tag/v0.2.0-preview.5) 已公開發佈，以下圖庫和原始素材包均可免登入下載。清單中的 `download_url` 固定到此版本；下載後請核對大小和 SHA-256。

| 素材包 | 清單中的內容 | 預期用途 |
| --- | --- | --- |
| `wizard-gta6-gallery-20261112.zip` | 464 個檔案：230 個圖庫目錄項目、228 張橫向圖片、2 段 MP4 預告片、230 張縮圖，共 460 個媒體引用。 | Wizard 可選圖庫。 |
| `gta6-original-materials-20261112.zip` | 350 個檔案：343 張原始 JPEG、2 段 MKV 影片、2 份 SRT 字幕及套件內說明檔。 | 原始素材歸檔與後續製作參考。 |

兩個壓縮包的位元組數、SHA-256 和清單記錄見[素材清單](../../assets/media/MANIFEST.json)。每包均包含逐檔案清單、著作權署名和用途說明。原始檔名保留；App 圖庫的分類、簡短顯示名和穩定 key 分開管理。兩份 SRT 的作者來源尚未獨立覈實，不聲稱它們是 Rockstar 官方字幕。

素材來源核對、檔名匹配與內容分類記錄不等於逐檔案位元組層級來源證明，也不構成再分發授權。媒體包中的每個檔案仍受相應權利約束。

## Rockstar 官方來源

專案所有者從 Rockstar 的公開媒體與下載頁面整理了素材：

- [GTA VI Artwork & Wallpapers](https://www.rockstargames.com/VI/media/artwork-wallpapers)
- [GTA VI Media](https://www.rockstargames.com/VI/media)
- [GTA VI Videos](https://www.rockstargames.com/VI/media/videos)
- [Rockstar Games Legal Terms](https://www.rockstargames.com/legal/)

本專案整理的來源檔案記錄包含 27 組桌布構圖及其 142 個尺寸或標誌版本、138 張遊戲截圖、51 張 Ultimate Edition 圖片和 12 張 Vintage Vice City Pack 圖片。圖庫為每組桌布選擇一張橫向圖片，並保留全部截圖與內容包圖片。Rockstar 網站內容可能更新；此處描述的具體包範圍以[素材清單](../../assets/media/MANIFEST.json)和包內逐檔案清單為準。

## 儲存庫示範圖與授權範圍

儲存庫的 [assets/demo](CAPTURES.md) 說明隨程式碼保存的 App 截圖來源：目前八張 `*-miami.jpg` 和 `clock-font-system.jpg` 是 build `20261112.41` 在 iPad 第 8 代、iOS 18 模擬器中的原生截圖；`*-ipad2.png` 是 build `20261111.36` 的早期實體裝置截圖。截圖中的 GTA VI 畫面仍屬於 Rockstar Games 與相關權利人，不適用 Wizard 的 MIT 程式碼授權。

媒體包不包含使用者照片、個人偏好設定、裝置備份、連接資訊、F1 影片、歷史遊戲音訊、字型或 Apple SDK。安裝和執行階段條件見[安裝指南](INSTALL.md)，統一署名見 [ATTRIBUTION.md](../../assets/media/ATTRIBUTION.md)。

## App 預設圖與宣傳素材

build 41 App 候選包含 `App/Resources/ViceCity.jpg`，來源檔案為 `ULTIMATE_EDITION_VICE_CITY_STYLE_01.jpg`。該圖為 3840 × 2160 像素，儲存庫中的該檔案與來源位元組一致；SHA-256 為 `c255874fee509eae0baa6f546861e483ec0b32efbfe8d013ec36888013d923c9`。App 只在沒有外部圖庫目錄時使用它作為預設畫面。README 宣傳圖和原生截圖也使用了經署名的 Rockstar 素材。相關圖片與衍生圖均不受 MIT 授權。App 內另有 SIL OFL 字型；儲存庫不分發 Rockstar 字型檔案。

## 相關記錄

- [素材清單與驗證值](../../assets/media/MANIFEST.json)
- [統一素材署名](../../assets/media/ATTRIBUTION.md)
- [示範截圖來源與中繼資料](CAPTURES.md)
- [第三方授權與服務條款](THIRD_PARTY.md)
