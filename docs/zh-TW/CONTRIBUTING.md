# 參與貢獻

[简体中文](../zh-CN/CONTRIBUTING.md) · **繁體中文** · [English](../../CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md)

提交修改前，請閱讀[相容性範圍](COMPATIBILITY.md)、[隱私與網路說明](PRIVACY.md)和[第三方素材聲明](THIRD_PARTY.md)。

## 回報問題

使用 GitHub 的 Bug 或功能建議表單。回報問題時，註明 Wizard 版本/建置號、iPad 型號、iOS 版本、安裝環境和最短重現步驟。分享日誌或截圖前，移除使用者名稱、本機路徑、網路位址、憑證、序列號、UDID、私有安裝資訊和個人媒體。

## 準備改動

圍繞具體問題提交最小改動。適合主機驗證的行為應附迴歸檢查；UI 改動需分別說明使用的裝置型號/系統與原始碼、建置證據。主機迴歸或編譯成功不等於裝置驗收。

App 建置依賴自行通過 Apple 開發工具取得的 iPhoneOS SDK，儲存庫不提供 SDK。不要提交 SDK、簽章材料、私有安裝器、裝置記錄、個人照片，或來源/分發權利未經說明的素材。Wizard 自有程式碼採用 MIT，第三方素材保留各自條款。

## 執行檢查

主機檢查需要 macOS、Apple Clang 與 Python 3。在儲存庫根目錄執行：

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

這些檢查透過 fixture 與測試替身執行原始碼邏輯，不會安裝 App，也不證明原生呈現、私有系統符號、簽章、原版 iOS 或首次安裝相容。可選的雙架構裝置建置見[開發指南](DEVELOPMENT.md#建置)，需要你自行提供 `IOS_SDK`。

## Pull Request

按儲存庫 PR 模板說明使用者可見的變化、已執行檢查，並區分原始碼與建置證據與裝置驗收證據。納入第三方素材前，更新署名、授權與來源記錄。不要聲明超出證據的功能、相容性或發佈狀態。
