# 参与贡献

**简体中文** · [繁體中文](../zh-TW/CONTRIBUTING.md) · [English](../../CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md)

提交改动前，请阅读[兼容性范围](COMPATIBILITY.md)、[隐私与网络说明](PRIVACY.md)和[第三方素材声明](THIRD_PARTY.md)。

## 报告问题

使用 GitHub 的 Bug 或功能建议表单。报告问题时，注明 Wizard 版本/构建号、iPad 型号、iOS 版本、安装环境和最短复现步骤。分享日志或截图前，移除用户名、本机路径、网络地址、凭据、序列号、UDID、私有安装信息和个人媒体。

## 准备改动

围绕具体问题提交最小改动。适合宿主机验证的行为应附回归检查；UI 改动需分别说明使用的设备型号/系统与源码、构建证据。宿主机回归或编译成功不等于设备验收。

App 构建依赖自行通过 Apple 开发工具获取的 iPhoneOS SDK，仓库不提供 SDK。不要提交 SDK、签名材料、私有安装器、设备记录、个人照片，或来源/分发权利未经说明的素材。Wizard 自有代码采用 MIT，第三方内容保留各自条款。

## 执行检查

宿主机检查需要 macOS、Apple Clang 与 Python 3。在仓库根目录执行：

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

这些检查通过夹具与替身执行源码逻辑，不会安装 App，也不证明原生显示、私有系统符号、签名、原版 iOS 或首次安装兼容。可选的双架构设备构建见[开发指南](DEVELOPMENT.md#构建)，需要你自行提供 `IOS_SDK`。

## Pull Request

按仓库 PR 模板说明用户可见的变化、已执行检查，并区分源码/构建证据与设备证据。引入第三方内容前，更新署名、许可与来源记录。不要声明超出证据的功能、兼容性或发布状态。
