**简体中文** · [繁體中文](../zh-TW/DEVELOPMENT.md) · [English](../open-source/README.md) · [日本語](../ja/DEVELOPMENT.md)

# Wizard 源码与开发指南

本仓库包含 Wizard 这款旧版 Objective-C/UIKit 原生 iPad App、主机回归检查、打包与安装工具，以及一个可选电源 tweak。核心 App 与 tweak 是独立组件。

App 源码候选为 **0.2.0 / build 20261112.40**，源码与资源指纹为 `7dd43ae900a459683affaba05f7512f4e78e29e36db672be207f32440207a802`。截至 2026-11-12，该版本尚未安装到实体 iPad。GitHub 仓库为私有，所有 Release 均为草稿；素材清单记录的是已准备的草稿附件，不代表存在公开下载。

Wizard 自有代码使用根目录中的 [MIT License](../../LICENSE)。该许可证不涵盖第三方图片、字体、用户导入内容或其他素材。请参阅[第三方声明](THIRD_PARTY.md)和 [GTA VI 素材指南](../open-source/GTA6-MATERIALS.md)。贡献前可先阅读[贡献指南](CONTRIBUTING.md)。

## 构建

在 macOS 上使用 Apple Clang、Xcode 命令行工具，以及通过 Apple 开发工具取得的 iPhoneOS SDK。仓库和源码导出包均不包含 SDK。

```sh
IOS_SDK="/path/to/iPhoneOS9.3.sdk" ./scripts/build-ipad.sh
```

已验证的 SDK 为 iPhoneOS 9.3。脚本生成未签名的 `WizardSystem.app`，架构为 `armv7` 与 `arm64`，最低部署目标为 iOS 9.0。这些设置说明构建目标，不证明所有 iOS 9–12 设备都能运行。较新的 SDK 构建尚未验证，包括旧版 `armv7` 与 MediaPlayer 行为。

构建会将编译器与 SDK 信息、编译命令模板、源码输入哈希、写入 App plist 的组合指纹、产物哈希、架构和警告记录到 `BUILD-METADATA.txt`。编译期间若许可清单中的源码或资源发生变化，脚本会停止。脚本通过 `nm -u -j` 检查未定义符号；检查出错或 App 自有的 `IW` 符号仍未解析时，不会继续。旧式 `dynamic_lookup` 链接选项仍用于私有系统符号；主机编译成功不证明这些符号在设备上存在或可用。脚本不会签名或安装 App。

历史 build 20261112.39 的元数据模板漏记了链接参数中的 `CoreText`，虽然当时的构建脚本确实链接了该 framework。脚本中的模板已修正；此处的描述错误没有改变 App 源码指纹、打包产物或内置字体。

默认输出到新建的 `.private-audit` 子目录。可通过 `--out PATH` 指定不存在的输出目录；脚本不会清空已有目录。构建会包含已审核的 App 图标与横向启动图、署名明确的 `ViceCity.jpg` 默认图，以及静态 OFL 字体 `Anton-Regular.ttf` 和对应许可证。因此 App 中含有第三方素材；编译不需要另行下载 GTA VI 完整素材包或专有字体。Rockstar 图片不属于 MIT 许可证，详见 [GTA VI 素材指南](../open-source/GTA6-MATERIALS.md)。

## 运行主机检查

CI 使用 GitHub 的 `macos-15` runner。在仓库根目录运行以下相同检查：

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
```

最后八个命令是主机源码回归测试。前面的命令检查仓库内容、仓库检查器回归、打包与安装器 fixture，以及 Shell 语法。这些测试使用 fixture、抽取的生产方法和 UI double。CI 不会构建设备版 App，也不会下载或重新分发 Apple SDK。这些检查不会签名或安装 App，不验证原生渲染，也不会在设备上解析私有系统 API，不能替代实体设备验收。

## 构建原生模拟器预览

使用 Xcode 已安装的 Simulator SDK 构建单独的 iPad 模拟器预览：

```sh
python3 scripts/build-preview.py --out build-preview
```

脚本会生成标识符为 `com.rex.wizard.preview`、目标为 iOS 18 或更新版本的临时签名 `WizardPreview.app`，并在 `PREVIEW-METADATA.json` 中记录源码与资源指纹。它不会安装 App 或启动模拟器。预览素材位于该 App 容器内的 `Documents/WizardMedia`；设备版继续使用 `/var/mobile/Media/iPadWizard/app`。

仅在为本项目选定的专用模拟器上检查 UIKit 渲染或截图。[演示截图来源](../../assets/demo/README.md)中的八张 `*-miami.jpg` 来自 iOS 18 的 iPad 第 8 代模拟器。该页的三张 `*-ipad2.png` 是 build `20261111.36` 的早期实体截图，不代表当前候选版本。两组截图均不能证明旧版 iOS 兼容性。证据矩阵见[兼容性指南](../COMPATIBILITY.md)。

预览接受最多八个许可列表内的场景命令，通过 `WizardPreviewCommands` 传入。例如：

```sh
xcrun simctl launch --terminate-running-process SIMULATOR_UDID com.rex.wizard.preview \\
  -WizardPreviewCommands "main,settingsmenu"
xcrun simctl io SIMULATOR_UDID screenshot settings.png
```

截图前等待场景切换完成。命令序列示例：`main,menu`、`main,themesmenu`、`main,gallery,gallerycategories` 和 `main,clockedit`。该入口仅存在于模拟器构建，调用真实 App 操作并避免外部 URL 确认弹窗。它不会改变设备构建，也不会授权安装到设备。

## 运行时与安装边界

App 依赖普通应用容器之外的媒体与偏好路径。`App/main.m` 使用 `/var/mobile/Media/iPadWizard/app` 存放媒体和状态，并在 `/var/mobile/Library/Preferences` 下读写电源偏好。它会动态解析 Apple 私有 BackBoardServices、GraphicsServices 和 SpringBoardServices 框架中的符号。

这是根据源码推断的旧运行方式，不是 plist 授予的能力。全新安装和原生 iOS 侧载尚未验证。任何设备操作前，请先阅读[设备安装与运行时文件](../open-source/INSTALL.md)，了解已准备设备的有限更新范围及前置条件。编译成功、主机测试或模拟器截图均不代表安装成功或实体设备验收。

独立的 `App/WizardPowerTweak/` 使用私有 SpringBoard API，可能改变锁屏、唤醒和显示行为。`scripts/build-power.sh` 会为 `armv7` 和 `arm64` 构建它，但不签名、不安装，也不证明运行兼容性。核心 App 安装器不会安装该 tweak。详见其[组件指南](../../App/WizardPowerTweak/README.md)。

## 隐私与服务集成

构建或分发前请阅读[隐私与网络行为](PRIVACY.md)。App 会导入用户选择的照片、开放本地网络媒体控制服务，并可播放提供的 URL。`App/Info.plist` 设置了 `NSAllowsArbitraryLoads=true`；这不是安全审查，也不证明每条网络路径都可用。

天气卡片包含服务商署名控件。使用合成 fixture 的原生检查不代表实时服务兼容。Open-Meteo 传输和法律许可状态仍未验证；更改或描述该集成前，请阅读[第三方条款](THIRD_PARTY.md)。

## 准备本地源码导出包

在原始工作区运行：

```sh
python3 scripts/prepare-open-source.py
```

可用 `--out PATH` 指定一个尚不存在的输出目录。导出器按审核过的 allowlist 复制文件，写入 `OPEN_SOURCE_EXPORT_REPORT.json`，并检查常见工作站路径与凭据模式。这些检查不等于完整隐私或安全审查。导出器不会初始化 Git、访问网络、签名、安装或发布。iPhoneOS SDK、私有设备状态、凭据和用户照片不会进入源码导出包。

## 许可证与署名

Wizard 自有代码使用根目录 MIT License。Google Material 路径数据另依根目录 `NOTICE` 中的 Apache 2.0 声明。App 包含的显示字体及其 SIL OFL 1.1 许可证分别作为文件保留。GTA VI 图片、视频、截图及其衍生素材的版权属于 Rockstar Games 与相应权利人，不受 MIT 许可。详见 [GTA VI 素材指南](../open-source/GTA6-MATERIALS.md)、[演示截图来源](../../assets/demo/README.md)、[第三方声明](THIRD_PARTY.md)和[贡献指南](CONTRIBUTING.md)。

时间编辑新增“海报 / 系统”字体选择。`clockFontStyle` 稳定取值为 0/1，缺失或异常值保留海报字体；完成、取消和重置沿用既有编辑流程。日期、日历和天气语言 ID 仍为 0英语、1简体中文、2繁体中文、3日语，与文档展示顺序分开。
