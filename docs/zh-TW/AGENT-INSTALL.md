# Agent 安裝提示詞

[简体中文](../AGENT-INSTALL.md) · **繁體中文** · [English](../en/AGENT-INSTALL.md) · [日本語](../ja/AGENT-INSTALL.md)

將下面的完整提示詞交給 Codex 或其他 Agent，表示你授權在目前連接、已準備且明確指定的一台 iPad 上嘗試安裝一次 Wizard 預覽包。授權僅限 build `20261112.40`、該裝置和本次安裝；授權涵蓋唯讀檢查、獲取並驗證固定安裝套件、安裝一次、更新時最多停止 Wizard 一次，以及保留安裝程式建立的完整回復 bundle。它不授權越獄、變更密碼、設定連線、安裝電源插件、啟動 App、respring、重新啟動或變更儲存庫發佈狀態。

儲存庫目前為私有儲存庫，所有 Release 均為草稿。`v0.2.0-preview.4` 沒有公開下載端點。下面的固定下載網址標為**發佈後才可用**；Agent 必須先確認固定 `.deb` 與配套清單能通過已獲准的現有儲存庫存取方式取得。如果檔案不可用，必須在連線裝置前停止回報，不能發佈 Release、改變儲存庫可見性、改用 `latest` 或其他版本。

## 提示詞

```text
我授權你僅在目前已連接、已準備、且我明確指定的那一台 iPad 上，嘗試安裝 Wizard 0.2.0 / build 20261112.40 一次。授權只涵蓋本提示中列出的唯讀檢查、獲取和驗證固定安裝套件、一次安裝、更新時由安裝程式最多停止 Wizard 一次，以及保留完整舊 App 回復 bundle。不要重複詢問這些已授權步驟；目標裝置不明確時只詢問目標裝置。不要超出下面的裝置、版本和操作範圍。

儲存庫目前是私有儲存庫，所有 GitHub Release 都是草稿。v0.2.0-preview.4 尚未發佈，以下 GitHub 下載路徑是未來固定網址，目前沒有公開下載端點。先用目前已獲准的儲存庫存取方式確認固定 .deb 與對應 manifest 檔案確實可取得；如果任一檔案不可用，立即停止並回報，不要連接或操作裝置。不得發佈 Release、改變儲存庫可見性、建立下載端點、使用 latest、改用其他版本或從非指定來源取得替代包。維護者 Release 頁面僅作獲准帳戶查看草稿的入口：https://github.com/rexchen1803/wizard/releases

發佈後唯一接受的 build 40 檔案及固定路徑：
- wizard_0.2.0-20261112.40_iphoneos-arm.deb
  https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.4/wizard_0.2.0-20261112.40_iphoneos-arm.deb
- wizard_0.2.0-20261112.40_iphoneos-arm.deb.manifest.json
  https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.4/wizard_0.2.0-20261112.40_iphoneos-arm.deb.manifest.json

1. 在任何裝置連接前，確認兩個固定檔案均可從獲准來源取得，檔名、套件版本和 manifest 對應一致，並核對 .deb 的 SHA-256 等於 manifest 中的 artifact_sha256。任何檔案缺失、雜湊不符、版本不符或來源不同，都停止並回報；不要繼續裝置檢查。
2. 只有在第 1 步全部通過後，才對唯一目標裝置做唯讀預檢：讀取確切型號和 iOS 版本，確認 rootful 越獄、Debian 套件管理環境、root 權限、可寫且非符號連結的 /Applications，以及 sysctl、sw_vers、ldid、uicache 和 killall 是否可用。檢查 Wizard bundle 是否已安裝。只能使用已設定並獲准的本機 USB 或 SSH 通道；不得建立帳號、變更密碼、啟用 SSH、變更網路、安裝憑證或改變信任設定。若該通道已設定並獲准但缺少登入憑證，只詢問該登入憑證；連線失敗或需要其他未授權設定時停止。
3. 只接受以下精確型號與系統配對：iPad2,4 + iOS 9.3.5；iPad3,4 + iOS 10.3.3；iPad4,1 + iOS 12.5.8。未越獄原生 iOS、rootless 越獄、iPhone 或任何其他型號/版本均停止，不要試圖建立或修復越獄，也不要繞過預檢。
4. 預檢通過後，通過裝置現有的 Cydia、Sileo、Zebra、Filza 或已獲准的 rootful dpkg 流程安裝該固定 .deb。此處的單次安裝已獲本提示授權。更新時安裝程式最多向 Wizard 傳送一次 TERM，並把原有 WizardSystem.app 完整保留為 WizardSystem.rollback-<build>-<UTC>.app。它會使用裝置已有的 ldid 簽章，並呼叫 uicache 註冊；不要安裝電源 tweak、啟動 Wizard、respring、重新啟動或操作其他 App。首次安裝沒有舊 App 回復 bundle。
5. 安裝後唯讀核對 bundle ID、版本、build、App 路徑、套件管理工具結果，以及媒體資料夾和偏好設定是否仍存在。不要讀取、複製或輸出媒體內容或偏好設定值。不要啟動 App；明確回報：「build 20261112.40 尚無實體裝置驗收」。安裝程式成功或套件管理工具回傳成功都不等於使用者已驗收。
6. 安裝失敗、關鍵狀態無法讀取，或安裝程式回報任何錯誤時，原樣記錄錯誤並停止。保留所有 WizardSystem.app、WizardSystem.rollback-*、WizardSystem.uninstalled-* 和 WizardSystem.failed-* 資料夾；不刪除、覆寫、手動修復或猜測清理任何資料，也不強制 respring 或重新啟動。

除非我在另一個明確請求中要求卸載，否則不要卸載 Debian 包。獲准卸載時，套件管理工具的卸載鈎子只註銷 build 與套件相符的 Wizard App，並把完整 bundle 保留為 WizardSystem.uninstalled-<build>-<UTC>.app；媒體、偏好設定和既有回復 bundle 保留。若需還原，重新安裝同一固定 .deb 取回 helper，再按 INSTALL.md 的 rollback 說明使用真實的 WizardSystem.uninstalled-* 路徑。不得讓 dpkg 或手動命令清理還原 bundle。

本授權不包含下載或安裝 Rockstar 媒體。只有我另行明確要求圖庫安裝時才可處理圖庫。圖庫也在未發佈的 v0.2.0-preview.4 草稿中；如果附件無法通過獲准方式取得，停止，不得發佈 Release 或改變儲存庫可見性。發佈後唯一接受的圖庫檔案為 wizard-gta6-gallery-20261112.zip，SHA-256 必須是 b8bd883b81a0a76086217ce3c27091d83b0b8261dcbabae49c88abb67aef3eba；固定未來網址為：
https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.4/wizard-gta6-gallery-20261112.zip
若我明確授權安裝該圖庫，先完整備份 /var/mobile/Media/iPadWizard/app，再核對雜湊，把 ZIP 中 app/ 的內容合併到此資料夾。絕不取代整個 app/，保留 assets/user、使用者匯入照片和偏好設定。原始素材包不是裝置圖庫安裝套件。Rockstar 素材來源標注不等於獲得再分發授權。
```

原始碼建置、提示詞授權、SHA-256 驗證、安裝程式成功和實體裝置驗收是不同的證據。裝置驗收範圍見[相容性指南](COMPATIBILITY.md)，完整安裝與還原說明見[安裝指南](INSTALL.md)。
