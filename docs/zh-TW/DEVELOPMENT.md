[简体中文](../zh-CN/DEVELOPMENT.md) · **繁體中文** · [English](../open-source/README.md) · [日本語](../ja/DEVELOPMENT.md)

# Wizard 原始碼與開發指南

本儲存庫包含 Wizard 這款舊版 Objective-C/UIKit 原生 iPad App、主機迴歸檢查、打包與安裝工具，以及一個可選電源 tweak。核心 App 與 tweak 是獨立元件。

App 原始碼候選為 **0.2.0 / build 20261112.41**，原始碼與資源指紋為 `cdcbce40e799e4277d318953b1e2cf057cbfb116f70a9c1e5228f6afaee05e91`。截至 2026-11-12，該版本尚未安裝到實體 iPad。原始碼儲存庫及 [v0.2.0-preview.5](https://github.com/rexchen1803/wizard/releases/tag/v0.2.0-preview.5) 的安裝套件、素材附件均已公開；素材清單記錄固定下載網址和雜湊。build 41 在時鐘編輯面板新增「海報」與「系統」兩種字型選項；預設仍為使用 Anton-Regular 的「海報」。儲存與取消會保留原有狀態。這項變更尚未通過實體裝置驗收。

Wizard 自有程式碼使用根目錄的 [MIT License](../../LICENSE)。該授權條款不涵蓋第三方圖片、字型、使用者匯入內容或其他素材。請參閱[第三方聲明](THIRD_PARTY.md)和 [GTA VI 素材指南](GTA6-MATERIALS.md)。貢獻前可先閱讀[貢獻指南](CONTRIBUTING.md)。

## 建置

在 macOS 上使用 Apple Clang、Xcode 命令列工具，以及透過 Apple 開發工具取得的 iPhoneOS SDK。儲存庫和原始碼匯出包均不包含 SDK。

```sh
IOS_SDK="/path/to/iPhoneOS9.3.sdk" ./scripts/build-ipad.sh
```

已驗證的 SDK 為 iPhoneOS 9.3。腳本產生未簽章的 `WizardSystem.app`，架構為 `armv7` 與 `arm64`，最低部署目標為 iOS 9.0。這些設定說明建置目標，不證明所有 iOS 9–12 裝置都能執行。較新的 SDK 建置尚未驗證，包括舊版 `armv7` 與 MediaPlayer 行為。

建置會將編譯器與 SDK 資訊、編譯命令樣板、原始碼輸入雜湊、寫入 App plist 的組合指紋、產物雜湊、架構和警告記錄到 `BUILD-METADATA.txt`。編譯期間若授權清單中的原始碼或資源發生變化，腳本會停止。腳本使用 `nm -u -j` 檢查未定義符號；檢查出錯或 App 自有的 `IW` 符號仍未解析時，不會繼續。舊式 `dynamic_lookup` 連結選項仍用於私有系統符號；主機編譯成功不證明這些符號在裝置上存在或可用。腳本不會簽章或安裝 App。

歷史 build 20261112.39 的中繼資料模板漏記了連結參數中的 `CoreText`，雖然當時的建置腳本確實連結了該 framework。腳本中的模板已修正；此處的描述錯誤沒有改變 App 原始碼指紋、打包產物或內建字型。

預設輸出到新建的 `.private-audit` 子目錄。可通過 `--out PATH` 指定不存在的輸出目錄；腳本不會清空已有目錄。建置會包含已審核的 App 圖示與橫向啟動圖、署名明確的 `ViceCity.jpg` 預設圖，以及靜態 OFL 字型 `Anton-Regular.ttf` 和對應授權條款。因此 App 中含有第三方素材；編譯不需要另行下載 GTA VI 完整素材包或專有字型。Rockstar 圖片不屬於 MIT 授權條款，詳見 [GTA VI 素材指南](GTA6-MATERIALS.md)。

## 執行主機檢查

CI 使用 GitHub 的 `macos-15` runner。在儲存庫根目錄執行以下相同檢查：

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

最後八個命令是主機原始碼迴歸測試。前面的命令檢查儲存庫內容、儲存庫檢查器迴歸、打包與安裝器 fixture，以及 Shell 語法。這些測試使用 fixture、擷取自正式程式碼的方法和 UI double。CI 不會建置裝置版 App，也不會下載或重新分發 Apple SDK。這些檢查不會簽章或安裝 App，不驗證原生渲染，也不會在裝置上解析私有系統 API，不能替代實體裝置驗收。

## 建置原生模擬器預覽

使用 Xcode 已安裝的 Simulator SDK 建置單獨的 iPad 模擬器預覽：

```sh
python3 scripts/build-preview.py --out build-preview
```

腳本會產生識別碼為 `com.rex.wizard.preview`、目標為 iOS 18 或更新版本的臨時簽章 `WizardPreview.app`，並在 `PREVIEW-METADATA.json` 中記錄原始碼與資源指紋。它不會安裝 App 或啟動模擬器。預覽素材位於該 App 容器內的 `Documents/WizardMedia`；裝置版繼續使用 `/var/mobile/Media/iPadWizard/app`。

僅在為本專案選定的專用模擬器上檢查 UIKit 渲染或截圖。[截圖來源](CAPTURES.md)中的八張 `*-miami.jpg` 和新增的 `clock-font-system.jpg` 是 build 41 在 iOS 18 的 iPad 第 8 代模擬器截圖。該頁的三張 `*-ipad2.png` 是 build `20261111.36` 的早期實體裝置截圖，不代表 build 41 的裝置驗收。兩組截圖均不能證明舊版 iOS 相容性。證據矩陣見[相容性指南](../COMPATIBILITY.md)。

預覽接受最多八個授權清單內的場景命令，通過 `WizardPreviewCommands` 傳入。例如：

```sh
xcrun simctl launch --terminate-running-process SIMULATOR_UDID com.rex.wizard.preview \\
  -WizardPreviewCommands "main,settingsmenu"
xcrun simctl io SIMULATOR_UDID screenshot settings.png
```

截圖前等待場景切換完成。命令序列示例：`main,menu`、`main,themesmenu`、`main,gallery,gallerycategories` 和 `main,clockedit`。該入口僅存在於模擬器建置，呼叫真實 App 操作並避免外部 URL 確認彈窗。它不會改變裝置建置，也不會授權安裝到裝置。

## 執行階段與安裝邊界

App 依賴普通App 容器之外的媒體與偏好路徑。`App/main.m` 使用 `/var/mobile/Media/iPadWizard/app` 存放媒體和狀態，並在 `/var/mobile/Library/Preferences` 下讀寫電源偏好。它會動態解析 Apple 私有 BackBoardServices、GraphicsServices 和 SpringBoardServices 框架中的符號。

這是根據原始碼推斷的舊執行方式，不是 plist 授予的能力。首次安裝和原生 iOS 側載尚未驗證。任何裝置操作前，請先閱讀[裝置安裝與執行階段資料](../open-source/INSTALL.md)，瞭解已準備裝置的有限更新範圍及前置條件。編譯成功、主機測試或模擬器截圖均不代表安裝成功或實體裝置驗收。

獨立的 `App/WizardPowerTweak/` 使用私有 SpringBoard API，可能改變鎖屏、喚醒和顯示行為。`scripts/build-power.sh` 會為 `armv7` 和 `arm64` 建置它，但不簽章、不安裝，也不證明執行相容性。核心 App 安裝器不會安裝該 tweak。詳見其[元件指南](../../App/WizardPowerTweak/README.md)。

## 隱私與服務整合

建置或分發前請閱讀[隱私與網路行為](PRIVACY.md)。App 會匯入使用者選擇的照片、開放區域網路媒體控制服務，並可播放提供的 URL。`App/Info.plist` 設定了 `NSAllowsArbitraryLoads=true`；這不是安全審查，也不證明每條網路路徑都可用。

天氣卡片包含服務商署名控制項。使用合成 fixture 的原生檢查不代表即時服務相容。Open-Meteo 傳輸和法律授權狀態仍未驗證；變更或描述該整合前，請閱讀[第三方條款](THIRD_PARTY.md)。

## 準備本機原始碼匯出包

在原始工作區執行：

```sh
python3 scripts/prepare-open-source.py
```

可用 `--out PATH` 指定一個尚不存在的輸出目錄。匯出器按審核過的 allowlist 複製檔案，寫入 `OPEN_SOURCE_EXPORT_REPORT.json`，並檢查常見工作站路徑與憑證模式。這些檢查不等於完整隱私或安全審查。匯出器不會初始化 Git、存取網路、簽章、安裝或發佈。iPhoneOS SDK、私有裝置狀態、憑證和使用者照片不會進入原始碼匯出包。

## 授權條款與署名

Wizard 自有程式碼使用根目錄 MIT License。Google Material 路徑資料另依根目錄 `NOTICE` 中的 Apache 2.0 聲明。App 包含的顯示字型及其 SIL OFL 1.1 授權條款分別作為檔案保留。GTA VI 圖片、影片、截圖及其衍生素材的著作權屬於 Rockstar Games 與相應權利人，不受 MIT 授權。詳見 [GTA VI 素材指南](GTA6-MATERIALS.md)、[截圖來源](CAPTURES.md)、[第三方聲明](THIRD_PARTY.md)和[貢獻指南](CONTRIBUTING.md)。
