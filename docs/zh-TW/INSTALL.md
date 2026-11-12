# 安裝 Wizard

[简体中文](../INSTALL.md) · **繁體中文** · [English](../en/INSTALL.md) · [日本語](../ja/INSTALL.md)

本文介紹 Wizard 0.2.0 / build `20261112.40` 的預覽安裝套件、原始碼建置、可選圖庫和回復方式。時鐘編輯面板提供「海報」與「系統」兩種字型，預設仍為使用 Anton-Regular 的「海報」；build 40 尚無實體裝置驗收。安裝套件僅供已完成準備的 **rootful 越獄 iPad** 使用；它不會安裝越獄或電源外掛，也不會修改憑證、網路或系統信任設定，或自動啟動 App。

## 目前下載狀態

儲存庫目前是私有儲存庫，所有 GitHub Release 均為草稿。`v0.2.0-preview.4` 也尚未發佈，因此現在沒有公開的 `releases/download/...` 下載端點。獲准的維護者可登入後從 [Releases 頁面](https://github.com/rexchen1803/wizard/releases)查看草稿；該頁面是維護入口，不代表公開下載已開放，也不保證附件可用。若你沒有權限讀取所需附件，或固定檔案不可用，請停止；不要發佈 Release、改變儲存庫可見性或改用 `latest`。即使日後發佈 Release，只要儲存庫仍為私有，附件存取仍受儲存庫權限控制。

v0.2.0-preview.4 發佈後，build 40 安裝套件和清單的固定檔名及預期路徑為：

| 檔案 | 固定檔名 | 發佈後的固定下載網址（目前尚不可用） |
| --- | --- | --- |
| Wizard Debian 套件 | `wizard_0.2.0-20261112.40_iphoneos-arm.deb` | `https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.4/wizard_0.2.0-20261112.40_iphoneos-arm.deb` |
| 套件清單 | `wizard_0.2.0-20261112.40_iphoneos-arm.deb.manifest.json` | `https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.4/wizard_0.2.0-20261112.40_iphoneos-arm.deb.manifest.json` |

只有在固定版本的 `.deb` 和同一版本清單均可從獲准來源取得時才繼續。使用清單中的 `artifact_sha256` 核對 `.deb`：macOS 可執行 `shasum -a 256 wizard_0.2.0-20261112.40_iphoneos-arm.deb`。版本、檔名或雜湊值不一致時停止，不混用其他版本的套件與清單。打包腳本會為每次輸出產生對應清單和雜湊；本儲存庫沒有硬編碼可替代下載清單的 build 40 `.deb` 雜湊。

## 裝置範圍與前置條件

安裝程式只接受以下精確型號與 iOS 版本配對：

| 裝置 | 型號識別碼 | iOS |
| --- | --- | --- |
| iPad 2 | `iPad2,4` | `9.3.5` |
| iPad 4 | `iPad3,4` | `10.3.3` |
| iPad Air | `iPad4,1` | `12.5.8` |

還必須具備 rootful 越獄環境、root 權限、可寫且不是符號連結的 `/Applications`、Debian 套件管理環境，以及 `ldid`、`uicache`、`killall`、`sysctl` 和 `sw_vers`。`uicache` 必須支援 `-p` 註冊和 `-u` 取消註冊。原版未越獄的原生 iOS、rootless 越獄、iPhone，以及未列出的裝置或系統版本都會被拒絕。不得通過改型號或系統版本繞過檢查。

套件結構與安裝程式的本機 fixture 預檢不等於裝置上的安裝、簽章、註冊或啟動驗收。較早 build 在個別已準備裝置上的記錄見[相容性表](COMPATIBILITY.md)；它們不證明 build 40 的首次安裝。目前 build 40 的裝置驗收仍未完成。

## 安裝預覽包

確認上文所列固定檔案在你的獲准來源中可用後：

1. 下載 `wizard_0.2.0-20261112.40_iphoneos-arm.deb` 及其同名 `.manifest.json` 清單。草稿未公開時，不要把上述未來下載網址當作可用連結；維護者可從 [Releases 頁面](https://github.com/rexchen1803/wizard/releases)開啟草稿。若附件無法獲取，停止。
2. 按清單中的 `artifact_sha256` 驗證 `.deb`。只使用與該包配套的清單；不要改用 `latest`、別的 Release 或重新命名的包。
3. 在已授權的目標 iPad 上，通過 Filza 或 Cydia、Sileo、Zebra 支援的本機 `.deb` 安裝流程安裝。已獲准的裝置 root 終端也可執行：

   ```sh
   dpkg -i ./wizard_0.2.0-20261112.40_iphoneos-arm.deb
   ```

安裝掛鉤先驗證裝置型號、系統、rootful 環境、套件管理工具、所需工具和 App 路徑。安裝程式在裝置上使用已有的 `ldid` 為未簽章 App 執行 ad-hoc 簽章，並用 `uicache` 註冊 App。更新時它最多向 Wizard 發送一次 `TERM`，把原有 App 完整保留為 `WizardSystem.rollback-<build>-<UTC>.app`，再放入候選 App。首次安裝沒有舊 App 可作為回復副本。安裝程式不會啟動 Wizard、重新啟動裝置或執行 respring。

安裝套件取代範圍不包括 `/var/mobile/Media/iPadWizard/app`、Wizard 偏好設定或既有回復目錄。若簽章、檔案取代或註冊失敗，安裝程式會按實際分支復原或保留候選、舊 App 和還原目錄。保留錯誤現場並報告原始錯誤；不要強制 respring、刪除還原目錄或清理使用者資料。安裝成功只表示安裝程式完成，仍需由使用者手動開啟 App 並單獨驗收。

## 從原始碼建置

儲存庫目前為私有儲存庫，克隆需要獲准的 GitHub 存取權限。建置需要 macOS、Apple Clang 和自行從 Apple 開發工具中取得的 iPhoneOS SDK；Apple SDK 不包含在儲存庫中。目前驗證過的 SDK 是 iPhoneOS 9.3；較新 SDK 的 armv7 與舊 MediaPlayer 介面相容性尚未驗證。

```sh
git clone https://github.com/rexchen1803/wizard.git
cd wizard
IOS_SDK="/path/to/iPhoneOS9.3.sdk" ./scripts/build-ipad.sh --out /tmp/WizardSystem-build
python3 scripts/package-release.py \
  --app /tmp/WizardSystem-build/WizardSystem.app \
  --out /tmp/wizard_0.2.0-20261112.40_iphoneos-arm.deb
```

輸出 App 資料夾、`.deb` 和相鄰 manifest 必須尚不存在。打包器要求版本檔名與 App build 一致，核對 `armv7`、`arm64` 架構、bundle ID、資源和來源指紋，並在本次產生的清單中寫入 `artifact_sha256`。`--dry-run` 只輸出套件結構和雜湊，不寫入套件檔案。建置和打包命令不會連接裝置或執行安裝。完整的[原始碼與開發指南](DEVELOPMENT.md#建置)說明瞭原始碼驗證範圍；[WizardPower 原始碼說明](../../App/WizardPowerTweak/README.md)有獨立建置入口，Wizard 安裝套件不會自動安裝該外掛。

## 可選 GTA VI 圖庫

圖庫和原始素材套件也屬於尚未公開的 `v0.2.0-preview.4` 草稿附件。目前沒有公開下載端點。只有維護者或已獲准的使用者能從草稿取得附件時才可使用；無法獲取時停止，不要發佈 Release 或改變儲存庫可見性。

| 檔案 | 內容 | 大小 | SHA-256 |
| --- | --- | ---: | --- |
| `wizard-gta6-gallery-20261112.zip` | 230 項圖庫目錄、228 張圖片、2 段影片及縮略圖 | 258,253,713 bytes | `b8bd883b81a0a76086217ce3c27091d83b0b8261dcbabae49c88abb67aef3eba` |
| `gta6-original-materials-20261112.zip` | 343 張原始 JPEG、2 段 MKV、2 份 SRT | 755,809,316 bytes | `182cb83aaf463dc22004f750a4e51a2419ef50eb2da851aba9c6d456d89aea0b` |

這些固定檔案的[本機清單](../../assets/media/MANIFEST.json)記錄預期大小與 SHA-256。發佈後的固定路徑如下，**目前尚不可用**；儲存庫保持私有時仍需獲准的儲存庫存取權限：

```text
https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.4/wizard-gta6-gallery-20261112.zip
https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.4/gta6-original-materials-20261112.zip
```

App 圖庫包僅在你另行選擇並授權安裝後使用。先完整備份裝置上的 `/var/mobile/Media/iPadWizard/app`，再將 ZIP 中 `app/` 的內容合併到該目錄；保留現有 `assets/user` 和偏好設定，不刪除或取代整個 `app` 目錄。若傳輸工具改寫了新複製檔案的權限，只修正這些新檔案，不遞迴變更已有使用者目錄。重新開啟 Wizard 後檢查原有桌布、收藏、裁切、使用者匯入照片和分類。原始素材套件用於收藏與製作，不是裝置圖庫安裝套件。素材著作權與署名見[素材說明](GTA6-MATERIALS.md)及[署名清單](../../assets/media/ATTRIBUTION.md)；Rockstar 素材不適用 Wizard 的 MIT 程式碼授權。

## 回復與卸載

更新後記錄安裝程式打印的確切回復目錄。在裝置上已獲准的 root 終端中，將示例中的佔位部分取代為安裝程式實際打印的完整路徑：

```sh
/usr/lib/wizard-installer/install-wizard.sh rollback "/Applications/WizardSystem.rollback-<build>-<UTC>.app"
```

回復會保留目前候選 App 為 `WizardSystem.failed-rollback-<UTC>.app`，還原指定的 `WizardSystem.rollback-*` 或 `WizardSystem.uninstalled-*` 目錄並重新註冊；不會啟動 App 或重新啟動 SpringBoard。遇到失敗時保留各目錄並報告，不猜測刪除或覆寫。

只有在任務明確要求卸載 Debian 套件時，才通過套件管理工具卸載，或在獲准的裝置 root 終端執行：

```sh
dpkg -r com.rex.wizardsystem
```

卸載鈎子只會註銷 build 與目前包匹配的 Wizard App，並將完整 bundle 保留為 `WizardSystem.uninstalled-<build>-<UTC>.app`；如果已安裝 App 的 build 不匹配，則保留該 App，但套件管理工具仍可能繼續移除本包及其 helper。卸載不清除媒體、偏好設定和既有回復目錄。若要還原被歸檔的 App，重新安裝同一固定 `.deb` 取回 helper，再把真實的 `WizardSystem.uninstalled-*` 路徑傳給 `rollback`。清除個人媒體或偏好設定是獨立操作，不屬於普通卸載。

App bundle 內含已署名的 Vice City 預設桌布；沒有外部圖庫時也可顯示。完整圖庫是可選附件。
