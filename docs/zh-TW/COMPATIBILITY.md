# 相容性與驗證狀態

[简体中文](../zh-CN/COMPATIBILITY.md) · **繁體中文** · [English](../COMPATIBILITY.md) · [日本語](../ja/COMPATIBILITY.md)

本指南區分建置證據、主機檢查、模擬器截圖與實體裝置執行情況。以下狀態以 2026-11-12 的 **Wizard 0.2.0 / build 20261112.41** 候選為準。build 41 已使用 iPhoneOS 9.3 SDK 建置為 `armv7` 與 `arm64`，也已建置 iPad 模擬器版本；App 原始碼與資源指紋為 `cdcbce40e799e4277d318953b1e2cf057cbfb116f70a9c1e5228f6afaee05e91`。該版本尚未安裝到任何實體 iPad。

## 按環境查看證據

| 環境 | 已驗證證據 | 證據邊界 |
| --- | --- | --- |
| 裝置建置目標 | App 聲明的最低部署版本為 iOS 9.0。候選 build `20261112.41` 使用 iPhoneOS 9.3 SDK 在本機編譯為 `armv7` 與 `arm64`。 | 部署目標和成功編譯不代表已相容 iOS 9–12、更新的 iOS 版本或任一裝置執行環境。 |
| iPad（第 8 代）模擬器，iOS 18.0 | build 41 的模擬器預覽使用已安裝的 iPhoneSimulator 27.1 SDK 建置，與裝置版使用相同的 App 原始碼與資源指紋。八張 `*-miami.jpg` 和新增的 `clock-font-system.jpg` 均為 build 41 的原生模擬器截圖。 | 模擬器呈現不證明實體裝置行為，也不代表 iOS 9–12 相容性。 |
| macOS 主機與 CI | `macos-15` [CI 工作流程](https://github.com/rexchen1803/wizard/actions/workflows/ci.yml)執行儲存庫與封裝檢查、Shell 語法檢查及九個主機迴歸命令。 | 主機測試資料、擷取自正式程式碼的方法與 UIKit 測試替身不會建置或安裝裝置版 App，也不能證明原生呈現、簽章、私有符號解析或裝置行為。 |
| iPad 2，`iPad2,4`，iOS 9.3.5 | 較早的 build `20261111.30` 更新到已有、已準備的安裝環境。記錄的檢查涵蓋啟動、選單、圖庫、偏好保留、指定的動態效果、行事曆和編輯流程，以及實體照片選擇與匯入。 | 這是早期版本在已準備安裝環境中的證據，不涵蓋 build `20261112.41`、首次安裝、原生系統或非越獄環境、輔助功能及全部互動。 |
| iPad 4，`iPad3,4`，iOS 10.3.3 | 較早的 build `20261111.30` 更新到已有、已準備的安裝環境。記錄的檢查涵蓋指定介面、行事曆、影片與媒體資源行為。 | 這是早期版本在已準備安裝環境中的證據，不涵蓋 build `20261112.41`、首次安裝、原生系統或非越獄環境、輔助功能及廣泛日常使用。 |
| iPad Air，`iPad4,1`，iOS 12.5.8 | 較早的 build `20261111.36` 更新到已還原並準備好的安裝環境。記錄了指定 UI 與媒體同步檢查。 | 這是早期版本在已準備安裝環境中的證據，不涵蓋 build `20261112.41`、首次安裝、原生系統或非越獄環境、完整播放、輔助功能及廣泛日常使用。 |
| 目前版本的實體 iPad 執行 | 尚無實體 iPad 安裝過 build `20261112.41`。 | 不宣稱目前版本已通過實體裝置驗收。 |
| 首次安裝或原生 iOS | 沒有已驗證的安裝路徑。現有安裝證據僅限已準備的 rootful 或 unsandboxed 裝置。 | 尚未證明原生裝置或首次安裝所需的簽章、註冊、外部儲存空間存取和私有框架行為。 |

已準備裝置的驗證範圍及前置條件見[裝置安裝與執行階段檔案](../open-source/INSTALL.md)。[示範截圖來源](CAPTURES.md)中的 `home-ipad2.png`、`gallery-ipad2.png` 和 `categories-ipad2.png` 是 build `20261111.36` 的早期實體裝置記錄，不是 build `20261112.41` 的截圖。目前 `*-miami.jpg` 則來自 iPad 第 8 代模擬器。

## 建置與主機檢查

目前候選使用 iPhoneOS 9.3 SDK 建置裝置版本。SDK 必須從 Apple 開發工具取得，原始碼儲存庫和匯出包均不包含 SDK。更新 SDK 建置未經驗證，包括其與舊版 MediaPlayer 介面及 `armv7` 的相容性。詳見[原始碼建置與貢獻指南](DEVELOPMENT.md#建置)。

CI 是 macOS 主機任務，會執行儲存庫檢查器及其迴歸用例、打包與安裝器 fixture、Shell 語法檢查，以及以下九個主機迴歸命令：

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

這些檢查可用於發現原始碼迴歸，但不能替代在目標裝置與系統版本上進行的安裝、啟動、互動、媒體、輔助功能和長時間執行檢查。

## 執行階段限制與可選元件

核心 App 從一般 App 容器之外的 `/var/mobile/Media/iPadWizard/app` 和 `/var/mobile/Library/Preferences` 讀取媒體與偏好檔案。它會動態解析 Apple 私有 `BackBoardServices`、`GraphicsServices` 和 `SpringBoardServices` 框架中的符號。主機編譯無法證明這些符號能在目標裝置解析或正常工作。

可選的 `WizardPower` tweak 是獨立元件，不屬於核心 App 的安裝流程，並使用私有 SpringBoard API。其建置、安裝與執行驗收需要分別審查；見[tweak 指南](../../App/WizardPowerTweak/README.md)。

iOS 18 模擬器中的影片檢查顯示了主題控制項和推進的媒體時間，但螢幕錄影未包含解碼後的影片畫面。從同一個靜音 fixture 提取的影格有效。該現象無法確定原因，也不代表實體裝置播放情況。原始碼仍保留舊裝置播放路徑；不宣稱 iOS 9–12 均可播放。

## 內建顯示字型

Build `20261112.41` 的裝置版與模擬器 App 都包含未修改的靜態字型 `Anton-Regular.ttf` 及其 SIL OFL 1.1 授權條款。`UIAppFonts` 註冊該字型。build 41 的模擬器截圖中繼資料記錄實際解析的字型名稱、SHA-256 和字型是否來自 App 套件。打包檢查會拒絕缺失或變更的字型、授權條款位元組及缺失的字型註冊。這驗證的是打包輸入，不代表舊款實體 iPad 上的呈現完全一致。build 41 的時鐘編輯面板提供「海報」與「系統」兩種字型；「海報」仍以 Anton-Regular 為預設，儲存與取消會保留原有狀態。系統字型截圖只證明模擬器畫面；build 41 尚無實體裝置驗收。

## 相關資料

- [原始碼建置與貢獻指南](DEVELOPMENT.md)
- [裝置安裝與執行階段檔案](../open-source/INSTALL.md)
- [模擬器和歷史截圖來源](CAPTURES.md)
- [第三方素材與授權條款](THIRD_PARTY.md)
