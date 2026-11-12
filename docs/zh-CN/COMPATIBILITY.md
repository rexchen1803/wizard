# 兼容性与验证状态

**简体中文** · [繁體中文](../zh-TW/COMPATIBILITY.md) · [English](../COMPATIBILITY.md) · [日本語](../ja/COMPATIBILITY.md)

本指南区分构建证据、主机检查、模拟器截图与实体设备运行情况。以下状态以 2026-11-12 核对的 **Wizard 0.2.0 / build 20261112.40** 源码候选为准。该版本尚未安装到任何实体 iPad。App 源码与资源指纹为 `7dd43ae900a459683affaba05f7512f4e78e29e36db672be207f32440207a802`。

## 按环境查看证据

| 环境 | 已验证证据 | 证据边界 |
| --- | --- | --- |
| 设备构建目标 | App 声明的最低部署版本为 iOS 9.0。候选 build `20261112.40` 使用 iPhoneOS 9.3 SDK 在本机编译为 `armv7` 与 `arm64`。 | 部署目标和成功编译不代表已兼容 iOS 9–12、更新的 iOS 版本或任一设备运行环境。 |
| iPad（第 8 代）模拟器，iOS 18.0 | 单独的模拟器预览使用已安装的 iPhoneSimulator 27.1 SDK 构建，App 源码与资源指纹相同。八张 `*-miami.jpg` 与一张系统字体编辑图均为原生 UIKit 模拟器截图。 | 模拟器渲染不证明实体设备行为，也不代表 iOS 9–12 兼容性。 |
| macOS 主机与 CI | `macos-15` [CI 工作流](https://github.com/rexchen1803/wizard/actions/workflows/ci.yml)运行仓库、安装包、shell 语法检查和八个主机回归命令。 | 主机测试数据、抽取方法与 UIKit 替身不会构建或安装设备 App，也不证明原生渲染、签名、私有符号解析或实体设备行为。 |
| iPad 2，`iPad2,4`，iOS 9.3.5 | 较早的 build `20261111.30` 更新到已有、已准备的安装环境。记录的检查覆盖启动、菜单、图库、偏好保留、指定的动态效果、日历和编辑流程，以及实体照片选择与导入。 | 这是早期版本在已准备安装环境中的证据，不覆盖 build `.39`、全新安装、原生系统或越狱外环境、辅助功能及全部交互。 |
| iPad 4，`iPad3,4`，iOS 10.3.3 | 较早的 build `20261111.30` 更新到已有、已准备的安装环境。记录的检查覆盖指定 UI、日历、视频与媒体资源行为。 | 这是早期版本在已准备安装环境中的证据，不覆盖 build `.39`、全新安装、原生系统或越狱外环境、辅助功能及广泛日常使用。 |
| iPad Air，`iPad4,1`，iOS 12.5.8 | 较早的 build `20261111.36` 更新到已恢复并准备好的安装环境。记录了指定 UI 与媒体同步检查。 | 这是早期版本在已准备安装环境中的证据，不覆盖 build `.39`、全新安装、原生系统或越狱外环境、完整播放、辅助功能及广泛日常使用。 |
| 当前版本的实体 iPad 运行 | 尚无实体 iPad 安装过 build `20261112.40`。 | 不宣称当前版本已通过实体设备验收。 |
| 全新安装或原生 iOS | 没有已验证的安装路径。现有安装证据仅限已准备的 rootful 或 unsandboxed 设备。 | 尚未证明原生设备或首次安装所需的签名、注册、外部存储访问和私有框架行为。 |

已准备设备的验证范围及前置条件见[设备安装与运行时文件](../open-source/INSTALL.md)。[演示截图来源](../../assets/demo/README.md)中的 `home-ipad2.png`、`gallery-ipad2.png` 和 `categories-ipad2.png` 是 build `20261111.36` 的早期实体设备记录，不是 build `20261112.40` 的截图。当前 `*-miami.jpg` 则来自 iPad 第 8 代模拟器。

## 构建与主机检查

当前候选使用 iPhoneOS 9.3 SDK 构建设备版本。SDK 必须从 Apple 开发工具取得，源码仓库和导出包均不包含 SDK。更新 SDK 构建未经验证，包括其与旧版 MediaPlayer 接口及 `armv7` 的兼容性。详见[源码构建与贡献指南](../open-source/README.md#build)。

CI 是 macOS 主机任务，会运行仓库检查器及其回归用例、打包与安装器 fixture、Shell 语法检查，以及以下八个主机回归命令：

```sh
python3 tests/native-regressions.py
./App/tests/run-http-transport-regressions.sh
./App/tests/run-weather-service-regressions.sh
python3 App/tests/cast-lifecycle-regressions.py
python3 App/tests/media-lifecycle-regressions.py
python3 App/tests/gallery-media-regressions.py
python3 App/tests/menu-layout-regressions.py
python3 App/tests/power-edge-regressions.py
```

这些检查可用于发现源码回归，但不能替代在目标设备与系统版本上进行的安装、启动、交互、媒体、辅助功能和长时间运行检查。

## 运行时限制与可选组件

核心 App 从普通应用容器之外的 `/var/mobile/Media/iPadWizard/app` 和 `/var/mobile/Library/Preferences` 读取媒体与偏好文件。它会动态解析 Apple 私有 `BackBoardServices`、`GraphicsServices` 和 `SpringBoardServices` 框架中的符号。主机编译无法证明这些符号能在目标设备解析或正常工作。

可选的 `WizardPower` tweak 是独立组件，不属于核心 App 的安装流程，并使用私有 SpringBoard API。其构建、安装与运行验收需要分别审查；见[tweak 指南](../../App/WizardPowerTweak/README.md)。

iOS 18 模拟器中的视频检查显示了主题控件和推进的媒体时间，但录屏未包含解码后的视频画面。从同一个静音 fixture 提取的帧有效。该现象无法确定原因，也不代表实体设备播放情况。源码仍保留旧设备播放路径；不宣称 iOS 9–12 均可播放。

## 内置显示字体

Build `20261112.40` 的设备版与模拟器 App 都包含未修改的静态字体 `Anton-Regular.ttf` 及其 SIL OFL 1.1 许可证。`UIAppFonts` 注册该字体，模拟器截图元数据记录了实际解析到的名称 `Anton-Regular`，并确认字体来自 App 包。打包检查会拒绝缺失或变更的字体、许可证字节及缺失的字体注册。这验证的是打包输入，不代表旧款实体 iPad 上的渲染完全一致。

## 相关资料

- [源码构建与贡献指南](../open-source/README.md)
- [设备安装与运行时文件](../open-source/INSTALL.md)
- [模拟器和历史截图来源](../../assets/demo/README.md)
- [第三方素材与许可证](THIRD_PARTY.md)

时间编辑提供海报（内置 Anton）和系统（iOS 等宽数字）选项。[系统字体截图](../../assets/demo/clock-font-system.jpg)单独记录后者；完成保存，取消恢复编辑前的字体。
